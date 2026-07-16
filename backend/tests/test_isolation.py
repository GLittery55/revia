import os
import tempfile
import unittest
import uuid

database_file = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
database_file.close()
os.environ["DATABASE_URL"] = f"sqlite:///{database_file.name}"
os.environ["JWT_SECRET"] = "test-secret-that-is-long-enough-for-tests"

from fastapi.testclient import TestClient
from app.main import app
from app.database import Base, engine

Base.metadata.create_all(engine)


class UserIsolationTests(unittest.TestCase):
    def setUp(self):
        self.alice = TestClient(app)
        self.bob = TestClient(app)
        suffix = uuid.uuid4().hex[:8]
        for client, username in [(self.alice, f"alice-{suffix}"), (self.bob, f"bob-{suffix}")]:
            response = client.post("/api/auth/register", json={"username": username, "password": "correct-horse-battery", "consentAccepted": True})
            self.assertEqual(response.status_code, 201, response.text)

    def test_observations_are_owned_by_token_user(self):
        token = self.alice.post("/api/device-tokens").json()["token"]
        payload = {"schemaVersion": 1, "capturedAt": "2026-07-16T08:00:00+08:00", "timezone": "Asia/Shanghai", "health": {"sleepMinutes": 400, "sleepBaselineMinutes": 450}, "calendar": {}}
        uploaded = self.alice.post("/api/observations", json=payload, headers={"Authorization": f"Bearer {token}"})
        self.assertEqual(uploaded.status_code, 201, uploaded.text)
        self.assertIsNotNone(self.alice.get("/api/observations/latest").json()["observation"])
        self.assertIsNone(self.bob.get("/api/observations/latest").json()["observation"])

    def test_user_cannot_modify_another_users_session(self):
        session_id = self.alice.post("/api/sessions", json={"condition": "cardMediated", "context": {}}).json()["sessionId"]
        response = self.bob.patch(f"/api/sessions/{session_id}", json={"stage": "tenderGrounding", "action": "attempted", "payload": {}})
        self.assertEqual(response.status_code, 404)

    def test_rotating_device_token_revokes_old_token(self):
        first = self.alice.post("/api/device-tokens").json()["token"]
        self.alice.post("/api/device-tokens")
        payload = {"schemaVersion": 1, "capturedAt": "2026-07-16T08:00:00+08:00", "health": {}, "calendar": {}}
        response = self.alice.post("/api/observations", json=payload, headers={"Authorization": f"Bearer {first}"})
        self.assertEqual(response.status_code, 403)


if __name__ == "__main__":
    unittest.main()
