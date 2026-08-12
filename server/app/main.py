from __future__ import annotations

import json
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from . import config
from .config import CONSENT_VERSION, MAX_SESSION_PAYLOAD_BYTES, validate_production_config
from .database import Base, engine, get_db
from .agent import complete_json
from .prompt_registry import CURRENT_V5_CORE_PROMPT_VERSION, turn_prompt_chat
from .models import ReflectionSession, SessionEvent, StudySchedule, User, utcnow
from .providers import gateway
from .schemas import (
    LoginIn,
    LLMChatIn,
    LLMChatOut,
    LLMTurnPromptIn,
    RegisterIn,
    SessionCreateIn,
    SessionCreatedOut,
    SessionSummaryOut,
    SessionUpdateIn,
    StudyAccessOut,
    StudyParticipantOut,
    StudyScheduleOut,
    StudyScheduleUpdateIn,
    UserOut,
)
from .security import clear_session_cookie, current_user, hash_password, set_session_cookie, verify_password


app = FastAPI(title="Beyond Comfort iOS API", version="1.0.0")


@app.on_event("startup")
async def startup() -> None:
    validate_production_config()
    Base.metadata.create_all(engine)
    await gateway.startup()


@app.on_event("shutdown")
async def shutdown() -> None:
    await gateway.aclose()


@app.get("/api/healthz")
def healthz() -> dict:
    return {"ok": True, "service": "beyond-comfort-ios-api", "version": app.version}


def user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        username=user.username,
        consentVersion=user.consent_version,
        consentedAt=user.consented_at,
    )


def require_study_admin(user: User = Depends(current_user)) -> User:
    if user.username.lower() not in config.STUDY_ADMIN_USERNAMES:
        raise HTTPException(403, "没有研究管理权限")
    return user


