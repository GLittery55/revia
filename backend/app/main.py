from __future__ import annotations

import json
import os
import random
from datetime import datetime, timezone

import httpx
from fastapi import Depends, FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .database import Base, engine, get_db
from .models import DeviceToken, Observation, ReflectionSession, StudyEvent, User, utcnow
from .schemas import LoginIn, ObservationIn, ReflectIn, RegisterIn, SessionIn, SessionUpdate
from .security import clear_session_cookie, current_user, device_user, hash_password, new_device_token, set_session_cookie, verify_password

app = FastAPI(title="Beyond Comfort API", version="1.0.0")
origins = [v.strip() for v in os.getenv("ALLOWED_ORIGINS", "http://localhost:8080").split(",") if v.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=True, allow_methods=["GET", "POST", "PATCH", "DELETE"], allow_headers=["Content-Type", "Authorization"])


@app.on_event("startup")
def create_tables():
    Base.metadata.create_all(engine)


@app.get("/api/healthz")
def healthz():
    return {"ok": True, "model": os.getenv("DEEPSEEK_MODEL", "deepseek-chat"), "deepSeekConfigured": bool(os.getenv("DEEPSEEK_API_KEY"))}


@app.post("/api/auth/register", status_code=201)
def register(item: RegisterIn, response: Response, db: Session = Depends(get_db)):
    if not item.consentAccepted:
        raise HTTPException(422, "必须先阅读并同意研究说明")
    user = User(username=item.username, password_hash=hash_password(item.password), consent_version=os.getenv("CONSENT_VERSION", "pilot-v1"))
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback(); raise HTTPException(409, "这个实验用户名已被使用")
    db.refresh(user); set_session_cookie(response, user)
    return public_user(user)


@app.post("/api/auth/login")
def login(item: LoginIn, response: Response, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.username == item.username.strip().lower()))
    if not user or not verify_password(item.password, user.password_hash):
        raise HTTPException(401, "用户名或密码不正确")
    set_session_cookie(response, user)
    return public_user(user)


@app.post("/api/auth/logout", status_code=204)
def logout(response: Response):
    clear_session_cookie(response)


@app.get("/api/auth/me")
def me(user: User = Depends(current_user)):
    return public_user(user)


def public_user(user: User):
    return {"id": user.id, "username": user.username, "consentVersion": user.consent_version, "consentedAt": user.consented_at}


