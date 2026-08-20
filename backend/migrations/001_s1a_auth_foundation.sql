ALTER TABLE medorbit.users
    ADD COLUMN IF NOT EXISTS authorization_version INTEGER NOT NULL DEFAULT 1;

ALTER TABLE medorbit.users
    DROP CONSTRAINT IF EXISTS users_authorization_version_check;

ALTER TABLE medorbit.users
    ADD CONSTRAINT users_authorization_version_check
    CHECK (authorization_version > 0);

ALTER TABLE medorbit.users
    DROP CONSTRAINT IF EXISTS users_role_check;

ALTER TABLE medorbit.users
    ADD CONSTRAINT users_role_check
    CHECK (role IN ('patient', 'doctor', 'admin', 'super_admin'));

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'medorbit'
          AND table_name = 'user_sessions'
          AND column_name = 'refresh_token'
    ) THEN
        EXECUTE 'ALTER TABLE medorbit.user_sessions ADD COLUMN IF NOT EXISTS refresh_token_hash VARCHAR(64)';
        EXECUTE $sql$
            UPDATE medorbit.user_sessions
            SET refresh_token_hash = encode(digest(refresh_token, 'sha256'), 'hex'),
                revoked_at = COALESCE(revoked_at, NOW())
        $sql$;
        EXECUTE 'DROP INDEX IF EXISTS medorbit.idx_sessions_token';
        EXECUTE 'ALTER TABLE medorbit.user_sessions ALTER COLUMN refresh_token_hash SET NOT NULL';
        EXECUTE 'ALTER TABLE medorbit.user_sessions DROP COLUMN refresh_token';
    END IF;
END
$$;

ALTER TABLE medorbit.user_sessions
    DROP CONSTRAINT IF EXISTS user_sessions_refresh_token_hash_check;

ALTER TABLE medorbit.user_sessions
    ADD CONSTRAINT user_sessions_refresh_token_hash_check
    CHECK (refresh_token_hash ~ '^[0-9a-f]{64}$');

CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_refresh_token_hash
    ON medorbit.user_sessions (refresh_token_hash);
