from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator


class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=40, pattern=r"^[a-zA-Z0-9_-]+$")
    password: str = Field(min_length=10, max_length=128)
    consentAccepted: bool

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str):
        return value.strip().lower()


class LoginIn(BaseModel):
    username: str
    password: str


class HealthSummary(BaseModel):
    sleepMinutes: Optional[float] = Field(default=None, ge=0, le=1440)
    sleepBaselineMinutes: Optional[float] = Field(default=None, ge=0, le=1440)
    restingHeartRate: Optional[float] = Field(default=None, ge=20, le=250)
    restingHeartRateBaseline: Optional[float] = Field(default=None, ge=20, le=250)
    hrvSDNN: Optional[float] = Field(default=None, ge=0, le=1000)
    hrvBaselineSDNN: Optional[float] = Field(default=None, ge=0, le=1000)


class CalendarSummary(BaseModel):
    eventCount: Optional[int] = Field(default=None, ge=0, le=500)
    scheduledMinutes: Optional[float] = Field(default=None, ge=0, le=1440)
    baselineScheduledMinutes: Optional[float] = Field(default=None, ge=0, le=1440)


class ObservationIn(BaseModel):
    schemaVersion: Literal[1] = 1
    capturedAt: datetime
    timezone: str = Field(default="Asia/Shanghai", max_length=80)
    health: HealthSummary = HealthSummary()
    calendar: CalendarSummary = CalendarSummary()


class SessionIn(BaseModel):
    condition: Literal["cardMediated", "modelAsserted"] = "cardMediated"
    context: dict = {}


class SessionUpdate(BaseModel):
    stage: str = Field(max_length=40)
    action: str = Field(max_length=80)
    payload: dict = {}


class ReflectIn(BaseModel):
    sessionId: str
    stage: Literal["tenderGrounding", "tenderExploration", "candidInquiry", "actionComposer"]
    context: dict
    contextualClues: list[dict] = []
    recentDialogue: list[dict] = []
    cardInterpretation: str = Field(default="", max_length=5000)
