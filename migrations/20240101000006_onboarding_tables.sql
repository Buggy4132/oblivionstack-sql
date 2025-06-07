-- Onboarding Tables
-- Tables for tracking onboarding process and AI questionnaire responses

-- Onboarding sessions
CREATE TABLE public.onboarding_sessions (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Session identification
    session_token text UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
    email text NOT NULL,
    
    -- Business information
    business_name text,
    industry industry_type,
    business_size text,
    
    -- Onboarding progress
    status onboarding_status DEFAULT 'not_started',
    current_step text,
    completed_steps text[] DEFAULT '{}',
    
    -- AI Analysis
    questionnaire_responses jsonb DEFAULT '{}',
    ai_analysis jsonb DEFAULT '{}',
    recommended_tier subscription_tier,
    recommended_modules text[] DEFAULT '{}',
    
    -- Conversion tracking
    source text,
    utm_campaign text,
    utm_source text,
    utm_medium text,
    referrer text,
    
    -- User association (after signup)
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    business_id uuid REFERENCES public.businesses(id) ON DELETE SET NULL,
    
    -- Timestamps
    started_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    completed_at timestamptz,
    abandoned_at timestamptz,
    expires_at timestamptz DEFAULT (CURRENT_TIMESTAMP + interval '30 days'),
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Questionnaire templates
CREATE TABLE public.questionnaire_templates (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Template identification
    key text UNIQUE NOT NULL,
    name text NOT NULL,
    description text,
    version integer DEFAULT 1,
    
    -- Template configuration
    industry industry_type,
    questions jsonb NOT NULL,
    scoring_logic jsonb DEFAULT '{}',
    
    -- Status
    is_active boolean DEFAULT true,
    is_default boolean DEFAULT false,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Questionnaire responses
CREATE TABLE public.questionnaire_responses (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id uuid NOT NULL REFERENCES public.onboarding_sessions(id) ON DELETE CASCADE,
    
    -- Question and response
    question_key text NOT NULL,
    question_text text NOT NULL,
    response_value text,
    response_metadata jsonb DEFAULT '{}',
    
    -- Scoring
    score numeric(5,2),
    weight numeric(3,2) DEFAULT 1.0,
    
    -- Timestamps
    answered_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(session_id, question_key)
);

-- Package recommendations
CREATE TABLE public.package_recommendations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id uuid NOT NULL REFERENCES public.onboarding_sessions(id) ON DELETE CASCADE,
    
    -- Recommendation details
    recommended_tier subscription_tier NOT NULL,
    confidence_score numeric(5,2),
    reasoning jsonb NOT NULL,
    
    -- Alternative options
    alternative_tiers subscription_tier[] DEFAULT '{}',
    custom_modules text[] DEFAULT '{}',
    
    -- Pricing
    monthly_price numeric(10,2),
    annual_price numeric(10,2),
    currency text DEFAULT 'AUD',
    
    -- User decision
    selected_tier subscription_tier,
    selected_at timestamptz,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Lead capture for marketing
CREATE TABLE public.marketing_leads (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Contact information
    email text NOT NULL UNIQUE,
    full_name text,
    phone text,
    company_name text,
    
    -- Lead details
    industry industry_type,
    business_size text,
    interests text[] DEFAULT '{}',
    
    -- Source tracking
    source text,
    utm_campaign text,
    utm_source text,
    utm_medium text,
    referrer text,
    landing_page text,
    
    -- Engagement
    newsletter_subscribed boolean DEFAULT false,
    demo_requested boolean DEFAULT false,
    consultation_requested boolean DEFAULT false,
    
    -- Conversion
    onboarding_session_id uuid REFERENCES public.onboarding_sessions(id),
    converted_to_user_id uuid REFERENCES auth.users(id),
    converted_at timestamptz,
    
    -- Lead scoring
    lead_score integer DEFAULT 0,
    lead_status text DEFAULT 'new' CHECK (lead_status IN ('new', 'contacted', 'qualified', 'converted', 'lost')),
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Consultation bookings
CREATE TABLE public.consultation_bookings (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Booking details
    session_id uuid REFERENCES public.onboarding_sessions(id) ON DELETE SET NULL,
    lead_id uuid REFERENCES public.marketing_leads(id) ON DELETE SET NULL,
    
    -- Contact information
    name text NOT NULL,
    email text NOT NULL,
    phone text,
    company_name text,
    
    -- Scheduling
    preferred_date date NOT NULL,
    preferred_time time NOT NULL,
    timezone text DEFAULT 'Australia/Perth',
    duration_minutes integer DEFAULT 30,
    
    -- Meeting details
    meeting_type text DEFAULT 'video' CHECK (meeting_type IN ('video', 'phone', 'in-person')),
    meeting_link text,
    calendar_event_id text,
    
    -- Status
    status text DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'completed', 'cancelled', 'no-show')),
    confirmed_at timestamptz,
    completed_at timestamptz,
    cancelled_at timestamptz,
    
    -- Notes
    customer_notes text,
    internal_notes text,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_onboarding_sessions_email ON public.onboarding_sessions(email);
CREATE INDEX idx_onboarding_sessions_status ON public.onboarding_sessions(status);
CREATE INDEX idx_onboarding_sessions_token ON public.onboarding_sessions(session_token);
CREATE INDEX idx_onboarding_sessions_created ON public.onboarding_sessions(created_at DESC);

CREATE INDEX idx_questionnaire_responses_session ON public.questionnaire_responses(session_id);
CREATE INDEX idx_package_recommendations_session ON public.package_recommendations(session_id);

CREATE INDEX idx_marketing_leads_email ON public.marketing_leads(email);
CREATE INDEX idx_marketing_leads_status ON public.marketing_leads(lead_status);
CREATE INDEX idx_marketing_leads_created ON public.marketing_leads(created_at DESC);

CREATE INDEX idx_consultation_bookings_email ON public.consultation_bookings(email);
CREATE INDEX idx_consultation_bookings_date ON public.consultation_bookings(preferred_date);
CREATE INDEX idx_consultation_bookings_status ON public.consultation_bookings(status);

-- Create triggers
CREATE TRIGGER update_onboarding_sessions_updated_at 
    BEFORE UPDATE ON public.onboarding_sessions 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_questionnaire_templates_updated_at 
    BEFORE UPDATE ON public.questionnaire_templates 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_marketing_leads_updated_at 
    BEFORE UPDATE ON public.marketing_leads 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_consultation_bookings_updated_at 
    BEFORE UPDATE ON public.consultation_bookings 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

-- Enable RLS (public read for some tables)
ALTER TABLE public.onboarding_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questionnaire_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questionnaire_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marketing_leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_bookings ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Questionnaire templates are public read
CREATE POLICY "Anyone can view active templates" ON public.questionnaire_templates
    FOR SELECT USING (is_active = true);

-- Onboarding sessions - users can manage their own
CREATE POLICY "Users can view own sessions" ON public.onboarding_sessions
    FOR SELECT USING (
        session_token = current_setting('request.session', true) OR
        email = current_setting('request.email', true) OR
        user_id = auth.user_id()
    );

CREATE POLICY "Public can create sessions" ON public.onboarding_sessions
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Users can update own sessions" ON public.onboarding_sessions
    FOR UPDATE USING (
        session_token = current_setting('request.session', true) OR
        email = current_setting('request.email', true) OR
        user_id = auth.user_id()
    );

-- Similar policies for other tables
CREATE POLICY "Session owners can view responses" ON public.questionnaire_responses
    FOR SELECT USING (
        session_id IN (
            SELECT id FROM public.onboarding_sessions
            WHERE session_token = current_setting('request.session', true)
            OR email = current_setting('request.email', true)
            OR user_id = auth.user_id()
        )
    );

CREATE POLICY "Session owners can add responses" ON public.questionnaire_responses
    FOR INSERT WITH CHECK (
        session_id IN (
            SELECT id FROM public.onboarding_sessions
            WHERE session_token = current_setting('request.session', true)
            OR email = current_setting('request.email', true)
        )
    );

-- Marketing leads - restricted access
CREATE POLICY "Staff can view leads" ON public.marketing_leads
    FOR SELECT USING (auth.has_role('staff'));

CREATE POLICY "Public can create leads" ON public.marketing_leads
    FOR INSERT WITH CHECK (true);

-- Consultation bookings - public create, restricted view
CREATE POLICY "Public can book consultations" ON public.consultation_bookings
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Staff can view bookings" ON public.consultation_bookings
    FOR SELECT USING (auth.has_role('staff'));

CREATE POLICY "Users can view own bookings" ON public.consultation_bookings
    FOR SELECT USING (email = current_setting('request.email', true));

-- Helper functions for onboarding

-- Start onboarding session
CREATE OR REPLACE FUNCTION public.start_onboarding_session(
    p_email text,
    p_business_name text DEFAULT NULL,
    p_source text DEFAULT NULL,
    p_utm_params jsonb DEFAULT '{}'
)
RETURNS jsonb AS $$
DECLARE
    v_session_id uuid;
    v_session_token text;
BEGIN
    -- Create or update lead
    INSERT INTO public.marketing_leads (
        email,
        company_name,
        source,
        utm_campaign,
        utm_source,
        utm_medium
    ) VALUES (
        p_email,
        p_business_name,
        p_source,
        p_utm_params->>'utm_campaign',
        p_utm_params->>'utm_source',
        p_utm_params->>'utm_medium'
    ) ON CONFLICT (email) DO UPDATE SET
        company_name = COALESCE(EXCLUDED.company_name, marketing_leads.company_name),
        updated_at = CURRENT_TIMESTAMP;
    
    -- Create onboarding session
    INSERT INTO public.onboarding_sessions (
        email,
        business_name,
        status,
        source,
        utm_campaign,
        utm_source,
        utm_medium
    ) VALUES (
        p_email,
        p_business_name,
        'in_progress',
        p_source,
        p_utm_params->>'utm_campaign',
        p_utm_params->>'utm_source',
        p_utm_params->>'utm_medium'
    ) RETURNING id, session_token INTO v_session_id, v_session_token;
    
    RETURN jsonb_build_object(
        'success', true,
        'session_id', v_session_id,
        'session_token', v_session_token
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE public.onboarding_sessions IS 'Tracks user progress through onboarding flow';
COMMENT ON TABLE public.questionnaire_templates IS 'AI questionnaire templates by industry';
COMMENT ON TABLE public.questionnaire_responses IS 'Individual question responses during onboarding';
COMMENT ON TABLE public.package_recommendations IS 'AI-generated package recommendations';
COMMENT ON TABLE public.marketing_leads IS 'Marketing lead capture and tracking';
COMMENT ON TABLE public.consultation_bookings IS 'Expert consultation scheduling';