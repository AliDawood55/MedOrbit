DROP TRIGGER IF EXISTS trg_users_revoke_sessions ON medorbit.users;

CREATE TRIGGER trg_users_revoke_sessions
AFTER UPDATE
ON medorbit.users
FOR EACH ROW
WHEN (OLD.authorization_version IS DISTINCT FROM NEW.authorization_version)
EXECUTE FUNCTION medorbit.revoke_sessions_on_authorization_change();
