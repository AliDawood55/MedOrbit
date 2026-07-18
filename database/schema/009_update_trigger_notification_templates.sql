CREATE OR REPLACE FUNCTION update_notification_templates_updated_at()
RETURNS TRIGGER AS $$

BEGIN

NEW.updated_at = CURRENT_TIMESTAMP;

RETURN NEW;

END;

$$ LANGUAGE plpgsql;



CREATE TRIGGER notification_templates_updated_at

BEFORE UPDATE ON public.notification_templates

FOR EACH ROW

EXECUTE FUNCTION update_notification_templates_updated_at();