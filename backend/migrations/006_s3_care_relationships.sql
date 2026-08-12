CREATE TABLE medorbit.doctor_patient_relationships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  doctor_id UUID NOT NULL REFERENCES medorbit.doctors(id),
  patient_id UUID NOT NULL REFERENCES medorbit.patients(id),
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  source VARCHAR(24) NOT NULL,
  source_reference_id UUID,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  created_by_user_id UUID REFERENCES medorbit.users(id),
  ended_by_user_id UUID REFERENCES medorbit.users(id),
  end_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT doctor_patient_relationships_status_check
    CHECK (status IN ('pending','active','ended','revoked')),
  CONSTRAINT doctor_patient_relationships_source_check
    CHECK (source IN ('appointment','manual_assign','admin_assign','telemedicine','referral')),
  CONSTRAINT doctor_patient_relationships_end_state_check
    CHECK (
      (status IN ('pending','active') AND ended_at IS NULL)
      OR (status IN ('ended','revoked') AND ended_at IS NOT NULL)
    )
);

CREATE UNIQUE INDEX doctor_patient_relationships_one_active_pair
  ON medorbit.doctor_patient_relationships (doctor_id, patient_id)
  WHERE status = 'active';

CREATE INDEX doctor_patient_relationships_patient_active
  ON medorbit.doctor_patient_relationships (patient_id, started_at DESC)
  WHERE status = 'active';

CREATE INDEX doctor_patient_relationships_doctor_history
  ON medorbit.doctor_patient_relationships (doctor_id, patient_id, created_at DESC);

-- Transitional backfill: cancelled/no-show-only history is deliberately excluded.
-- The earliest qualifying appointment is retained as the evidence reference and
-- its booking timestamp is the relationship start evidence.
WITH ranked_evidence AS (
  SELECT a.doctor_id,
         a.patient_id,
         a.id AS appointment_id,
         COALESCE(a.created_at, NOW()) AS evidence_at,
         ROW_NUMBER() OVER (
           PARTITION BY a.doctor_id, a.patient_id
           ORDER BY COALESCE(a.created_at, NOW()), a.id
         ) AS evidence_rank
  FROM medorbit.appointments a
  WHERE a.status IN ('scheduled','confirmed','in_progress','completed')
)
INSERT INTO medorbit.doctor_patient_relationships
  (doctor_id, patient_id, status, source, source_reference_id, started_at)
SELECT e.doctor_id, e.patient_id, 'active', 'appointment', e.appointment_id, e.evidence_at
FROM ranked_evidence e
WHERE e.evidence_rank = 1
  AND NOT EXISTS (
    SELECT 1
    FROM medorbit.doctor_patient_relationships r
    WHERE r.doctor_id=e.doctor_id
      AND r.patient_id=e.patient_id
      AND r.status='active'
  );