@app.post("/api/device-tokens")
def rotate_device_token(user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.execute(delete(DeviceToken).where(DeviceToken.user_id == user.id))
    raw, digest = new_device_token()
    db.add(DeviceToken(user_id=user.id, token_hash=digest))
    db.commit()
    return {"token": raw, "warning": "令牌只显示一次；重新生成会立即撤销旧令牌"}


@app.delete("/api/device-tokens", status_code=204)
def revoke_device_tokens(user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.execute(delete(DeviceToken).where(DeviceToken.user_id == user.id)); db.commit()


@app.post("/api/observations", status_code=201)
def upload_observation(item: ObservationIn, user: User = Depends(device_user), db: Session = Depends(get_db)):
    observation = Observation(user_id=user.id, captured_at=item.capturedAt, timezone=item.timezone, payload=item.model_dump(mode="json"))
    db.add(observation); db.commit(); db.refresh(observation)
    return {"accepted": True, "observationId": observation.id, "clues": make_clues(item)}


@app.get("/api/observations/latest")
def latest_observation(user: User = Depends(current_user), db: Session = Depends(get_db)):
    row = db.scalar(select(Observation).where(Observation.user_id == user.id).order_by(Observation.captured_at.desc()).limit(1))
    if not row:
        return {"observation": None, "clues": []}
    item = ObservationIn.model_validate(row.payload)
    return {"observation": row.payload, "clues": make_clues(item)}


def make_clues(item: ObservationIn):
    pairs = [
        ("sleep", item.health.sleepMinutes, item.health.sleepBaselineMinutes, "睡眠时长"),
        ("restingHeartRate", item.health.restingHeartRate, item.health.restingHeartRateBaseline, "静息心率"),
        ("hrv", item.health.hrvSDNN, item.health.hrvBaselineSDNN, "HRV（SDNN）"),
        ("calendarLoad", item.calendar.scheduledMinutes, item.calendar.baselineScheduledMinutes, "日程负荷"),
    ]
    clues = []
    for source, value, baseline, label in pairs:
        if value is None:
            continue
        if not baseline:
            text = f"{label}已有记录，但个人基线不足"
        else:
            pct = round((value - baseline) / baseline * 100)
            direction = "接近" if abs(pct) < 5 else ("高于" if pct > 0 else "低于")
            text = f"{label}{direction}近期个人基线约 {abs(pct)}%"
        clues.append({"source": source, "observation": text, "certainty": "clue_only"})
    return clues


@app.post("/api/sessions", status_code=201)
def create_session(item: SessionIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    session = ReflectionSession(user_id=user.id, condition=item.condition, payload={"context": item.context})
    db.add(session); db.flush(); db.add(StudyEvent(session_id=session.id, stage="orient", action="session_started")); db.commit(); db.refresh(session)
    return {"sessionId": session.id, "stage": session.stage}


@app.patch("/api/sessions/{session_id}")
def update_session(session_id: str, item: SessionUpdate, user: User = Depends(current_user), db: Session = Depends(get_db)):
    session = owned_session(db, session_id, user.id)
    session.stage = item.stage; session.payload = item.payload
    db.add(StudyEvent(session_id=session.id, stage=item.stage, action=item.action)); db.commit()
    return {"sessionId": session.id, "stage": session.stage}


@app.delete("/api/sessions/{session_id}", status_code=204)
def delete_session(session_id: str, user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.delete(owned_session(db, session_id, user.id)); db.commit()


@app.delete("/api/account", status_code=204)
def delete_account(response: Response, user: User = Depends(current_user), db: Session = Depends(get_db)):
    db.delete(user); db.commit(); clear_session_cookie(response)


def owned_session(db: Session, session_id: str, user_id: str):
    session = db.scalar(select(ReflectionSession).where(ReflectionSession.id == session_id, ReflectionSession.user_id == user_id))
    if not session:
        raise HTTPException(404, "会话不存在")
    return session


@app.get("/api/cards/draw")
def draw_card(_: User = Depends(current_user)):
    index = random.SystemRandom().randrange(22)
    return {"id": index, "neutralLabel": f"Reflection Card {index + 1:02d}", "imageUrl": f"/cards/m{index:02d}.jpg"}


@app.post("/api/reflect")
async def reflect(item: ReflectIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    session = owned_session(db, item.sessionId, user.id)
    key = os.getenv("DEEPSEEK_API_KEY", "").strip()
    if not key or key == "YOUR_DEEPSEEK_API_KEY":
        raise HTTPException(503, "DeepSeek API key尚未配置")
    payload = {"model": os.getenv("DEEPSEEK_MODEL", "deepseek-chat"), "temperature": 0.2, "max_tokens": 900, "response_format": {"type": "json_object"}, "messages": [{"role": "system", "content": system_prompt(item.stage)}, {"role": "user", "content": item.model_dump_json(exclude={"sessionId", "stage"})}]}
    async with httpx.AsyncClient(timeout=45) as client:
        result = await client.post("https://api.deepseek.com/chat/completions", headers={"Authorization": f"Bearer {key}"}, json=payload)
    if result.status_code >= 400:
        raise HTTPException(502, f"DeepSeek请求失败（{result.status_code}）")
    try:
        content = json.loads(result.json()["choices"][0]["message"]["content"])
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        raise HTTPException(502, "DeepSeek返回格式无法解析") from exc
    session.stage = item.stage
    db.add(StudyEvent(session_id=session.id, stage=item.stage, action="llm_response_generated")); db.commit()
    return content


def system_prompt(stage: str):
    return f"""You support a card-mediated self-compassion reflection at stage {stage}. Return JSON only: {{"reflectiveSummary":"","uncertaintyStatement":"","question":"","hypotheses":[],"actionSuggestions":[]}}. Use a tender, steady, therapist-informed voice without claiming to provide therapy. Do not repeat the user's latest words. Tender self-compassion comes before fierce inquiry. Treat sleep, resting heart rate, HRV and calendar observations only as uncertain clues; mention alternatives, never diagnose or claim causation. Never infer conventional tarot meaning. Only candidInquiry may return up to two hedged hypotheses. Only actionComposer may return 2-4 small non-punitive care, repair, protection or change suggestions. Ask one gentle question. Never prescribe confrontation."""

