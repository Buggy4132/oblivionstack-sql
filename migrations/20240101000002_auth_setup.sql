-- Authentication Setup
-- This migration configures authentication and user management

-- Create custom auth schema tables
CREATE TABLE IF NOT EXISTS auth_helpers.user_profiles (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
    email text NOT NULL UNIQUE,
    full_name text,
    display_name text,
    avatar_url text,
    phone text,
    timezone text DEFAULT 'Australia/Perth',
    locale text DEFAULT 'en-AU',
    email_verified boolean DEFAULT false,
    phone_verified boolean DEFAULT false,
    onboarding_completed boolean DEFAULT false,
    metadata jsonb DEFAULT '{}',
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_email CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT valid_phone CHECK (phone IS NULL OR phone ~* '^\+?[1-9]\d{1,14}$')
);

-- Create auth tokens table for API access
CREATE TABLE IF NOT EXISTS auth_helpers.api_tokens (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id uuid NOT NULL,
    name text NOT NULL,
    token_hash text NOT NULL UNIQUE,
    last_used_at timestamptz,
    expires_at timestamptz,
    scopes text[] DEFAULT '{}',
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Create session management table
CREATE TABLE IF NOT EXISTS auth_helpers.user_sessions (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    session_token text NOT NULL UNIQUE,
    ip_address inet,
    user_agent text,
    last_activity timestamptz DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamptz NOT NULL,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Create password history table for security
CREATE TABLE IF NOT EXISTS auth_helpers.password_history (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    password_hash text NOT NULL,
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Create auth audit log
CREATE TABLE IF NOT EXISTS auth_helpers.auth_audit_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type text NOT NULL,
    ip_address inet,
    user_agent text,
    metadata jsonb DEFAULT '{}',
    created_at timestamptz DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes
CREATE INDEX idx_user_profiles_user_id ON auth_helpers.user_profiles(user_id);
CREATE INDEX idx_user_profiles_email ON auth_helpers.user_profiles(email);
CREATE INDEX idx_api_tokens_user_id ON auth_helpers.api_tokens(user_id);
CREATE INDEX idx_api_tokens_business_id ON auth_helpers.api_tokens(business_id);
CREATE INDEX idx_api_tokens_token_hash ON auth_helpers.api_tokens(token_hash);
CREATE INDEX idx_user_sessions_user_id ON auth_helpers.user_sessions(user_id);
CREATE INDEX idx_user_sessions_token ON auth_helpers.user_sessions(session_token);
CREATE INDEX idx_auth_audit_user_id ON auth_helpers.auth_audit_log(user_id);
CREATE INDEX idx_auth_audit_created ON auth_helpers.auth_audit_log(created_at DESC);

-- Create triggers
CREATE TRIGGER update_user_profiles_updated_at 
    BEFORE UPDATE ON auth_helpers.user_profiles 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

CREATE TRIGGER update_api_tokens_updated_at 
    BEFORE UPDATE ON auth_helpers.api_tokens 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

-- Function to create user profile on signup
CREATE OR REPLACE FUNCTION auth_helpers.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO auth_helpers.user_profiles (user_id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        NEW.raw_user_meta_data->>'full_name'
    );
    
    -- Log the signup event
    INSERT INTO auth_helpers.auth_audit_log (user_id, event_type, metadata)
    VALUES (
        NEW.id,
        'signup',
        jsonb_build_object(
            'email', NEW.email,
            'provider', NEW.raw_app_meta_data->>'provider'
        )
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new user signup
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION auth_helpers.handle_new_user();

-- Function to log authentication events
CREATE OR REPLACE FUNCTION auth_helpers.log_auth_event(
    p_user_id uuid,
    p_event_type text,
    p_metadata jsonb DEFAULT '{}'
)
RETURNS void AS $$
BEGIN
    INSERT INTO auth_helpers.auth_audit_log (
        user_id,
        event_type,
        ip_address,
        user_agent,
        metadata
    ) VALUES (
        p_user_id,
        p_event_type,
        (current_setting('request.headers', true)::json->>'x-real-ip')::inet,
        current_setting('request.headers', true)::json->>'user-agent',
        p_metadata
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check password history
CREATE OR REPLACE FUNCTION auth_helpers.check_password_history(
    p_user_id uuid,
    p_password_hash text,
    p_history_count int DEFAULT 5
)
RETURNS boolean AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM auth_helpers.password_history
        WHERE user_id = p_user_id
        AND password_hash = p_password_hash
        ORDER BY created_at DESC
        LIMIT p_history_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to clean up expired sessions
CREATE OR REPLACE FUNCTION auth_helpers.cleanup_expired_sessions()
RETURNS void AS $$
BEGIN
    DELETE FROM auth_helpers.user_sessions
    WHERE expires_at < CURRENT_TIMESTAMP;
    
    DELETE FROM auth_helpers.api_tokens
    WHERE expires_at < CURRENT_TIMESTAMP
    AND expires_at IS NOT NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add RLS policies for auth tables
ALTER TABLE auth_helpers.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_helpers.api_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_helpers.user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_helpers.password_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth_helpers.auth_audit_log ENABLE ROW LEVEL SECURITY;

-- User profiles policies
CREATE POLICY "Users can view own profile" ON auth_helpers.user_profiles
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can update own profile" ON auth_helpers.user_profiles
    FOR UPDATE USING (auth.uid() = user_id);

-- API tokens policies
CREATE POLICY "Users can view own tokens" ON auth_helpers.api_tokens
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own tokens" ON auth_helpers.api_tokens
    FOR ALL USING (auth.uid() = user_id);

-- Sessions policies
CREATE POLICY "Users can view own sessions" ON auth_helpers.user_sessions
    FOR SELECT USING (auth.uid() = user_id);

-- Add comments
COMMENT ON TABLE auth_helpers.user_profiles IS 'Extended user profile information';
COMMENT ON TABLE auth_helpers.api_tokens IS 'API tokens for programmatic access';
COMMENT ON TABLE auth_helpers.user_sessions IS 'Active user sessions tracking';
COMMENT ON TABLE auth_helpers.password_history IS 'Password history for security compliance';
COMMENT ON TABLE auth_helpers.auth_audit_log IS 'Authentication event audit trail';