def as_utc(value: datetime) -> datetime:
    """Normalize database and request timestamps before schedule comparisons.

    SQLite does not round-trip timezone information from ``DateTime(timezone=True)``.
    Treat legacy naive values as UTC, while converting offset-aware request values to UTC.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def current_study_access(schedule: StudySchedule | None, now: datetime | None = None) -> StudyAccessOut:
    if schedule is None:
        return StudyAccessOut(status="unassigned", isAvailable=False)
    if not schedule.enabled:
        return StudyAccessOut(status="disabled", isAvailable=False, sequence=schedule.sequence)
    now = as_utc(now or utcnow())
    period_one_starts_at = (
        as_utc(schedule.period_one_starts_at) if schedule.period_one_starts_at is not None else None
    )
    period_two_starts_at = (
        as_utc(schedule.period_two_starts_at) if schedule.period_two_starts_at is not None else None
    )
    if period_one_starts_at is None or now < period_one_starts_at:
        return StudyAccessOut(
            status="scheduled",
            isAvailable=False,
            sequence=schedule.sequence,
            availableAt=period_one_starts_at,
        )
    if period_two_starts_at is not None and now >= period_two_starts_at:
        return StudyAccessOut(
            status="active",
            isAvailable=True,
            sequence=schedule.sequence,
            period=2,
            condition="modelAsserted" if schedule.sequence == "cardFirst" else "cardMediated",
            availableAt=period_two_starts_at,
        )
    return StudyAccessOut(
        status="active",
        isAvailable=True,
        sequence=schedule.sequence,
        period=1,
        condition="cardMediated" if schedule.sequence == "cardFirst" else "modelAsserted",
        availableAt=period_one_starts_at,
    )


def schedule_out(schedule: StudySchedule) -> StudyScheduleOut:
    access = current_study_access(schedule)
    return StudyScheduleOut(
        **access.model_dump(),
        userId=schedule.user_id,
        username=schedule.user.username,
        periodOneStartsAt=(
            as_utc(schedule.period_one_starts_at)
            if schedule.period_one_starts_at is not None
            else None
        ),
        periodTwoStartsAt=(
            as_utc(schedule.period_two_starts_at)
            if schedule.period_two_starts_at is not None
            else None
        ),
        enabled=schedule.enabled,
        updatedAt=schedule.updated_at,
    )


@app.post("/api/auth/register", response_model=UserOut, status_code=201)
def register(item: RegisterIn, response: Response, db: Session = Depends(get_db)) -> UserOut:
    if not item.consentAccepted:
        raise HTTPException(422, "必须先同意研究数据说明")
    user = User(
        username=item.username,
        password_hash=hash_password(item.password),
        consent_version=CONSENT_VERSION,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "这个用户名已被使用")
    db.refresh(user)
    set_session_cookie(response, user)
    return user_out(user)


@app.post("/api/auth/login", response_model=UserOut)
def login(item: LoginIn, response: Response, db: Session = Depends(get_db)) -> UserOut:
    username = item.username.strip().lower()
    user = db.scalar(select(User).where(User.username == username))
    if not user or not verify_password(item.password, user.password_hash):
        raise HTTPException(401, "用户名或密码不正确")
    set_session_cookie(response, user)
    return user_out(user)


@app.post("/api/auth/logout", status_code=204, response_class=Response)
def logout(response: Response) -> Response:
    clear_session_cookie(response)
    response.status_code = 204
    return response


@app.get("/api/auth/me", response_model=UserOut)
def me(user: User = Depends(current_user), db: Session = Depends(get_db)) -> UserOut:
    return user_out(user)


@app.get("/api/study/me", response_model=StudyAccessOut)
def study_me(user: User = Depends(current_user), db: Session = Depends(get_db)) -> StudyAccessOut:
    return current_study_access(db.get(StudySchedule, user.id))


@app.get("/api/admin/study-schedules", response_model=list[StudyScheduleOut])
def list_study_schedules(
    _: User = Depends(require_study_admin),
    db: Session = Depends(get_db),
) -> list[StudyScheduleOut]:
    schedules = db.scalars(select(StudySchedule).order_by(StudySchedule.updated_at.desc())).all()
    return [schedule_out(schedule) for schedule in schedules]


@app.get("/api/admin/study-participants", response_model=list[StudyParticipantOut])
def list_study_participants(
    admin: User = Depends(require_study_admin),
    db: Session = Depends(get_db),
) -> list[StudyParticipantOut]:
    participants = db.scalars(
        select(User).where(User.id != admin.id).order_by(User.username.asc())
    ).all()
    return [StudyParticipantOut(id=user.id, username=user.username) for user in participants]


@app.put("/api/admin/study-schedules/{participant_id}", response_model=StudyScheduleOut)
def set_study_schedule(
    participant_id: str,
    item: StudyScheduleUpdateIn,
    admin: User = Depends(require_study_admin),
    db: Session = Depends(get_db),
) -> StudyScheduleOut:
    participant = db.get(User, participant_id)
    if participant is None:
        raise HTTPException(404, "参与者不存在")
    if participant.id == admin.id:
        raise HTTPException(422, "管理员账号不能作为参与者排期")
    if (
        item.periodOneStartsAt is not None
        and item.periodTwoStartsAt is not None
        and as_utc(item.periodTwoStartsAt) <= as_utc(item.periodOneStartsAt)
    ):
        raise HTTPException(422, "第二期开始时间必须晚于第一期")
    schedule = db.get(StudySchedule, participant.id)
    if schedule is None:
        schedule = StudySchedule(user_id=participant.id, sequence=item.sequence)
        db.add(schedule)
    schedule.sequence = item.sequence
    schedule.period_one_starts_at = (
        as_utc(item.periodOneStartsAt) if item.periodOneStartsAt is not None else None
    )
    schedule.period_two_starts_at = (
        as_utc(item.periodTwoStartsAt) if item.periodTwoStartsAt is not None else None
    )
    schedule.enabled = item.enabled
    schedule.updated_by_user_id = admin.id
    db.commit()
    db.refresh(schedule)
    return schedule_out(schedule)


@app.post("/api/llm/chat", response_model=LLMChatOut)
async def llm_chat(item: LLMChatIn, _: User = Depends(current_user)) -> LLMChatOut:
    return LLMChatOut(content=await complete_json(item))


@app.post("/api/llm/turn", response_model=LLMChatOut)
async def llm_turn(item: LLMTurnPromptIn, _: User = Depends(current_user)) -> LLMChatOut:
    """Build the versioned current TurnController prompt entirely on the server."""
    if item.promptVersion == CURRENT_V5_CORE_PROMPT_VERSION:
        task_names = {
            "planner": "current_v5_core_planner",
            "writer": "current_v5_core_writer",
        }
    else:
        task_names = {
            "planner": "turn_controller_planner",
            "plan_critic": "turn_controller_plan_critic",
            "writer": "turn_controller_writer",
            "writer_critic": "turn_controller_critic",
            "writer_revision": "turn_controller_writer_revision",
        }
    if item.promptTask not in task_names:
        raise HTTPException(409, "prompt task is not available for this contract version")
    return LLMChatOut(
        content=await complete_json(
            turn_prompt_chat(item),
            agent_task_override=task_names[item.promptTask],
        )
    )


@app.post("/api/sessions", response_model=SessionCreatedOut, status_code=201)
def create_session(
    item: SessionCreateIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> SessionCreatedOut:
    access = current_study_access(db.get(StudySchedule, user.id))
    if not access.isAvailable:
        raise HTTPException(403, "当前没有管理员开放的研究体验")
    if (
        item.studySequence != access.sequence
        or item.studyPeriod != access.period
        or item.condition != access.condition
    ):
        raise HTTPException(422, "会话条件与当前管理员排期不匹配")
    session = ReflectionSession(
        user_id=user.id,
        condition=item.condition,
        payload={"context": item.context},
    )
    db.add(session)
    db.flush()
    db.add(SessionEvent(session_id=session.id, stage="orient", action="session_started"))
    db.commit()
    return SessionCreatedOut(sessionId=session.id, stage=session.stage)


@app.get("/api/sessions", response_model=list[SessionSummaryOut])
def list_sessions(
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> list[SessionSummaryOut]:
    sessions = db.scalars(
        select(ReflectionSession)
        .where(ReflectionSession.user_id == user.id)
        .order_by(ReflectionSession.updated_at.desc())
        .limit(100)
    ).all()
    return [
        SessionSummaryOut(
            id=session.id,
            stage=session.stage,
            createdAt=session.created_at,
            updatedAt=session.updated_at,
            payload=session.payload,
        )
        for session in sessions
    ]


def owned_session(db: Session, session_id: str, user_id: str) -> ReflectionSession:
    session = db.scalar(
        select(ReflectionSession).where(
            ReflectionSession.id == session_id,
            ReflectionSession.user_id == user_id,
        )
    )
    if not session:
        raise HTTPException(404, "反思记录不存在")
    return session


@app.patch("/api/sessions/{session_id}", response_model=SessionCreatedOut)
def update_session(
    session_id: str,
    item: SessionUpdateIn,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> SessionCreatedOut:
    payload_size = len(json.dumps(item.payload, ensure_ascii=False).encode("utf-8"))
    if payload_size > MAX_SESSION_PAYLOAD_BYTES:
        raise HTTPException(413, "反思记录过大，无法同步")
    session = owned_session(db, session_id, user.id)
    session.stage = item.stage
    session.payload = item.payload
    db.add(SessionEvent(session_id=session.id, stage=item.stage, action=item.action))
    db.commit()
    return SessionCreatedOut(sessionId=session.id, stage=session.stage)


@app.delete("/api/sessions/{session_id}", status_code=204, response_class=Response)
def delete_session(
    session_id: str,
    user: User = Depends(current_user),
    db: Session = Depends(get_db),
) -> Response:
    db.delete(owned_session(db, session_id, user.id))
    db.commit()
    return Response(status_code=204)
