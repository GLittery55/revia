from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt
from fastapi import Cookie, Depends, Header, HTTPException, Response
from pwdlib import PasswordHash
from sqlalchemy import select
from sqlalchemy.orm import Session

from .database import get_db
from .models import DeviceToken, User, utcnow

password_hash = PasswordHash.recommended()
JWT_SECRET = os.getenv("JWT_SECRET", "development-only-change-me")
JWT_ALGORITHM = "HS256"
COOKIE_SECURE = os.getenv("COOKIE_SECURE", "false").lower() == "true"
COOKIE_DOMAIN = os.getenv("COOKIE_DOMAIN") or None


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, encoded: str) -> bool:
    return password_hash.verify(password, encoded)


def set_session_cookie(response: Response, user: User):
    expires = datetime.now(timezone.utc) + timedelta(hours=12)
    token = jwt.encode({"sub": user.id, "exp": expires}, JWT_SECRET, algorithm=JWT_ALGORITHM)
    response.set_cookie("bc_session", token, max_age=43200, httponly=True, secure=COOKIE_SECURE, samesite="strict", domain=COOKIE_DOMAIN, path="/")


def clear_session_cookie(response: Response):
    response.delete_cookie("bc_session", domain=COOKIE_DOMAIN, path="/")


def current_user(bc_session: Optional[str] = Cookie(default=None), db: Session = Depends(get_db)) -> User:
    if not bc_session:
        raise HTTPException(401, "请先登录")
    try:
        user_id = jwt.decode(bc_session, JWT_SECRET, algorithms=[JWT_ALGORITHM])["sub"]
    except (jwt.PyJWTError, KeyError):
        raise HTTPException(401, "登录已过期")
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(401, "用户不可用")
    return user


def new_device_token() -> tuple[str, str]:
    raw = "bc_" + secrets.token_urlsafe(40)
    return raw, hashlib.sha256(raw.encode()).hexdigest()


def device_user(authorization: Optional[str] = Header(default=None), db: Session = Depends(get_db)) -> User:
    if not authorization or not authorization.startswith("Bearer bc_"):
        raise HTTPException(401, "快捷指令令牌缺失")
    digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
    record = db.scalar(select(DeviceToken).where(DeviceToken.token_hash == digest, DeviceToken.revoked_at.is_(None)))
    if not record:
        raise HTTPException(403, "快捷指令令牌无效")
    record.last_used_at = utcnow()
    user = db.get(User, record.user_id)
    if not user or not user.is_active:
        raise HTTPException(403, "用户不可用")
    return user
