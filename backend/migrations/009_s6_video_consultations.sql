CREATE TABLE medorbit.video_consultations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  appointment_id UUID NOT NULL UNIQUE REFERENCES medorbit.appointments(id),
  doctor_id UUID NOT NULL REFERENCES medorbit.doctors(id),
  patient_id UUID NOT NULL REFERENCES medorbit.patients(id),
  status VARCHAR(16) NOT NULL DEFAULT 'created',
  scheduled_at TIMESTAMPTZ,
  patient_joined_at TIMESTAMPTZ,
  doctor_joined_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_by_user_id UUID NOT NULL REFERENCES medorbit.users(id),
  ended_by_user_id UUID REFERENCES medorbit.users(id),
  end_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT video_consultations_status_check
    CHECK (status IN ('created','waiting','active','ended','expired','cancelled')),
  CONSTRAINT video_consultations_end_state_check CHECK (
    (status='ended' AND ended_at IS NOT NULL AND ended_by_user_id IS NOT NULL)
    OR (status<>'ended')
  )
);

CREATE INDEX video_consultations_participants
  ON medorbit.video_consultations(doctor_id,patient_id,created_at DESC);

CREATE INDEX video_consultations_joinable
  ON medorbit.video_consultations(expires_at,status)
  WHERE status IN ('created','waiting','active');
