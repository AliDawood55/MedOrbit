CREATE TABLE IF NOT EXISTS public.appointment_status_history (

    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    appointment_id UUID NOT NULL,

    old_status VARCHAR(50),

    new_status VARCHAR(50) NOT NULL,

    changed_by UUID,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,


    CONSTRAINT fk_status_history_appointment

    FOREIGN KEY (appointment_id)

    REFERENCES public.appointments(id)

    ON DELETE CASCADE

);