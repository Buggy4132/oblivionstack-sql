-- User Tables
-- Extended user data and preferences

-- User preferences
CREATE TABLE public.user_preferences (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Display preferences
    theme text DEFAULT 'light' CHECK (theme IN ('light', 'dark', 'auto')),
    language text DEFAULT 'en',
    date_format text DEFAULT 'DD/MM/YYYY',
    time_format text DEFAULT '12h' CHECK (time_format IN ('12h', '24h')),
    
    -- Notification preferences
    email_notifications boolean DEFAULT true,
    sms_notifications boolean DEFAULT false,
    push_notifications boolean DEFAULT true,
    notification_digest text DEFAULT 'instant' CHECK (notification_digest IN ('instant', 'hourly', 'daily', 'weekly')),
    
    -- Privacy settings
    profile_visibility text DEFAULT 'team' CHECK (profile_visibility IN ('public', 'team', 'private')),
    show_online_status boolean DEFAULT true,
    
    -- UI preferences
    sidebar_collapsed boolean DEFAULT false,
    dashboard_layout jsonb DEFAULT '{}',
    default_business_id uuid,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- User activity tracking
CREATE TABLE public.user_activities (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id uuid REFERENCES public.businesses(id) ON DELETE CASCADE,
    
    activity_type text NOT NULL,
    activity_description text,
    entity_type text,
    entity_id uuid,
    
    -- Activity metadata
    metadata jsonb DEFAULT '{}',
    ip_address inet,
    user_agent text,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- User notifications
CREATE TABLE public.user_notifications (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id uuid REFERENCES public.businesses(id) ON DELETE CASCADE,
    
    -- Notification details
    type text NOT NULL,
    title text NOT NULL,
    message text,
    action_url text,
    
    -- Status
    is_read boolean DEFAULT false,
    read_at timestamptz,
    
    -- Priority and metadata
    priority text DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    metadata jsonb DEFAULT '{}',
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz
);

-- User devices (for push notifications)
CREATE TABLE public.user_devices (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Device information
    device_token text NOT NULL UNIQUE,
    device_type text NOT NULL CHECK (device_type IN ('ios', 'android', 'web')),
    device_name text,
    
    -- Push notification settings
    push_enabled boolean DEFAULT true,
    last_used_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- User saved searches/filters
CREATE TABLE public.user_saved_filters (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id uuid REFERENCES public.businesses(id) ON DELETE CASCADE,
    
    name text NOT NULL,
    entity_type text NOT NULL,
    filter_data jsonb NOT NULL,
    is_default boolean DEFAULT false,
    
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(user_id, business_id, entity_type, name)
);

-- User dashboard widgets
CREATE TABLE public.user_dashboard_widgets (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id uuid REFERENCES public.businesses(id) ON DELETE CASCADE,
    
    widget_type text NOT NULL,
    position integer NOT NULL,
    size text DEFAULT 'medium' CHECK (size IN ('small', 'medium', 'large', 'full')),
    settings jsonb DEFAULT '{}',
    
    is_visible boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(user_id, business_id, position)
);

-- Create indexes
CREATE INDEX idx_user_preferences_user ON public.user_preferences(user_id);
CREATE INDEX idx_user_activities_user ON public.user_activities(user_id);
CREATE INDEX idx_user_activities_business ON public.user_activities(business_id);
CREATE INDEX idx_user_activities_created ON public.user_activities(created_at DESC);
CREATE INDEX idx_user_activities_type ON public.user_activities(activity_type);

CREATE INDEX idx_user_notifications_user ON public.user_notifications(user_id);
CREATE INDEX idx_user_notifications_business ON public.user_notifications(business_id);
CREATE INDEX idx_user_notifications_unread ON public.user_notifications(user_id, is_read);
CREATE INDEX idx_user_notifications_created ON public.user_notifications(created_at DESC);

CREATE INDEX idx_user_devices_user ON public.user_devices(user_id);
CREATE INDEX idx_user_devices_token ON public.user_devices(device_token);

CREATE INDEX idx_user_saved_filters_user ON public.user_saved_filters(user_id);
CREATE INDEX idx_user_saved_filters_business ON public.user_saved_filters(business_id);

CREATE INDEX idx_user_dashboard_widgets_user ON public.user_dashboard_widgets(user_id);
CREATE INDEX idx_user_dashboard_widgets_business ON public.user_dashboard_widgets(business_id);

-- Create triggers
CREATE TRIGGER update_user_preferences_updated_at 
    BEFORE UPDATE ON public.user_preferences 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_devices_updated_at 
    BEFORE UPDATE ON public.user_devices 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_saved_filters_updated_at 
    BEFORE UPDATE ON public.user_saved_filters 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_user_dashboard_widgets_updated_at 
    BEFORE UPDATE ON public.user_dashboard_widgets 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

-- Enable RLS
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_saved_filters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_dashboard_widgets ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- User preferences - users can only manage their own
SELECT public.create_user_rls_policies('public', 'user_preferences');

-- User activities - users can view their own activities
CREATE POLICY "Users can view own activities" ON public.user_activities
    FOR SELECT USING (user_id = auth.user_id());

CREATE POLICY "System can insert activities" ON public.user_activities
    FOR INSERT WITH CHECK (user_id = auth.user_id());

-- User notifications - users can manage their own
CREATE POLICY "Users can view own notifications" ON public.user_notifications
    FOR SELECT USING (user_id = auth.user_id());

CREATE POLICY "Users can update own notifications" ON public.user_notifications
    FOR UPDATE USING (user_id = auth.user_id());

CREATE POLICY "Users can delete own notifications" ON public.user_notifications
    FOR DELETE USING (user_id = auth.user_id());

-- User devices - users can manage their own
SELECT public.create_user_rls_policies('public', 'user_devices');

-- User saved filters - scoped to user and business
CREATE POLICY "Users can view own filters" ON public.user_saved_filters
    FOR SELECT USING (
        user_id = auth.user_id() 
        AND (business_id IS NULL OR auth.belongs_to_business(business_id))
    );

CREATE POLICY "Users can manage own filters" ON public.user_saved_filters
    FOR ALL USING (
        user_id = auth.user_id() 
        AND (business_id IS NULL OR auth.belongs_to_business(business_id))
    );

-- User dashboard widgets - scoped to user and business
CREATE POLICY "Users can view own widgets" ON public.user_dashboard_widgets
    FOR SELECT USING (
        user_id = auth.user_id() 
        AND (business_id IS NULL OR auth.belongs_to_business(business_id))
    );

CREATE POLICY "Users can manage own widgets" ON public.user_dashboard_widgets
    FOR ALL USING (
        user_id = auth.user_id() 
        AND (business_id IS NULL OR auth.belongs_to_business(business_id))
    );

-- Functions for user management
CREATE OR REPLACE FUNCTION public.get_user_businesses(p_user_id uuid DEFAULT NULL)
RETURNS TABLE(
    business_id uuid,
    business_name text,
    role user_role,
    joined_at timestamptz
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.id,
        b.name,
        bu.role,
        bu.joined_at
    FROM public.businesses b
    JOIN public.business_users bu ON b.id = bu.business_id
    WHERE bu.user_id = COALESCE(p_user_id, auth.user_id())
    AND bu.status = 'active'
    AND b.deleted_at IS NULL
    ORDER BY bu.joined_at DESC;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Add comments
COMMENT ON TABLE public.user_preferences IS 'User-specific preferences and settings';
COMMENT ON TABLE public.user_activities IS 'User activity audit trail';
COMMENT ON TABLE public.user_notifications IS 'User notifications queue';
COMMENT ON TABLE public.user_devices IS 'Registered devices for push notifications';
COMMENT ON TABLE public.user_saved_filters IS 'Saved searches and filters per user';
COMMENT ON TABLE public.user_dashboard_widgets IS 'Customizable dashboard widget configuration';