-- Extend the existing availability source of truth for doctor-managed weekly
-- rules and date-specific exceptions. Existing rows remain ordinary available
-- windows; appointments and reviewed doctor credentials are not rewritten.

ALTER TABLE medorbit.doctor_availability
  ADD COLUMN availability_type VARCHAR(16) NOT NULL DEFAULT 'available',
  ADD COLUMN updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

ALTER TABLE medorbit.doctor_availability
  ADD CONSTRAINT doctor_availability_type_check
    CHECK (availability_type IN ('available', 'blocked', 'day_off')),
  ADD CONSTRAINT doctor_availability_scope_check
    CHECK (
      (availability_type='available' AND
        ((day_of_week IS NOT NULL AND specific_date IS NULL)
         OR (day_of_week IS NULL AND specific_date IS NOT NULL)))
      OR
      (availability_type IN ('blocked','day_off')
        AND day_of_week IS NULL AND specific_date IS NOT NULL)
    ),
  ADD CONSTRAINT doctor_availability_time_order_check
    CHECK (end_time > start_time),
  ADD CONSTRAINT doctor_availability_duration_check
    CHECK (slot_duration IN (15,20,30,45,60)),
  ADD CONSTRAINT doctor_availability_window_length_check
    CHECK (
      availability_type='day_off'
      OR end_time - start_time <= INTERVAL '16 hours'
    ),
  ADD CONSTRAINT doctor_availability_day_off_shape_check
    CHECK (
      availability_type<>'day_off'
      OR (start_time=TIME '00:00:00' AND end_time=TIME '23:59:59')
    );

CREATE UNIQUE INDEX doctor_availability_active_rule_unique
  ON medorbit.doctor_availability
    (doctor_id,clinic_id,day_of_week,specific_date,start_time,end_time,
     slot_duration,is_telemedicine,availability_type) NULLS NOT DISTINCT
  WHERE is_active=true;

CREATE INDEX doctor_availability_effective_date
  ON medorbit.doctor_availability
    (doctor_id,specific_date,availability_type,start_time,end_time)
  WHERE is_active=true AND specific_date IS NOT NULL;

ALTER TABLE medorbit.appointments
  ADD CONSTRAINT appointments_time_order_check CHECK (end_time > start_time),
  ADD CONSTRAINT appointments_duration_bounds_check
    CHECK (duration_minutes BETWEEN 1 AND 480);

-- This is the final database guard for two concurrent requests attempting the
-- same doctor/date/start. The booking service additionally validates an exact
-- generated slot and serializes all bookings for a doctor/day.
CREATE UNIQUE INDEX appointments_one_active_doctor_start
  ON medorbit.appointments(doctor_id,scheduled_date,start_time)
  WHERE status NOT IN ('cancelled','no_show');
