CREATE OR REPLACE FUNCTION medorbit.enforce_authorization_version()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role
       OR NEW.is_active IS DISTINCT FROM OLD.is_active
       OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
       OR NEW.password_hash IS DISTINCT FROM OLD.password_hash THEN
        NEW.authorization_version := OLD.authorization_version + 1;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_authorization_version ON medorbit.users;

CREATE TRIGGER trg_users_authorization_version
BEFORE UPDATE OF role, is_active, deleted_at, password_hash
ON medorbit.users
FOR EACH ROW
EXECUTE FUNCTION medorbit.enforce_authorization_version();

CREATE OR REPLACE FUNCTION medorbit.revoke_sessions_on_authorization_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE medorbit.user_sessions
    SET revoked_at = NOW()
    WHERE user_id = NEW.id
      AND revoked_at IS NULL;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_revoke_sessions ON medorbit.users;

CREATE TRIGGER trg_users_revoke_sessions
AFTER UPDATE OF authorization_version
ON medorbit.users
FOR EACH ROW
WHEN (OLD.authorization_version IS DISTINCT FROM NEW.authorization_version)
EXECUTE FUNCTION medorbit.revoke_sessions_on_authorization_change();
