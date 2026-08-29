"""Virtual Doctor trust boundary — the AI service half.

Before this boundary existed, `/virtual-doctor/*` was completely open: no
credential, no ownership check, and `user_id` taken from the request body. A
browser, a curl one-liner or anyone at all could start consultations, drive
someone else's session, and download another patient's report by id.

The backend paywall is UX. THIS is the security boundary, so these tests are
written as bypass attempts rather than as happy paths: they assert that a
direct caller — exactly what an attacker uses to skip the frontend and the
backend quota — gets nothing.

Runs entirely in-process against the FastAPI app with no database, because
every assertion here is about rejection: the boundary must refuse before any
handler, engine or query is reached.
"""

import os
import sys
import uuid
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

os.environ["AI_INTERNAL_TOKEN"] = "test-internal-token-for-boundary-tests"

from identity_boundary import (  # noqa: E402
    expected_internal_token,
    require_internal_identity,
    resolve_internal_identity,
)
from virtual_doctor.router import router  # noqa: E402


VALID_TOKEN = "test-internal-token-for-boundary-tests"
USER_ID = str(uuid.uuid4())
OTHER_USER_ID = str(uuid.uuid4())


@pytest.fixture()
def client():
    app = FastAPI()
    app.include_router(router)
    return TestClient(app, raise_server_exceptions=False)


def internal_headers(user_id=USER_ID, token=VALID_TOKEN):
    return {
        "X-MedOrbit-Internal-Token": token,
        "X-MedOrbit-User-Id": user_id,
    }


PROTECTED_ROUTES = [
    ("post", "/virtual-doctor/start", {"language": "en"}),
    ("post", "/virtual-doctor/message", {"session_id": "abc", "message": "hi"}),
    ("get", "/virtual-doctor/session/abc", None),
    ("post", "/virtual-doctor/report/abc", None),
    ("get", "/virtual-doctor/report/abc/download", None),
    ("post", "/virtual-doctor/speak", {"text": "hello", "language": "en"}),
    ("get", "/virtual-doctor/speak/status", None),
    ("post", "/virtual-doctor/speak/warmup", None),
    ("get", "/virtual-doctor/transcribe/status", None),
    ("post", "/virtual-doctor/transcribe/warmup", None),
]


class TestDirectAccessIsRefused:
    """The curl/Postman case: skip the frontend and the backend entirely."""

    @pytest.mark.parametrize("method,path,body", PROTECTED_ROUTES)
    def test_no_credential_is_refused(self, client, method, path, body):
        response = client.request(method.upper(), path, json=body)
        assert response.status_code == 403, (
            f"{method.upper()} {path} answered {response.status_code} without a credential"
        )

    @pytest.mark.parametrize("method,path,body", PROTECTED_ROUTES)
    def test_wrong_credential_is_refused(self, client, method, path, body):
        response = client.request(
            method.upper(), path, json=body, headers=internal_headers(token="wrong-token")
        )
        assert response.status_code == 403, (
            f"{method.upper()} {path} accepted a forged internal token"
        )

    def test_a_user_id_header_alone_proves_nothing(self, client):
        """The header is not the credential — the shared secret is.

        Without this, anyone who guessed the header name could impersonate any
        account by simply setting it.
        """
        response = client.post(
            "/virtual-doctor/start",
            json={"language": "en"},
            headers={"X-MedOrbit-User-Id": USER_ID},
        )
        assert response.status_code == 403

    def test_transcription_is_not_a_free_public_service(self, client):
        """STT is expensive. It must not be reachable without the credential."""
        response = client.post(
            "/virtual-doctor/transcribe",
            files={"audio": ("clip.webm", b"not-real-audio", "audio/webm")},
        )
        assert response.status_code == 403


class TestClientSuppliedIdentityIsRejected:
    """`user_id: null` was the old contract. Any client-supplied id is a forgery."""

    def test_payload_user_id_is_rejected_even_with_a_valid_credential(self, client):
        response = client.post(
            "/virtual-doctor/start",
            json={"language": "en", "user_id": OTHER_USER_ID},
            headers=internal_headers(),
        )
        assert response.status_code == 403
        assert "Client-supplied identity" in response.text

    def test_resolve_rejects_payload_identity_outright(self):
        with pytest.raises(Exception) as excinfo:
            resolve_internal_identity(OTHER_USER_ID, None, VALID_TOKEN, USER_ID, None)
        assert getattr(excinfo.value, "status_code", None) == 403


