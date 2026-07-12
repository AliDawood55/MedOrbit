BEGIN;

CREATE TABLE IF NOT EXISTS public.email_verification_tokens
(
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    user_id UUID NOT NULL,

    token VARCHAR(255) NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,

    verified_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_email_verification_user
        FOREIGN KEY (user_id)
        REFERENCES public.users(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_email_verification_user
ON public.email_verification_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_email_verification_token
ON public.email_verification_tokens(token);

CREATE INDEX IF NOT EXISTS idx_email_verification_expire
ON public.email_verification_tokens(expires_at);

COMMENT ON TABLE public.email_verification_tokens IS
'Stores email verification tokens for newly registered users';

COMMIT;