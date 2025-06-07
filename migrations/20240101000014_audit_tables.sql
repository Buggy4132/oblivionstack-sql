-- Audit Tables
-- Comprehensive audit logging for compliance and debugging

-- Main audit log table
CREATE TABLE public.audit_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Context
    table_name text NOT NULL,
    record_id uuid,
    action text NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')),
    
    -- User and business context
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    business_id uuid REFERENCES public.businesses(id) ON DELETE SET NULL,
    
    -- Data changes
    old_data jsonb,
    new_data jsonb,
    changed_fields text[],
    
    -- Request context
    ip_address inet,
    user_agent text,
    request_id text,
    
    -- Timestamp
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- API request logs
CREATE TABLE public.api_request_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Request details
    method text NOT NULL,
    path text NOT NULL,
    query_params jsonb,
    headers jsonb,
    body jsonb,
    
    -- Response details
    status_code integer,
    response_body jsonb,
    response_time_ms integer,
    
    -- User context
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    business_id uuid REFERENCES public.businesses(id) ON DELETE SET NULL,
    api_key_id uuid,
    
    -- Request metadata
    ip_address inet,
    user_agent text,
    request_id text,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Error logs
CREATE TABLE public.error_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Error details
    error_type text NOT NULL,
    error_message text NOT NULL,
    error_code text,
    stack_trace text,
    
    -- Context
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    business_id uuid REFERENCES public.businesses(id) ON DELETE SET NULL,
    
    -- Request context
    request_method text,
    request_path text,
    request_id text,
    
    -- Additional data
    metadata jsonb DEFAULT '{}',
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Business subscription changes
CREATE TABLE public.subscription_audit_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    
    -- Change details
    action text NOT NULL,
    previous_tier subscription_tier,
    new_tier subscription_tier,
    previous_status subscription_status,
    new_status subscription_status,
    
    -- Billing details
    amount numeric(10, 2),
    currency text DEFAULT 'AUD',
    payment_method text,
    
    -- User who made the change
    changed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    change_reason text,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Data export audit
CREATE TABLE public.data_export_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Export details
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    export_type text NOT NULL,
    entity_types text[],
    
    -- Export parameters
    date_from timestamptz,
    date_to timestamptz,
    filters jsonb,
    
    -- Results
    record_count integer,
    file_size_bytes bigint,
    format text,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Security events
CREATE TABLE public.security_event_logs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Event details
    event_type text NOT NULL,
    severity text NOT NULL CHECK (severity IN ('info', 'warning', 'error', 'critical')),
    description text NOT NULL,
    
    -- User context
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    business_id uuid REFERENCES public.businesses(id) ON DELETE SET NULL,
    
    -- Security details
    ip_address inet,
    user_agent text,
    metadata jsonb DEFAULT '{}',
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_audit_logs_table ON public.audit_logs(table_name);
CREATE INDEX idx_audit_logs_record ON public.audit_logs(record_id);
CREATE INDEX idx_audit_logs_user ON public.audit_logs(user_id);
CREATE INDEX idx_audit_logs_business ON public.audit_logs(business_id);
CREATE INDEX idx_audit_logs_created ON public.audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_action ON public.audit_logs(action);

CREATE INDEX idx_api_request_logs_path ON public.api_request_logs(path);
CREATE INDEX idx_api_request_logs_user ON public.api_request_logs(user_id);
CREATE INDEX idx_api_request_logs_business ON public.api_request_logs(business_id);
CREATE INDEX idx_api_request_logs_created ON public.api_request_logs(created_at DESC);
CREATE INDEX idx_api_request_logs_status ON public.api_request_logs(status_code);

CREATE INDEX idx_error_logs_type ON public.error_logs(error_type);
CREATE INDEX idx_error_logs_user ON public.error_logs(user_id);
CREATE INDEX idx_error_logs_business ON public.error_logs(business_id);
CREATE INDEX idx_error_logs_created ON public.error_logs(created_at DESC);

CREATE INDEX idx_subscription_audit_business ON public.subscription_audit_logs(business_id);
CREATE INDEX idx_subscription_audit_created ON public.subscription_audit_logs(created_at DESC);

CREATE INDEX idx_data_export_logs_business ON public.data_export_logs(business_id);
CREATE INDEX idx_data_export_logs_user ON public.data_export_logs(user_id);
CREATE INDEX idx_data_export_logs_created ON public.data_export_logs(created_at DESC);

CREATE INDEX idx_security_events_type ON public.security_event_logs(event_type);
CREATE INDEX idx_security_events_severity ON public.security_event_logs(severity);
CREATE INDEX idx_security_events_user ON public.security_event_logs(user_id);
CREATE INDEX idx_security_events_created ON public.security_event_logs(created_at DESC);

-- Enable RLS (audit tables typically have restricted access)
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_request_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.error_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.data_export_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_event_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies (restrictive - only admins/owners can view)
CREATE POLICY "Only admins can view audit logs" ON public.audit_logs
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.business_users
            WHERE user_id = auth.user_id()
            AND business_id = audit_logs.business_id
            AND role IN ('owner', 'admin')
            AND status = 'active'
        )
    );

-- Similar policies for other audit tables
CREATE POLICY "Only admins can view API logs" ON public.api_request_logs
    FOR SELECT USING (
        auth.has_role('admin')
    );

CREATE POLICY "Only admins can view error logs" ON public.error_logs
    FOR SELECT USING (
        auth.has_role('admin')
    );

CREATE POLICY "Business owners can view subscription history" ON public.subscription_audit_logs
    FOR SELECT USING (
        auth.belongs_to_business(business_id) AND auth.has_role('owner')
    );

CREATE POLICY "Users can view own data exports" ON public.data_export_logs
    FOR SELECT USING (
        user_id = auth.user_id() OR auth.has_role('admin')
    );

CREATE POLICY "Admins can view security events" ON public.security_event_logs
    FOR SELECT USING (
        auth.has_role('admin')
    );

-- Audit helper functions
CREATE OR REPLACE FUNCTION public.log_api_request(
    p_method text,
    p_path text,
    p_status_code integer,
    p_response_time_ms integer,
    p_metadata jsonb DEFAULT '{}'
)
RETURNS void AS $$
BEGIN
    INSERT INTO public.api_request_logs (
        method,
        path,
        status_code,
        response_time_ms,
        user_id,
        business_id,
        ip_address,
        user_agent,
        headers
    ) VALUES (
        p_method,
        p_path,
        p_status_code,
        p_response_time_ms,
        auth.user_id(),
        auth.business_id(),
        (current_setting('request.headers', true)::json->>'x-real-ip')::inet,
        current_setting('request.headers', true)::json->>'user-agent',
        current_setting('request.headers', true)::jsonb
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE public.audit_logs IS 'General audit trail for all data changes';
COMMENT ON TABLE public.api_request_logs IS 'API request and response logging';
COMMENT ON TABLE public.error_logs IS 'Application error tracking';
COMMENT ON TABLE public.subscription_audit_logs IS 'Business subscription change history';
COMMENT ON TABLE public.data_export_logs IS 'Data export audit trail for compliance';
COMMENT ON TABLE public.security_event_logs IS 'Security-related event tracking';