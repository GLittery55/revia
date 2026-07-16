from __future__ import annotations

import hashlib
import json
import os
import random
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "static"
DB_PATH = os.getenv("DATABASE_PATH", str(ROOT / "beyondcomfort.db"))
DEVICE_TOKEN = os.getenv("DEVICE_TOKEN", "")
MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-chat")
STAGES = {
    "tenderGrounding", "tenderExploration", "candidInquiry", "actionComposer"
}

app = FastAPI(title="Beyond Comfort API", version="0.1.0")
origins = [x.strip() for x in os.getenv("ALLOWED_ORIGINS", "http://localhost:8000").split(",") if x.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["GET", "POST", "DELETE"], allow_headers=["*"])
app.mount("/static", StaticFiles(directory=STATIC), name="static")


def db() -> sqlite3.Connection:
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS observations (
      id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, captured_at TEXT NOT NULL,
      timezone TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS observations_token_time ON observations(token_hash, captured_at DESC);
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, stage TEXT NOT NULL,
      payload TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS study_events (
      id TEXT PRIMARY KEY, session_id TEXT NOT NULL, stage TEXT NOT NULL,
      action TEXT NOT NULL, created_at TEXT NOT NULL
    );
    """)
    return conn


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def auth(authorization: str | None = Header(default=None)) -> str:
    if not DEVICE_TOKEN:
        raise HTTPException(503, "DEVICE_TOKEN has not been configured")
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Bearer token required")
    supplied = authorization[7:]
    if not secrets_equal(supplied, DEVICE_TOKEN):
        raise HTTPException(403, "Invalid device token")
    return hashlib.sha256(supplied.encode()).hexdigest()


def secrets_equal(a: str, b: str) -> bool:
    import hmac
    return hmac.compare_digest(a.encode(), b.encode())


class HealthSummary(BaseModel):
    sleepMinutes: float | None = Field(default=None, ge=0, le=1440)
    sleepBaselineMinutes: float | None = Field(default=None, ge=0, le=1440)
    restingHeartRate: float | None = Field(default=None, ge=20, le=250)
    restingHeartRateBaseline: float | None = Field(default=None, ge=20, le=250)
    hrvSDNN: float | None = Field(default=None, ge=0, le=1000)
    hrvBaselineSDNN: float | None = Field(default=None, ge=0, le=1000)


class CalendarSummary(BaseModel):
    eventCount: int | None = Field(default=None, ge=0, le=500)
    scheduledMinutes: float | None = Field(default=None, ge=0, le=1440)
    baselineScheduledMinutes: float | None = Field(default=None, ge=0, le=1440)


class ObservationIn(BaseModel):
    schemaVersion: Literal[1] = 1
    capturedAt: datetime
    timezone: str = "Asia/Shanghai"
    health: HealthSummary = HealthSummary()
    calendar: CalendarSummary = CalendarSummary()


class SessionIn(BaseModel):
    condition: Literal["cardMediated", "modelAsserted"] = "cardMediated"
    context: dict = {}


class ReflectIn(BaseModel):
    stage: Literal["tenderGrounding", "tenderExploration", "candidInquiry", "actionComposer"]
    context: dict
    contextualClues: list[dict] = []
    recentDialogue: list[dict] = []
    cardInterpretation: str = ""


@app.get("/")
def home():
    return FileResponse(STATIC / "index.html")


@app.get("/healthz")
def healthz():
    return {"ok": True, "model": MODEL, "deepSeekConfigured": bool(os.getenv("DEEPSEEK_API_KEY"))}


@app.post("/api/v1/observations", status_code=201)
def save_observation(item: ObservationIn, token_hash: str = Depends(auth)):
    oid = f"obs_{uuid.uuid4().hex}"
    conn = db()
    conn.execute("INSERT INTO observations VALUES (?,?,?,?,?,?)", (oid, token_hash, item.capturedAt.isoformat(), item.timezone, item.model_dump_json(), now()))
    conn.commit(); conn.close()
    return {"accepted": True, "observationId": oid, "clues": clues(item)}


@app.get("/api/v1/observations/latest")
def latest_observation(token_hash: str = Depends(auth)):
    conn = db()
    row = conn.execute("SELECT payload FROM observations WHERE token_hash=? ORDER BY captured_at DESC LIMIT 1", (token_hash,)).fetchone()
    conn.close()
    if not row:
        return {"observation": None, "clues": []}
    item = ObservationIn.model_validate_json(row["payload"])
    return {"observation": item, "clues": clues(item)}


def clues(item: ObservationIn) -> list[dict]:
    out: list[dict] = []
    pairs = [
        ("sleep", item.health.sleepMinutes, item.health.sleepBaselineMinutes, "睡眠时长"),
        ("restingHeartRate", item.health.restingHeartRate, item.health.restingHeartRateBaseline, "静息心率"),
        ("hrv", item.health.hrvSDNN, item.health.hrvBaselineSDNN, "HRV（SDNN）"),
        ("calendarLoad", item.calendar.scheduledMinutes, item.calendar.baselineScheduledMinutes, "日程负荷"),
    ]
    for source, value, baseline, label in pairs:
        if value is None:
            continue
        if not baseline:
            text = f"{label}已有记录，但个人基线不足"
        else:
            pct = round((value - baseline) / baseline * 100)
            direction = "接近" if abs(pct) < 5 else ("高于" if pct > 0 else "低于")
            text = f"{label}{direction}近期个人基线约 {abs(pct)}%"
        out.append({"source": source, "observation": text, "certainty": "clue_only"})
    return out


@app.post("/api/v1/sessions", status_code=201)
def create_session(item: SessionIn, token_hash: str = Depends(auth)):
    sid = f"ses_{uuid.uuid4().hex}"
    ts = now(); payload = item.model_dump_json()
    conn = db()
    conn.execute("INSERT INTO sessions VALUES (?,?,?,?,?,?)", (sid, token_hash, "orient", payload, ts, ts))
    conn.execute("INSERT INTO study_events VALUES (?,?,?,?,?)", (uuid.uuid4().hex, sid, "orient", "session_started", ts))
    conn.commit(); conn.close()
    return {"sessionId": sid, "stage": "orient"}


@app.get("/api/v1/cards/draw")
def draw_card(_: str = Depends(auth)):
    index = random.SystemRandom().randrange(22)
    return {"id": index, "neutralLabel": f"Reflection Card {index + 1:02d}", "imageUrl": f"/static/cards/m{index:02d}.jpg"}


@app.post("/api/v1/reflect")
async def reflect(item: ReflectIn, _: str = Depends(auth)):
    key = os.getenv("DEEPSEEK_API_KEY", "").strip()
    if not key or key == "YOUR_DEEPSEEK_API_KEY":
        raise HTTPException(503, "DeepSeek API key has not been configured")
    prompt = system_prompt(item.stage)
    user_input = item.model_dump_json(exclude={"stage"})
    payload = {"model": MODEL, "temperature": 0.2, "max_tokens": 900, "response_format": {"type": "json_object"}, "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": user_input}]}
    async with httpx.AsyncClient(timeout=45) as client:
        response = await client.post("https://api.deepseek.com/chat/completions", headers={"Authorization": f"Bearer {key}"}, json=payload)
    if response.status_code >= 400:
        raise HTTPException(502, f"DeepSeek request failed ({response.status_code})")
    try:
        content = response.json()["choices"][0]["message"]["content"]
        return json.loads(content)
    except (KeyError, IndexError, json.JSONDecodeError) as exc:
        raise HTTPException(502, "DeepSeek returned invalid structured output") from exc


def system_prompt(stage: str) -> str:
    return f"""
You support a card-mediated self-compassion reflection at stage {stage}. Return JSON only:
{{"reflectiveSummary":"","uncertaintyStatement":"","question":"","hypotheses":[],"actionSuggestions":[]}}
Use a tender, steady, therapist-informed voice without claiming to provide therapy. Do not repeat or paraphrase the user's latest words. Tender self-compassion comes before fierce inquiry. Treat sleep, resting heart rate, HRV, and calendar observations only as uncertain clues: use may/might/one clue, mention alternatives, never diagnose or claim causation. Never infer conventional tarot meaning. The user interprets the ambiguous card first.
Only candidInquiry may return up to two hedged hypotheses. Only actionComposer may return 2-4 small non-punitive options as {{"type":"care|repair|protection|change","text":"","rationale":""}}. In other stages those arrays must be empty. Ask one gentle question. Never prescribe confrontation.
""".strip()

