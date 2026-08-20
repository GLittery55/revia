from __future__ import annotations

import os


DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql+psycopg://beyondcomfort:beyondcomfort@db:5432/beyondcomfort",
)
JWT_SECRET = os.getenv("JWT_SECRET", "development-only-change-me")
JWT_ALGORITHM = "HS256"
SESSION_HOURS = int(os.getenv("SESSION_HOURS", "168"))
COOKIE_SECURE = os.getenv("COOKIE_SECURE", "true").lower() == "true"
COOKIE_DOMAIN = os.getenv("COOKIE_DOMAIN") or None
CONSENT_VERSION = os.getenv("CONSENT_VERSION", "pilot-v1")
MAX_SESSION_PAYLOAD_BYTES = int(os.getenv("MAX_SESSION_PAYLOAD_BYTES", "524288"))
# Comma-separated account names permitted to operate the study-management API. Keeping this in
# deployment configuration avoids granting researcher privileges through the participant client.
STUDY_ADMIN_USERNAMES = frozenset(
    name.strip().lower()
    for name in os.getenv("STUDY_ADMIN_USERNAMES", "").split(",")
    if name.strip()
)

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5-mini").strip() or "gpt-5-mini"
OPENAI_PLANNER_MODEL = os.getenv("OPENAI_PLANNER_MODEL", OPENAI_MODEL).strip() or OPENAI_MODEL
OPENAI_WRITER_MODEL = os.getenv("OPENAI_WRITER_MODEL", OPENAI_MODEL).strip() or OPENAI_MODEL
OPENAI_CRITIC_MODEL = os.getenv("OPENAI_CRITIC_MODEL", OPENAI_MODEL).strip() or OPENAI_MODEL
OPENAI_PLANNER_REASONING_EFFORT = os.getenv(
    "OPENAI_PLANNER_REASONING_EFFORT", "low"
).strip().lower()
OPENAI_WRITER_REASONING_EFFORT = os.getenv(
    "OPENAI_WRITER_REASONING_EFFORT", "low"
).strip().lower()
OPENAI_CRITIC_REASONING_EFFORT = os.getenv(
    "OPENAI_CRITIC_REASONING_EFFORT", "low"
).strip().lower()
OPENAI_TIMEOUT_SECONDS = float(os.getenv("OPENAI_TIMEOUT_SECONDS", "25"))
OPENAI_FAILURE_COOLDOWN_SECONDS = float(
    os.getenv("OPENAI_FAILURE_COOLDOWN_SECONDS", "60")
)

DEEPSEEK_API_KEY = os.getenv("DEEPSEEK_API_KEY", "").strip()
DEEPSEEK_MODEL = os.getenv("DEEPSEEK_MODEL", "deepseek-v4-pro").strip() or "deepseek-v4-pro"
DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com").rstrip("/")
DEEPSEEK_PLANNER_MODEL = os.getenv("DEEPSEEK_PLANNER_MODEL", DEEPSEEK_MODEL).strip() or DEEPSEEK_MODEL
DEEPSEEK_WRITER_MODEL = os.getenv("DEEPSEEK_WRITER_MODEL", DEEPSEEK_MODEL).strip() or DEEPSEEK_MODEL
DEEPSEEK_CRITIC_MODEL = os.getenv("DEEPSEEK_CRITIC_MODEL", DEEPSEEK_MODEL).strip() or DEEPSEEK_MODEL
DEEPSEEK_PLANNER_THINKING = os.getenv("DEEPSEEK_PLANNER_THINKING", "enabled").strip().lower()
DEEPSEEK_WRITER_THINKING = os.getenv("DEEPSEEK_WRITER_THINKING", "disabled").strip().lower()
DEEPSEEK_CRITIC_THINKING = os.getenv("DEEPSEEK_CRITIC_THINKING", "disabled").strip().lower()
DEEPSEEK_PLANNER_REASONING_EFFORT = os.getenv("DEEPSEEK_PLANNER_REASONING_EFFORT", "high").strip().lower()
DEEPSEEK_WRITER_REASONING_EFFORT = os.getenv("DEEPSEEK_WRITER_REASONING_EFFORT", "high").strip().lower()
DEEPSEEK_CRITIC_REASONING_EFFORT = os.getenv("DEEPSEEK_CRITIC_REASONING_EFFORT", "high").strip().lower()
DEEPSEEK_TIMEOUT_SECONDS = float(os.getenv("DEEPSEEK_TIMEOUT_SECONDS", "45"))
# DeepSeek availability protection is deliberately threshold based. One user's isolated timeout
# must not suspend the provider for every other participant.
DEEPSEEK_FAILURE_THRESHOLD = int(os.getenv("DEEPSEEK_FAILURE_THRESHOLD", "3"))
DEEPSEEK_FAILURE_WINDOW_SECONDS = float(
    os.getenv("DEEPSEEK_FAILURE_WINDOW_SECONDS", "30")
)
DEEPSEEK_HALF_OPEN_AFTER_SECONDS = float(
    os.getenv("DEEPSEEK_HALF_OPEN_AFTER_SECONDS", "5")
)
DEEPSEEK_MAX_CONCURRENCY = int(os.getenv("DEEPSEEK_MAX_CONCURRENCY", "6"))
DEEPSEEK_QUEUE_TIMEOUT_SECONDS = float(
    os.getenv("DEEPSEEK_QUEUE_TIMEOUT_SECONDS", "20")
)
# One application-wide async HTTP pool serves all provider roles. The DeepSeek semaphore still
# controls request admission; these limits only bound reusable sockets and idle keep-alive
# connections so concurrent participants do not create a new TCP/TLS connection per agent call.
PROVIDER_HTTP_MAX_CONNECTIONS = int(
    os.getenv("PROVIDER_HTTP_MAX_CONNECTIONS", "24")
)
PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS = int(
    os.getenv("PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS", "12")
)
PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS = float(
    os.getenv("PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS", "30")
)
PROVIDER_RETRY_ATTEMPTS = int(os.getenv("PROVIDER_RETRY_ATTEMPTS", "2"))
PROVIDER_RETRY_BACKOFF_SECONDS = float(os.getenv("PROVIDER_RETRY_BACKOFF_SECONDS", "0.4"))

