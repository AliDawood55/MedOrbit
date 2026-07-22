BEGIN;


-- Add revocation support
ALTER TABLE public.user_sessions
ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ;


-- Track last refresh usage
ALTER TABLE public.user_sessions
ADD COLUMN IF NOT EXISTS last_used_at TIMESTAMPTZ;


-- Identify device
ALTER TABLE public.user_sessions
ADD COLUMN IF NOT EXISTS device_name VARCHAR(100);


-- Identify platform
ALTER TABLE public.user_sessions
ADD COLUMN IF NOT EXISTS platform VARCHAR(20);


-- Automatically update timestamp
ALTER TABLE public.user_sessions
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ
DEFAULT CURRENT_TIMESTAMP;



-- Index for faster refresh token lookup
CREATE INDEX IF NOT EXISTS idx_user_sessions_refresh_token
ON public.user_sessions(refresh_token);



-- Index active sessions lookup
CREATE INDEX IF NOT EXISTS idx_user_sessions_active
ON public.user_sessions(user_id, revoked_at);



COMMIT;