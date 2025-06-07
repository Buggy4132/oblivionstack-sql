-- Business Tables
-- Core business entities and relationships

-- Businesses table (main tenant table)
CREATE TABLE public.businesses (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    slug text UNIQUE NOT NULL,
    industry industry_type NOT NULL,
    status business_status DEFAULT 'trial',
    subscription_tier subscription_tier DEFAULT 'basic',
    subscription_status subscription_status DEFAULT 'trialing',
    trial_ends_at timestamptz,
    subscription_ends_at timestamptz,
    
    -- Business details
    email text NOT NULL,
    phone text,
    website text,
    timezone text DEFAULT 'Australia/Perth',
    currency text DEFAULT 'AUD',
    locale text DEFAULT 'en-AU',
    
    -- Address
    address_line1 text,
    address_line2 text,
    city text,
    state text,
    postal_code text,
    country text DEFAULT 'AU',
    
    -- Settings and metadata
    settings jsonb DEFAULT '{}',
    features jsonb DEFAULT '{}',
    metadata jsonb DEFAULT '{}',
    
    -- Timestamps
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    deleted_at timestamptz,
    
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT valid_slug CHECK (slug ~* '^[a-z0-9-]+$')
);

-- Business users (many-to-many relationship)
CREATE TABLE public.business_users (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role user_role NOT NULL DEFAULT 'staff',
    status text DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'pending')),
    
    -- Permissions and access
    permissions jsonb DEFAULT '{}',
    departments text[] DEFAULT '{}',
    
    -- Timestamps
    invited_at timestamptz,
    joined_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    last_active_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(business_id, user_id)
);

-- Business locations (for multi-location businesses)
CREATE TABLE public.business_locations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    name text NOT NULL,
    is_primary boolean DEFAULT false,
    
    -- Location details
    email text,
    phone text,
    
    -- Address
    address_line1 text,
    address_line2 text,
    city text,
    state text,
    postal_code text,
    country text DEFAULT 'AU',
    
    -- Operating hours
    operating_hours jsonb DEFAULT '{}',
    timezone text DEFAULT 'Australia/Perth',
    
    -- Settings
    settings jsonb DEFAULT '{}',
    metadata jsonb DEFAULT '{}',
    
    -- Status
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Business modules (track which modules are enabled)
CREATE TABLE public.business_modules (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    module_key text NOT NULL,
    module_category module_category NOT NULL,
    is_enabled boolean DEFAULT true,
    settings jsonb DEFAULT '{}',
    enabled_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(business_id, module_key)
);

-- Business integrations
CREATE TABLE public.business_integrations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    integration_type text NOT NULL,
    integration_key text NOT NULL,
    
    -- Configuration
    config jsonb DEFAULT '{}',
    credentials jsonb DEFAULT '{}', -- Encrypted
    
    -- Status
    is_active boolean DEFAULT true,
    last_sync_at timestamptz,
    sync_status text,
    error_message text,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(business_id, integration_key)
);

-- Business notifications preferences
CREATE TABLE public.business_notifications (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id uuid NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    
    -- Email notifications
    email_booking_confirmation boolean DEFAULT true,
    email_booking_reminder boolean DEFAULT true,
    email_staff_schedule boolean DEFAULT true,
    email_inventory_alerts boolean DEFAULT true,
    email_financial_reports boolean DEFAULT true,
    
    -- SMS notifications
    sms_booking_confirmation boolean DEFAULT false,
    sms_booking_reminder boolean DEFAULT false,
    sms_marketing boolean DEFAULT false,
    
    -- In-app notifications
    app_notifications jsonb DEFAULT '{}',
    
    -- Notification settings
    reminder_hours_before integer DEFAULT 24,
    quiet_hours_start time,
    quiet_hours_end time,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(business_id)
);

-- Create indexes
CREATE INDEX idx_businesses_slug ON public.businesses(slug);
CREATE INDEX idx_businesses_status ON public.businesses(status);
CREATE INDEX idx_businesses_industry ON public.businesses(industry);
CREATE INDEX idx_businesses_subscription ON public.businesses(subscription_tier, subscription_status);
CREATE INDEX idx_businesses_created ON public.businesses(created_at DESC);

CREATE INDEX idx_business_users_business ON public.business_users(business_id);
CREATE INDEX idx_business_users_user ON public.business_users(user_id);
CREATE INDEX idx_business_users_role ON public.business_users(role);
CREATE INDEX idx_business_users_status ON public.business_users(status);

CREATE INDEX idx_business_locations_business ON public.business_locations(business_id);
CREATE INDEX idx_business_locations_primary ON public.business_locations(business_id, is_primary);

CREATE INDEX idx_business_modules_business ON public.business_modules(business_id);
CREATE INDEX idx_business_modules_enabled ON public.business_modules(business_id, is_enabled);
CREATE INDEX idx_business_modules_category ON public.business_modules(module_category);

CREATE INDEX idx_business_integrations_business ON public.business_integrations(business_id);
CREATE INDEX idx_business_integrations_type ON public.business_integrations(integration_type);

-- Create triggers
CREATE TRIGGER update_businesses_updated_at 
    BEFORE UPDATE ON public.businesses 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_business_users_updated_at 
    BEFORE UPDATE ON public.business_users 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_business_locations_updated_at 
    BEFORE UPDATE ON public.business_locations 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_business_modules_updated_at 
    BEFORE UPDATE ON public.business_modules 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_business_integrations_updated_at 
    BEFORE UPDATE ON public.business_integrations 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_business_notifications_updated_at 
    BEFORE UPDATE ON public.business_notifications 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

-- Enable RLS
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies for businesses
CREATE POLICY "Users can view businesses they belong to" ON public.businesses
    FOR SELECT USING (
        id IN (SELECT business_id FROM public.business_users WHERE user_id = auth.user_id() AND status = 'active')
    );

CREATE POLICY "Only owners can update business" ON public.businesses
    FOR UPDATE USING (
        id IN (SELECT business_id FROM public.business_users WHERE user_id = auth.user_id() AND role = 'owner' AND status = 'active')
    );

-- RLS Policies for business_users
CREATE POLICY "Users can view business users in their business" ON public.business_users
    FOR SELECT USING (
        business_id IN (SELECT business_id FROM public.business_users WHERE user_id = auth.user_id() AND status = 'active')
    );

CREATE POLICY "Admins can manage business users" ON public.business_users
    FOR ALL USING (
        business_id IN (
            SELECT business_id FROM public.business_users 
            WHERE user_id = auth.user_id() 
            AND role IN ('owner', 'admin') 
            AND status = 'active'
        )
    );

-- Apply standard RLS to other tables
SELECT public.create_rls_policies('public', 'business_locations');
SELECT public.create_rls_policies('public', 'business_modules');
SELECT public.create_rls_policies('public', 'business_integrations');
SELECT public.create_rls_policies('public', 'business_notifications');

-- Add comments
COMMENT ON TABLE public.businesses IS 'Main business/tenant table';
COMMENT ON TABLE public.business_users IS 'Many-to-many relationship between businesses and users';
COMMENT ON TABLE public.business_locations IS 'Multiple locations for a business';
COMMENT ON TABLE public.business_modules IS 'Enabled modules and features per business';
COMMENT ON TABLE public.business_integrations IS 'Third-party integrations configuration';
COMMENT ON TABLE public.business_notifications IS 'Notification preferences per business';