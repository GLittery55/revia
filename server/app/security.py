from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt
from fastapi import Cookie, Depends, HTTPException, Response
from jwt import InvalidTokenError
from pwdlib import PasswordHash
from sqlalchemy.orm import Session

from .config import COOKIE_DOMAIN, COOKIE_SECURE, JWT_ALGORITHM, JWT_SECRET, SESSION_HOURS
from .database import get_db
from .models import User


password_hash = PasswordHash.recommended()
COOKIE_NAME = "bc_session"


def hash_password(password: str) -> str:
    return password_hash.hash(password)


def verify_password(password: str, encoded: str) -> bool:
    return password_hash.verify(password, encoded)


def set_session_cookie(response: Response, user: User) -> None:
    expires = datetime.now(timezone.utc) + timedelta(hours=SESSION_HOURS)
    token = jwt.encode({"sub": user.id, "exp": expires}, JWT_SECRET, algorithm=JWT_ALGORITHM)
    response.set_cookie(
        COOKIE_NAME,
        token,
        max_age=SESSION_HOURS * 3600,
        httponly=True,
        secure=COOKIE_SECURE,
        samesite="strict",
        domain=COOKIE_DOMAIN,
        path="/",
    )


def clear_session_cookie(response: Response) -> None:
    response.delete_cookie(COOKIE_NAME, domain=COOKIE_DOMAIN, path="/")


def current_user(
    bc_session: Optional[str] = Cookie(default=None),
    db: Session = Depends(get_db),
) -> User:
    if not bc_session:
        raise HTTPException(401, "请先登录")
    try:
        user_id = jwt.decode(bc_session, JWT_SECRET, algorithms=[JWT_ALGORITHM])["sub"]
    except (InvalidTokenError, KeyError):
        raise HTTPException(401, "登录已过期")
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(401, "用户不存在")
    return user
