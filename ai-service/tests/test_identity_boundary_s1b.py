import os
import sys
import unittest
import uuid
from pathlib import Path

from fastapi import HTTPException

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from identity_boundary import expected_internal_token, resolve_internal_identity


class IdentityBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.previous_token = os.environ.get("AI_INTERNAL_TOKEN")
        self.previous_jwt = os.environ.get("JWT_SECRET")
        os.environ["AI_INTERNAL_TOKEN"] = "test-internal-secret"

    def tearDown(self):
        if self.previous_token is None:
            os.environ.pop("AI_INTERNAL_TOKEN", None)
        else:
            os.environ["AI_INTERNAL_TOKEN"] = self.previous_token
        if self.previous_jwt is None:
            os.environ.pop("JWT_SECRET", None)
        else:
            os.environ["JWT_SECRET"] = self.previous_jwt

    def test_direct_payload_identity_is_rejected(self):
        with self.assertRaises(HTTPException) as caught:
            resolve_internal_identity(str(uuid.uuid4()), None, None, None, None)
        self.assertEqual(caught.exception.status_code, 403)

    def test_spoofed_internal_context_is_rejected(self):
        with self.assertRaises(HTTPException) as caught:
            resolve_internal_identity(None, None, "wrong", str(uuid.uuid4()), None)
        self.assertEqual(caught.exception.status_code, 403)

    def test_valid_internal_context_is_accepted(self):
        user_id = str(uuid.uuid4())
        record_id = str(uuid.uuid4())
        self.assertEqual(
            resolve_internal_identity(None, None, expected_internal_token(), user_id, record_id),
            (user_id, record_id),
        )

    def test_anonymous_context_remains_available(self):
        self.assertEqual(resolve_internal_identity(None, None, None, None, None), (None, None))


if __name__ == "__main__":
    unittest.main()
