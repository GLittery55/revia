# Beyond Comfort remote study deployment

The web application is split into three independently replaceable layers:

- `frontend/`: static participant UI served by Nginx
- `backend/`: FastAPI authentication, study API, ownership checks, and DeepSeek proxy
- PostgreSQL: durable user-owned observations, sessions, and events

The original `web/` directory is the legacy single-user prototype. Do not deploy it for participant studies.

## Security model

- Registration uses a pseudonymous study username and a password hashed with Argon2.
- Browser authentication is a 12-hour `HttpOnly`, `SameSite=Strict` cookie.
- Shortcut uploads use a separate random bearer token. Only its SHA-256 hash is stored.
- Reissuing a Shortcut token revokes the previous token.
- User ownership comes only from the validated cookie or token. API payloads cannot choose `user_id`.
- Account deletion cascades to that user's Shortcut tokens, observations, sessions, and study events.
- DeepSeek and database credentials exist only in `deploy/.env` on the server.

## Local or ECS Docker start

From the repository root:

```bash
cd deploy
cp .env.example .env
```

Generate secrets:

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(48))"
```

Use different generated values for `POSTGRES_PASSWORD` and `JWT_SECRET`. If the database password contains URL-special characters, URL-encode it in `DATABASE_URL`. Fill in `DEEPSEEK_API_KEY`, then start:

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f backend
```

The compose port is bound to `127.0.0.1:8080`; it is not public. Test on the server with:

```bash
curl http://127.0.0.1:8080/api/healthz
```

For a remote study, put the host Nginx configuration in `deploy/host-nginx.conf.example` behind a real domain and trusted TLS certificate. Set these production values:

```env
COOKIE_SECURE=true
COOKIE_DOMAIN=study.your-domain.example
ALLOWED_ORIGINS=https://study.your-domain.example
```

Only ports 80 and 443 should be public. Keep PostgreSQL, backend port 8000, and frontend container port 8080 private.

## Update on ECS

```bash
cd ~/apps/BeyondComfort
git pull --ff-only
cd deploy
docker compose up -d --build
```

Do not overwrite the server's `deploy/.env` during updates.

## Shortcut upload

After registering, open **Account**, generate the one-time Shortcut token, and configure the Shortcut request:

```text
POST https://study.your-domain.example/api/observations
Authorization: Bearer bc_<participant-specific-token>
Content-Type: application/json
```

Body:

```json
{
  "schemaVersion": 1,
  "capturedAt": "2026-07-16T09:00:00+08:00",
  "timezone": "Asia/Shanghai",
  "health": {
    "sleepMinutes": 405,
    "sleepBaselineMinutes": 435,
    "restingHeartRate": 68,
    "restingHeartRateBaseline": 64,
    "hrvSDNN": 42,
    "hrvBaselineSDNN": 47
  },
  "calendar": {
    "eventCount": 6,
    "scheduledMinutes": 420,
    "baselineScheduledMinutes": 330
  }
}
```

Never include calendar titles, notes, contacts, or raw HealthKit samples.

