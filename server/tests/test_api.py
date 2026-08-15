from __future__ import annotations

import os
import tempfile
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch


database_file = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
database_file.close()
os.environ["DATABASE_URL"] = f"sqlite:///{database_file.name}"
os.environ["JWT_SECRET"] = "test-secret-that-is-long-enough"
os.environ["COOKIE_SECURE"] = "false"

from fastapi.testclient import TestClient

from app import config

# Test modules can be imported in either order; refresh the already-imported config module before
# database.py creates its engine.
config.DATABASE_URL = os.environ["DATABASE_URL"]
config.JWT_SECRET = os.environ["JWT_SECRET"]
config.COOKIE_SECURE = False

from app.database import Base, engine
from app.main import app
from app.prompt_registry import TURN_PROMPT_VERSION


Base.metadata.create_all(engine)


class APITests(unittest.TestCase):
    def setUp(self) -> None:
        self.alice = TestClient(app)
        self.bob = TestClient(app)
        self.manager = TestClient(app)
        self.registration_users: dict[str, dict] = {}
        suffix = uuid.uuid4().hex[:8]
        self.alice_username = f"alice-{suffix}"
        self.bob_username = f"bob-{suffix}"
        self.manager_username = f"manager-{suffix}"
        for client, username in (
            (self.alice, self.alice_username),
            (self.bob, self.bob_username),
            (self.manager, self.manager_username),
        ):
            response = client.post(
                "/api/auth/register",
                json={"username": username, "password": "correct-horse-battery", "consentAccepted": True},
            )
            self.assertEqual(response.status_code, 201, response.text)
            self.registration_users[username] = response.json()
        config.STUDY_ADMIN_USERNAMES = frozenset({self.manager_username})
        alice_id = self.alice.get("/api/auth/me").json()["id"]
        response = self.manager.put(
            f"/api/admin/study-schedules/{alice_id}",
            json={
                "sequence": "cardFirst",
                "periodOneStartsAt": (datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat(),
                "enabled": True,
            },
        )
        self.assertEqual(response.status_code, 200, response.text)

    def test_registration_hashes_password_and_restores_cookie_session(self) -> None:
        response = self.alice.get("/api/auth/me")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(response.json()["username"].startswith("alice-"))
        study = self.alice.get("/api/study/me").json()
        self.assertEqual(study["status"], "active")
        self.assertEqual(study["condition"], "cardMediated")

    def test_auth_user_dates_use_second_precision_utc(self) -> None:
        login = self.alice.post(
            "/api/auth/login",
            json={"username": self.alice_username, "password": "correct-horse-battery"},
        )
        self.assertEqual(login.status_code, 200, login.text)

        current_user = self.alice.get("/api/auth/me")
        self.assertEqual(current_user.status_code, 200, current_user.text)

        for payload in (
            self.registration_users[self.alice_username],
            login.json(),
            current_user.json(),
        ):
            self.assertRegex(
                payload["consentedAt"],
                r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$",
            )

    def test_chat_payload_persists_and_is_isolated(self) -> None:
        session_id = self.alice.post(
            "/api/sessions",
            json={"condition": "cardMediated", "studySequence": "cardFirst", "studyPeriod": 1, "context": {}},
        ).json()["sessionId"]
        payload = {
            "messages": [
                {"role": "user", "content": "private disclosure"},
                {"role": "assistant", "content": "private response"},
            ],
            "trackingCues": [],
            "cardInterpretation": "",
        }
        updated = self.alice.patch(
            f"/api/sessions/{session_id}",
            json={"stage": "contextGathering", "action": "assistant_message", "payload": payload},
        )
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(self.alice.get("/api/sessions").json()[0]["payload"], payload)
        self.assertEqual(self.bob.get("/api/sessions").json(), [])

    def test_other_user_cannot_update_or_delete_session(self) -> None:
        session_id = self.alice.post(
            "/api/sessions",
            json={"condition": "cardMediated", "studySequence": "cardFirst", "studyPeriod": 1, "context": {}},
        ).json()["sessionId"]
        update = self.bob.patch(
            f"/api/sessions/{session_id}",
            json={"stage": "orient", "action": "attempt", "payload": {}},
        )
        self.assertEqual(update.status_code, 404)
        self.assertEqual(self.bob.delete(f"/api/sessions/{session_id}").status_code, 404)

    def test_study_session_rejects_a_condition_that_does_not_match_its_period(self) -> None:
        response = self.alice.post(
            "/api/sessions",
            json={
                "condition": "modelAsserted",
                "studySequence": "cardFirst",
                "studyPeriod": 1,
                "context": {},
            },
        )
        self.assertEqual(response.status_code, 422)

    def test_admin_controls_participant_schedule_and_second_period_switch(self) -> None:
        bob_id = self.bob.get("/api/auth/me").json()["id"]
        first_start = datetime.now(timezone.utc) - timedelta(days=7)
        second_start = datetime.now(timezone.utc) - timedelta(minutes=1)
        response = self.manager.put(
            f"/api/admin/study-schedules/{bob_id}",
            json={
                "sequence": "directFirst",
                "periodOneStartsAt": first_start.isoformat(),
                "periodTwoStartsAt": second_start.isoformat(),
                "enabled": True,
            },
        )
        self.assertEqual(response.status_code, 200, response.text)
        access = self.bob.get("/api/study/me")
        self.assertEqual(access.status_code, 200, access.text)
        self.assertEqual(access.json()["period"], 2)
        self.assertEqual(access.json()["condition"], "cardMediated")
        self.assertEqual(
            self.alice.get("/api/admin/study-schedules").status_code,
            403,
        )
        participants = self.manager.get("/api/admin/study-participants")
        self.assertEqual(participants.status_code, 200, participants.text)
        participant_names = {item["username"] for item in participants.json()}
        self.assertIn(self.alice_username, participant_names)
        self.assertIn(self.bob_username, participant_names)
        self.assertNotIn(self.manager_username, participant_names)

    def test_logout_invalidates_cookie(self) -> None:
        self.assertEqual(self.alice.post("/api/auth/logout").status_code, 204)
        self.assertEqual(self.alice.get("/api/auth/me").status_code, 401)

    def test_llm_proxy_requires_login_and_returns_content_only(self) -> None:
        payload = {
            "messages": [
                {"role": "system", "content": "Return JSON"},
                {"role": "user", "content": "hello"},
            ],
            "maxTokens": 350,
            "temperature": 0.1,
        }
        anonymous = TestClient(app)
        self.assertEqual(anonymous.post("/api/llm/chat", json=payload).status_code, 401)
        with patch("app.main.complete_json", new=AsyncMock(return_value='{"accepted":true}')):
            response = self.alice.post("/api/llm/chat", json=payload)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json(), {"content": '{"accepted":true}'})

    def test_llm_proxy_accepts_messages_up_to_fifty_thousand_characters(self) -> None:
        payload = {
            "messages": [{"role": "system", "content": "x" * 50_000}],
            "maxTokens": 350,
            "temperature": 0.1,
        }
        with patch("app.main.complete_json", new=AsyncMock(return_value='{"accepted":true}')):
            response = self.alice.post("/api/llm/chat", json=payload)
        self.assertEqual(response.status_code, 200, response.text)

    def test_llm_proxy_accepts_turn_planner_token_budget(self) -> None:
        payload = {
            "messages": [{"role": "system", "content": "Return JSON"}],
            "maxTokens": 1_600,
            "temperature": 0.28,
            "agentMode": "fast",
        }
        with patch("app.main.complete_json", new=AsyncMock(return_value='{"accepted":true}')):
            response = self.alice.post("/api/llm/chat", json=payload)
        self.assertEqual(response.status_code, 200, response.text)

    def test_typed_turn_endpoint_requires_login_and_builds_server_prompt(self) -> None:
        payload = {
            "promptTask": "planner",
            "promptVersion": TURN_PROMPT_VERSION,
            "payload": {
                "request": {
                    "trigger": "userMessage",
                    "protocolStage": "contextualDisclosure",
                    "condition": "cardMediated",
                    "permissions": {
                        "currentStage": "contextualDisclosure",
                        "allowedStages": ["contextualDisclosure"],
                        "allowedActions": ["none"],
                        "allowedReplyIntents": ["exploreContext"],
                    },
                    "recentMessages": [],
                    "semanticMemory": {},
                    "trackingCandidates": [],
                    "cardMappingConfirmed": False,
                }
            },
            "maxTokens": 1_600,
            "temperature": 0.28,
        }
        anonymous = TestClient(app)
        self.assertEqual(anonymous.post("/api/llm/turn", json=payload).status_code, 401)
        with patch("app.main.complete_json", new=AsyncMock(return_value='{"ok":true}')) as complete:
            response = self.alice.post("/api/llm/turn", json=payload)
        self.assertEqual(response.status_code, 200, response.text)
        sent = complete.await_args.args[0]
        self.assertEqual(sent.agentMode, "fast")
        self.assertIn("private semantic TurnPlanner", sent.messages[0].content)
        self.assertEqual(
            complete.await_args.kwargs["agent_task_override"],
            "turn_controller_planner",
        )
        self.assertNotIn("messages", payload)

    def test_typed_turn_endpoint_rejects_unknown_prompt_version(self) -> None:
        payload = {
            "promptTask": "planner",
            "promptVersion": "unknown",
            "payload": {"request": {}},
            "maxTokens": 700,
            "temperature": 0.2,
        }
        response = self.alice.post("/api/llm/turn", json=payload)
        self.assertEqual(response.status_code, 409, response.text)

    def test_llm_proxy_rejects_token_budget_above_server_limit(self) -> None:
        payload = {
            "messages": [{"role": "system", "content": "Return JSON"}],
            "maxTokens": 2_001,
            "temperature": 0.28,
            "agentMode": "fast",
        }
        response = self.alice.post("/api/llm/chat", json=payload)
        self.assertEqual(response.status_code, 422, response.text)

    def test_llm_proxy_rejects_messages_over_fifty_thousand_characters(self) -> None:
        payload = {
            "messages": [{"role": "system", "content": "x" * 50_001}],
            "maxTokens": 350,
            "temperature": 0.1,
        }
        response = self.alice.post("/api/llm/chat", json=payload)
        self.assertEqual(response.status_code, 422, response.text)


if __name__ == "__main__":
    unittest.main()
