from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, JSON, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def new_id(prefix: str) -> str:
    return f"{prefix}_{uuid4().hex}"


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("usr"))
    username: Mapped[str] = mapped_column(String(40), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    consent_version: Mapped[str] = mapped_column(String(50))
    consented_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    sessions: Mapped[list["ReflectionSession"]] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True
    )
    study_assignment: Mapped["StudyAssignment | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True, uselist=False
    )


class StudyAssignment(Base):
    """A durable, server-owned crossover order for one account.

    This separate table is additive: deployment creates it without rewriting or discarding the
    existing users and reflection_sessions tables.
    """

    __tablename__ = "study_assignments"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    sequence: Mapped[str] = mapped_column(String(20))
    assigned_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    user: Mapped["User"] = relationship(back_populates="study_assignment")


class StudySchedule(Base):
    """Administrator-controlled crossover availability for one participant.

    This is deliberately a new table instead of new columns on users or the legacy assignment
    table, so deployment is additive and does not rewrite collected research records.
    """

    __tablename__ = "study_schedules"

    user_id: Mapped[str] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    sequence: Mapped[str] = mapped_column(String(20))
    period_one_starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    period_two_starts_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_by_user_id: Mapped[Optional[str]] = mapped_column(String(40), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user: Mapped["User"] = relationship()


class ReflectionSession(Base):
    __tablename__ = "reflection_sessions"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("ses"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    condition: Mapped[str] = mapped_column(String(30), default="cardMediated")
    stage: Mapped[str] = mapped_column(String(40), default="orient")
    payload: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, onupdate=utcnow)

    user: Mapped[User] = relationship(back_populates="sessions")
    events: Mapped[list["SessionEvent"]] = relationship(
        back_populates="session", cascade="all, delete-orphan", passive_deletes=True
    )

    __table_args__ = (Index("ix_reflection_sessions_user_updated", "user_id", "updated_at"),)


class SessionEvent(Base):
    __tablename__ = "session_events"

    id: Mapped[str] = mapped_column(String(40), primary_key=True, default=lambda: new_id("evt"))
    session_id: Mapped[str] = mapped_column(ForeignKey("reflection_sessions.id", ondelete="CASCADE"), index=True)
    stage: Mapped[str] = mapped_column(String(40))
    action: Mapped[str] = mapped_column(String(80))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    session: Mapped[ReflectionSession] = relationship(back_populates="events")
