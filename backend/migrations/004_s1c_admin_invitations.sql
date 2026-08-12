CREATE TABLE medorbit.admin_invitations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(320) NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,
    invited_by_user_id UUID NOT NULL REFERENCES medorbit.users(id),
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ NULL,
    accepted_by_user_id UUID NULL REFERENCES medorbit.users(id),
    revoked_at TIMESTAMPTZ NULL,
    revoked_by_user_id UUID NULL REFERENCES medorbit.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT admin_invitations_status_check CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
    CONSTRAINT admin_invitations_acceptance_check CHECK (
        (status = 'accepted' AND accepted_at IS NOT NULL AND accepted_by_user_id IS NOT NULL)
        OR (status <> 'accepted' AND accepted_at IS NULL AND accepted_by_user_id IS NULL)
    ),
    CONSTRAINT admin_invitations_revocation_check CHECK (
        (status = 'revoked' AND revoked_at IS NOT NULL AND revoked_by_user_id IS NOT NULL)
        OR (status <> 'revoked' AND revoked_at IS NULL AND revoked_by_user_id IS NULL)
    )
);

CREATE UNIQUE INDEX admin_invitations_one_pending_email_idx
    ON medorbit.admin_invitations (email)
    WHERE status = 'pending';

CREATE INDEX admin_invitations_status_created_idx
    ON medorbit.admin_invitations (status, created_at DESC);
