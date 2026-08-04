# Beyond Comfort iOS API deployment

Only `server/` and `server-deploy/` are deployed. The SwiftUI application remains on the Mac and iPhone.

## First deployment

```bash
cd /root/apps/BeyondComfort/server-deploy
cp .env.example .env
chmod 600 .env
docker compose up -d --build
curl http://127.0.0.1:8000/api/healthz
```

Use `nginx-http.conf.example` before requesting the IP certificate. After the certificate is issued, replace it with `nginx-https.conf.example`.

Never run `docker compose down -v` after participant data has been collected; `-v` deletes the PostgreSQL volume.

## DeepSeek-first multi-model agent

`/api/llm/chat` runs a private `Planner -> Writer -> Critic` pipeline while preserving the iOS
response contract. Each role uses DeepSeek first. A connection error, timeout, invalid/empty JSON,
authentication error, rate limit, or upstream error opens a short DeepSeek circuit and routes the
current and immediately following roles to OpenAI. A normal DeepSeek response is not replaced merely
because its wording is imperfect; the Critic requests one Writer revision instead.

Set these values in `/etc/beyondcomfort/api.env` (native deployment) or `server-deploy/.env`
(Docker deployment):

```dotenv
AGENT_ENABLED=true
AGENT_CRITIC_ENABLED=true
DEEPSEEK_API_KEY=your-deepseek-key
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-pro
DEEPSEEK_TIMEOUT_SECONDS=45
DEEPSEEK_FAILURE_THRESHOLD=3
DEEPSEEK_FAILURE_WINDOW_SECONDS=30
DEEPSEEK_HALF_OPEN_AFTER_SECONDS=5
DEEPSEEK_MAX_CONCURRENCY=6
DEEPSEEK_QUEUE_TIMEOUT_SECONDS=20
PROVIDER_HTTP_MAX_CONNECTIONS=24
PROVIDER_HTTP_MAX_KEEPALIVE_CONNECTIONS=12
PROVIDER_HTTP_KEEPALIVE_EXPIRY_SECONDS=30
OPENAI_API_KEY=your-openai-key
OPENAI_BASE_URL=https://api.openai.com/v1
OPENAI_MODEL=gpt-5-mini
OPENAI_TIMEOUT_SECONDS=25
OPENAI_FAILURE_COOLDOWN_SECONDS=60
```

OpenAI is optional. If it is configured, requests use it while the DeepSeek circuit is open. In a
DeepSeek-only deployment, leave `OPENAI_API_KEY` empty; waiting requests then use the bounded
half-open probe path instead of failing immediately because another request opened the circuit.
Environment values must be stored in the service environment file; values exported only in an SSH
shell are not inherited by `beyondcomfort-api` after that shell exits.

DeepSeek requests use a bounded asynchronous queue. A single timeout affects only its own request;
the circuit opens only after the configured number of availability failures inside the configured
window. Once open, one request performs a half-open probe. If no fallback provider is configured,
other requests wait within the bounded queue timeout instead of immediately inheriting the first
request's failure.

Planner, Writer, and Critic calls reuse one process-wide asynchronous HTTP connection pool instead
of creating a new TCP/TLS connection for every role call. The pool is created during FastAPI
startup and closed during shutdown.

The API response contains only the final content. Provider, model, completion ID, and token usage are
kept out of the iOS response. Provider selection is visible only in server logs:

```bash
journalctl -u beyondcomfort-api -f | grep -E 'agent_role_completed|deepseek_fallback|deepseek_circuit_opened|deepseek_half_open_probe|deepseek_circuit_closed|deepseek_queue_timeout|openai_unavailable'
```
