CREATE TABLE public.notification_templates (

    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    name VARCHAR(100) NOT NULL UNIQUE,

    type VARCHAR(50) NOT NULL,

    subject_en VARCHAR(255) NOT NULL,
    subject_ar VARCHAR(255),

    body_html TEXT NOT NULL,
    body_text TEXT,

    variables JSONB DEFAULT '{}'::jsonb,

    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);


CREATE INDEX idx_notification_templates_type
ON public.notification_templates(type);


CREATE INDEX idx_notification_templates_active
ON public.notification_templates(is_active);