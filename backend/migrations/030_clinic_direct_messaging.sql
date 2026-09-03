-- Clinics are organisations represented by their verified owner account.
-- They may exchange ordinary text messages with patients and doctors; this
-- never creates a clinical relationship or grants medical-record access.
ALTER TABLE medorbit.conversation_members
  DROP CONSTRAINT IF EXISTS conversation_members_role_check;
ALTER TABLE medorbit.conversation_members
  ADD CONSTRAINT conversation_members_role_check
  CHECK (member_role IN ('patient','doctor','clinic'));

ALTER TABLE medorbit.direct_conversations
  DROP CONSTRAINT IF EXISTS direct_conversations_type_check;
ALTER TABLE medorbit.direct_conversations
  ADD CONSTRAINT direct_conversations_type_check
  CHECK (conversation_type IN ('patient_doctor','doctor_doctor','clinic_doctor','patient_clinic'));

CREATE INDEX IF NOT EXISTS clinics_owner_approved_idx
  ON medorbit.clinics(owner_user_id)
  WHERE is_active=true AND approval_status='approved';
