BEGIN;

CREATE TABLE IF NOT EXISTS public.password_reset_tokens
(
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    user_id UUID NOT NULL,

    token VARCHAR(255) NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,

    used_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_password_reset_user
        FOREIGN KEY (user_id)
        REFERENCES public.users(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_password_reset_user
ON public.password_reset_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_password_reset_token
ON public.password_reset_tokens(token);

CREATE INDEX IF NOT EXISTS idx_password_reset_expires
ON public.password_reset_tokens(expires_at);

COMMENT ON TABLE public.password_reset_tokens IS
'Stores one-time password reset tokens';

COMMIT;