AGENT_ENABLED = os.getenv("AGENT_ENABLED", "true").lower() == "true"
AGENT_CRITIC_ENABLED = os.getenv("AGENT_CRITIC_ENABLED", "true").lower() == "true"
# Temporary, privacy-bounded diagnostics for current-v5 Tracking selection. Disabled by default.
# The diagnostic logs compact aggregate/profile metadata and selected IDs only; it never logs the
# transcript, semantic memory, complete prompt, model body, or daily values.
CURRENT_V5_TRACKING_DIAGNOSTICS = (
    os.getenv("CURRENT_V5_TRACKING_DIAGNOSTICS", "false").lower() == "true"
)
# Temporary, privacy-bounded diagnostics for the first current-v5 Synthesis transaction. Disabled
# by default. The diagnostic records only JSON field presence/types, character counts, and whether
# Swift-style normalized deltas are equal; it never logs either delta, the transcript, semantic
# memory, a complete prompt, or a model body.
CURRENT_V5_SYNTHESIS_DIAGNOSTICS = (
    os.getenv("CURRENT_V5_SYNTHESIS_DIAGNOSTICS", "false").lower() == "true"
)


def validate_production_config() -> None:
    if JWT_SECRET == "development-only-change-me" and os.getenv("ENVIRONMENT") == "production":
        raise RuntimeError("JWT_SECRET must be configured in production")
    if not STUDY_ADMIN_USERNAMES and os.getenv("ENVIRONMENT") == "production":
        raise RuntimeError("STUDY_ADMIN_USERNAMES must include at least one researcher account")
    if PROVIDER_RETRY_ATTEMPTS < 1 or PROVIDER_RETRY_ATTEMPTS > 3:
        raise RuntimeError("PROVIDER_RETRY_ATTEMPTS must be between 1 and 3")
    if DEEPSEEK_FAILURE_THRESHOLD < 2 or DEEPSEEK_FAILURE_THRESHOLD > 10:
        raise RuntimeError("DEEPSEEK_FAILURE_THRESHOLD must be between 2 and 10")
    if DEEPSEEK_FAILURE_WINDOW_SECONDS <= 0:
        raise RuntimeError("DEEPSEEK_FAILURE_WINDOW_SECONDS must be positive")
    if DEEPSEEK_HALF_OPEN_AFTER_SECONDS <= 0:
        raise RuntimeError("DEEPSEEK_HALF_OPEN_AFTER_SECONDS must be positive")
    if DEEPSEEK_MAX_CONCURRENCY < 1 or DEEPSEEK_MAX_CONCURRENCY > 64:
        raise RuntimeError("DEEPSEEK_MAX_CONCURRENCY must be between 1 and 64")
    if DEEPSEEK_QUEUE_TIMEOUT_SECONDS <= 0:
        raise RuntimeError("DEEPSEEK_QUEUE_TIMEOUT_SECONDS must be positive")
    if PROVIDER_HTTP_MAX_CONNECTIONS < 1 or PROVIDER_HTTP_MAX_CONNECTIONS > 256:
        raise RuntimeError("PROVIDER_HTTP_MAX_CONNECTIONS must be between 1 and 256")
    if (
        PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS < 0
        or PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS > PROVIDER_HTTP_MAX_CONNECTIONS
    ):
        raise RuntimeError(
            "PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS must be between 0 and "
            "PROVIDER_HTTP_MAX_CONNECTIONS"
        )
    if PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS <= 0:
        raise RuntimeError("PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS must be positive")
    for role in ("PLANNER", "WRITER", "CRITIC"):
        effort = globals()[f"OPENAI_{role}_REASONING_EFFORT"]
        if effort not in {"none", "low", "medium", "high"}:
            raise RuntimeError(
                f"OPENAI_{role}_REASONING_EFFORT must be none, low, medium, or high"
            )
    for role in ("PLANNER", "WRITER", "CRITIC"):
        thinking = globals()[f"DEEPSEEK_{role}_THINKING"]
        if thinking not in {"enabled", "disabled"}:
            raise RuntimeError(
                f"DEEPSEEK_{role}_THINKING must be enabled or disabled"
            )
        effort = globals()[f"DEEPSEEK_{role}_REASONING_EFFORT"]
        if effort not in {"high", "max"}:
            raise RuntimeError(
                f"DEEPSEEK_{role}_REASONING_EFFORT must be high or max"
            )
