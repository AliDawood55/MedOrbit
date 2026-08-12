import hashlib
import hmac
import os
import uuid
from typing import Optional

from fastapi import HTTPException


def expected_internal_token() -> Optional[str]:
    configured = os.environ.get("AI_INTERNAL_TOKEN")
    if configured:
        return configured
    jwt_secret = os.environ.get("JWT_SECRET")
    if not jwt_secret:
        return None
    return hashlib.sha256(f"medorbit-ai-internal:{jwt_secret}".encode()).hexdigest()


def resolve_internal_identity(
    payload_user_id: Optional[str],
    payload_record_id: Optional[str],
    internal_token: Optional[str],
    internal_user_id: Optional[str],
    internal_record_id: Optional[str],
) -> tuple[Optional[str], Optional[str]]:
    if payload_user_id or payload_record_id:
        raise HTTPException(status_code=403, detail="Client-supplied identity is not accepted")

    if not internal_user_id and not internal_record_id:
        return None, None

    expected = expected_internal_token()
    if not expected or not internal_token or not hmac.compare_digest(internal_token, expected):
        raise HTTPException(status_code=403, detail="Invalid internal identity context")
    if internal_record_id and not internal_user_id:
        raise HTTPException(status_code=403, detail="Record context requires a user context")

    try:
        if internal_user_id:
            uuid.UUID(internal_user_id)
        if internal_record_id:
            uuid.UUID(internal_record_id)
    except ValueError:
        raise HTTPException(status_code=403, detail="Invalid internal identity context")

    return internal_user_id, internal_record_id
