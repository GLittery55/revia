from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, JSON, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def utcnow():
    return datetime.now(timezone.utc)


def new_id(prefix: str):
    return f"{prefix}_{uuid4().hex}"


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("usr"))
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    consent_version: Mapped[str] = mapped_column(String(50))
    consented_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    device_tokens: Mapped[list["DeviceToken"]] = relationship(cascade="all, delete-orphan")
    observations: Mapped[list["Observation"]] = relationship(cascade="all, delete-orphan")
    sessions: Mapped[list["ReflectionSession"]] = relationship(cascade="all, delete-orphan")


class DeviceToken(Base):
    __tablename__ = "device_tokens"
    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("dev"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    label: Mapped[str] = mapped_column(String(80), default="iPhone Shortcut")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_used_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))


class Observation(Base):
    __tablename__ = "observations"
    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("obs"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    captured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    timezone: Mapped[str] = mapped_column(String(80))
    payload: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    __table_args__ = (Index("ix_observations_user_captured", "user_id", "captured_at"),)


class ReflectionSession(Base):
    __tablename__ = "reflection_sessions"
    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("ses"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    condition: Mapped[str] = mapped_column(String(30), default="cardMediated")
    stage: Mapped[str] = mapped_column(String(40), default="orient")
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)
    events: Mapped[list["StudyEvent"]] = relationship(cascade="all, delete-orphan")


class StudyEvent(Base):
    __tablename__ = "study_events"
    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("evt"))
    session_id: Mapped[str] = mapped_column(ForeignKey("reflection_sessions.id", ondelete="CASCADE"), index=True)
    stage: Mapped[str] = mapped_column(String(40))
    action: Mapped[str] = mapped_column(String(80))
    detail: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
