from __future__ import annotations

from datetime import datetime
from typing import Any, Literal, Optional

from pydantic import BaseModel, Field, field_validator


class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=40, pattern=r"^[a-zA-Z0-9_-]+$")
    password: str = Field(min_length=10, max_length=128)
    consentAccepted: bool

    @field_validator("username")
    @classmethod
    def normalize_username(cls, value: str) -> str:
        return value.strip().lower()


class LoginIn(BaseModel):
    username: str = Field(min_length=3, max_length=40)
    password: str = Field(min_length=10, max_length=128)


class UserOut(BaseModel):
    id: str
    username: str
    consentVersion: str
    consentedAt: datetime


class StudyAccessOut(BaseModel):
    status: Literal["unassigned", "scheduled", "active", "disabled"]
    isAvailable: bool
    sequence: Optional[Literal["cardFirst", "directFirst"]] = None
    period: Optional[int] = None
    condition: Optional[Literal["cardMediated", "modelAsserted"]] = None
    availableAt: Optional[datetime] = None


class StudyScheduleUpdateIn(BaseModel):
    sequence: Literal["cardFirst", "directFirst"]
    periodOneStartsAt: Optional[datetime] = None
    periodTwoStartsAt: Optional[datetime] = None
    enabled: bool = True


class StudyParticipantOut(BaseModel):
    id: str
    username: str


class StudyScheduleOut(StudyAccessOut):
    userId: str
    username: str
    periodOneStartsAt: Optional[datetime] = None
    periodTwoStartsAt: Optional[datetime] = None
    enabled: bool
    updatedAt: datetime


class SessionCreateIn(BaseModel):
    condition: Literal["cardMediated", "modelAsserted"] = "cardMediated"
    context: dict[str, Any] = Field(default_factory=dict)
    studySequence: Optional[Literal["cardFirst", "directFirst"]] = None
    studyPeriod: Optional[int] = Field(default=None, ge=1, le=2)


class SessionUpdateIn(BaseModel):
    stage: str = Field(min_length=1, max_length=40)
    action: str = Field(min_length=1, max_length=80)
    payload: dict[str, Any] = Field(default_factory=dict)


class SessionCreatedOut(BaseModel):
    sessionId: str
    stage: str


class SessionSummaryOut(BaseModel):
    id: str
    stage: str
    createdAt: datetime
    updatedAt: datetime
    payload: dict[str, Any]


class LLMMessageIn(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str = Field(min_length=1, max_length=50_000)


class LLMChatIn(BaseModel):
    messages: list[LLMMessageIn] = Field(min_length=1, max_length=20)
    maxTokens: int = Field(default=700, ge=50, le=2_000)
    temperature: float = Field(default=0.2, ge=0, le=1)
    agentMode: Literal["fast", "balanced", "deep"] = "balanced"


class LLMTurnPromptIn(BaseModel):
    """Typed current-turn input; trusted prompt text is selected only by the server."""

    promptTask: Literal[
        "planner",
        "plan_critic",
        "writer",
        "writer_critic",
        "writer_revision",
    ]
    promptVersion: str = Field(min_length=1, max_length=80)
    payload: dict[str, Any]
    maxTokens: int = Field(default=700, ge=50, le=2_000)
    temperature: float = Field(default=0.2, ge=0, le=1)


class LLMChatOut(BaseModel):
    content: str
