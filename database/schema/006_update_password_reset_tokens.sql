BEGIN;


ALTER TABLE public.password_reset_tokens
RENAME COLUMN token TO token_hash;


COMMIT;