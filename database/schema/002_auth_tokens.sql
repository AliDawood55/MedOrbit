BEGIN;

-- ==========================================================
-- PASSWORD RESET TOKENS
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.password_reset_tokens
(
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    user_id UUID NOT NULL,

    token VARCHAR(255) NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,

    used_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT password_reset_tokens_user_fk
        FOREIGN KEY (user_id)
        REFERENCES public.users(id)
        ON DELETE CASCADE
);

COMMENT ON TABLE public.password_reset_tokens
IS 'Stores one-time password reset tokens.';


CREATE INDEX IF NOT EXISTS idx_password_reset_user
ON public.password_reset_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_password_reset_token
ON public.password_reset_tokens(token);

CREATE INDEX IF NOT EXISTS idx_password_reset_expiry
ON public.password_reset_tokens(expires_at);



-- ==========================================================
-- EMAIL VERIFICATION TOKENS
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.email_verification_tokens
(
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    user_id UUID NOT NULL,

    token VARCHAR(255) NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,

    verified_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT email_verification_tokens_user_fk
        FOREIGN KEY (user_id)
        REFERENCES public.users(id)
        ON DELETE CASCADE
);

COMMENT ON TABLE public.email_verification_tokens
IS 'Stores email verification tokens.';


CREATE INDEX IF NOT EXISTS idx_email_verification_user
ON public.email_verification_tokens(user_id);

CREATE INDEX IF NOT EXISTS idx_email_verification_token
ON public.email_verification_tokens(token);

CREATE INDEX IF NOT EXISTS idx_email_verification_expiry
ON public.email_verification_tokens(expires_at);

COMMIT;