class TestRequireInternalIdentity:
    """The strict helper the Virtual Doctor uses, as distinct from the lenient one."""

    def test_absent_identity_is_a_hard_failure(self):
        """resolve_* permits anonymous; require_* must not.

        An unattributed consultation belongs to no account, enforces no
        entitlement, and is readable by anyone holding its id — which is
        precisely the state this whole change exists to end.
        """
        with pytest.raises(Exception) as excinfo:
            require_internal_identity(None, None, None)
        assert getattr(excinfo.value, "status_code", None) == 403

    def test_lenient_helper_still_permits_anonymous(self):
        """The endpoints that legitimately degrade to anonymous are unaffected."""
        assert resolve_internal_identity(None, None, None, None, None) == (None, None)

    def test_valid_credential_resolves_to_the_user(self):
        assert require_internal_identity(None, VALID_TOKEN, USER_ID) == USER_ID

    def test_a_malformed_user_id_is_refused(self):
        """A non-UUID id would otherwise reach a query as a raw string."""
        with pytest.raises(Exception) as excinfo:
            require_internal_identity(None, VALID_TOKEN, "'; DROP TABLE users; --")
        assert getattr(excinfo.value, "status_code", None) == 403

    def test_token_comparison_is_constant_time(self):
        """Guards against recovering the secret one byte at a time."""
        import inspect

        import identity_boundary

        source = inspect.getsource(identity_boundary.resolve_internal_identity)
        assert "compare_digest" in source, "internal token must not be compared with =="

    def test_a_near_miss_token_is_refused(self):
        almost = VALID_TOKEN[:-1] + ("x" if VALID_TOKEN[-1] != "x" else "y")
        with pytest.raises(Exception) as excinfo:
            require_internal_identity(None, almost, USER_ID)
        assert getattr(excinfo.value, "status_code", None) == 403

    def test_an_empty_token_is_refused(self):
        with pytest.raises(Exception) as excinfo:
            require_internal_identity(None, "", USER_ID)
        assert getattr(excinfo.value, "status_code", None) == 403


class TestCredentialDerivation:
    """The backend and the AI service must derive the same secret independently."""

    def test_explicit_token_wins(self):
        assert expected_internal_token() == VALID_TOKEN

    def test_derived_token_matches_the_backend_formula(self, monkeypatch):
        """Mirrors aiBoundary.service.js. If the two drift, every call 403s."""
        import hashlib

        monkeypatch.delenv("AI_INTERNAL_TOKEN", raising=False)
        monkeypatch.setenv("JWT_SECRET", "a-shared-development-secret")
        expected = hashlib.sha256(
            b"medorbit-ai-internal:a-shared-development-secret"
        ).hexdigest()
        assert expected_internal_token() == expected

    def test_no_secret_means_no_access(self, monkeypatch):
        """A misconfigured service must fail closed, never open."""
        monkeypatch.delenv("AI_INTERNAL_TOKEN", raising=False)
        monkeypatch.delenv("JWT_SECRET", raising=False)
        assert expected_internal_token() is None
        with pytest.raises(Exception) as excinfo:
            require_internal_identity(None, "any-token", USER_ID)
        assert getattr(excinfo.value, "status_code", None) == 403


class TestOwnershipIsPartOfTheLookup:
    """Session and report lookups are scoped to the owner, not filtered after."""

    def test_engine_scopes_message_lookup_to_the_owner(self):
        import inspect

        from virtual_doctor import interview_engine

        source = inspect.getsource(interview_engine.handle_message)
        assert "owner_user_id" in source
        assert "AND user_id = $2" in source, (
            "handle_message must scope the session query to the owner"
        )

    def test_engine_scopes_session_state_to_the_owner(self):
        import inspect

        from virtual_doctor import interview_engine

        source = inspect.getsource(interview_engine.get_session_state)
        assert "AND user_id = $2" in source

    def test_report_download_joins_through_the_owning_session(self):
        import inspect

        from virtual_doctor import report_generator

        source = inspect.getsource(report_generator.get_report_pdf_path)
        assert "JOIN virtual_doctor_sessions" in source, (
            "a report id must not be a bearer token for a medical document"
        )
        assert "s.user_id = $2" in source

    def test_report_generation_checks_ownership_before_building(self):
        """Ownership must be checked before any medical data is read or rendered."""
        import inspect

        from virtual_doctor import report_generator

        source = inspect.getsource(report_generator.generate_report)
        ownership_at = source.find("AND user_id = $2")
        build_at = source.find("build_report_data")
        assert ownership_at != -1, "generate_report must scope to the owner"
        assert ownership_at < build_at, (
            "ownership must be verified before the report is built"
        )


class TestRouterCoverage:
    """A new endpoint on this router must not be able to forget the boundary."""

    def test_router_carries_a_blanket_identity_dependency(self):
        assert router.dependencies, "the router must declare a router-level dependency"

    def test_every_route_is_covered(self, client):
        """Belt and braces: sweep the router's own route table."""
        skipped = {"/virtual-doctor/reasoning/health"}
        for route in router.routes:
            path = getattr(route, "path", "")
            if path in skipped:
                continue
            for method in getattr(route, "methods", set()) - {"HEAD", "OPTIONS"}:
                probe = path.replace("{session_id}", "x").replace("{report_id}", "x")
                response = client.request(method, probe)
                assert response.status_code == 403, (
                    f"{method} {path} is reachable without the internal credential"
                )
