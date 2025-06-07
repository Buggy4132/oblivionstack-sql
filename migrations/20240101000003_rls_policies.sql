-- Row Level Security Policies
-- This migration sets up comprehensive RLS policies for multi-tenant security

-- Helper function for RLS policy creation
CREATE OR REPLACE FUNCTION public.create_rls_policies(
    schema_name text,
    table_name text,
    enable_insert boolean DEFAULT true,
    enable_select boolean DEFAULT true,
    enable_update boolean DEFAULT true,
    enable_delete boolean DEFAULT true
)
RETURNS void AS $$
DECLARE
    full_table_name text;
BEGIN
    full_table_name := schema_name || '.' || table_name;
    
    -- Enable RLS
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', full_table_name);
    
    -- Create SELECT policy
    IF enable_select THEN
        EXECUTE format(
            'CREATE POLICY "Users can view own business %s" ON %s
            FOR SELECT USING (
                business_id IN (
                    SELECT business_id FROM public.business_users 
                    WHERE user_id = auth.user_id() AND status = ''active''
                )
            )',
            table_name, full_table_name
        );
    END IF;
    
    -- Create INSERT policy
    IF enable_insert THEN
        EXECUTE format(
            'CREATE POLICY "Users can insert into own business %s" ON %s
            FOR INSERT WITH CHECK (
                business_id IN (
                    SELECT business_id FROM public.business_users 
                    WHERE user_id = auth.user_id() 
                    AND status = ''active''
                    AND role IN (''owner'', ''admin'', ''manager'')
                )
            )',
            table_name, full_table_name
        );
    END IF;
    
    -- Create UPDATE policy
    IF enable_update THEN
        EXECUTE format(
            'CREATE POLICY "Users can update own business %s" ON %s
            FOR UPDATE USING (
                business_id IN (
                    SELECT business_id FROM public.business_users 
                    WHERE user_id = auth.user_id() 
                    AND status = ''active''
                    AND role IN (''owner'', ''admin'', ''manager'')
                )
            )',
            table_name, full_table_name
        );
    END IF;
    
    -- Create DELETE policy
    IF enable_delete THEN
        EXECUTE format(
            'CREATE POLICY "Users can delete from own business %s" ON %s
            FOR DELETE USING (
                business_id IN (
                    SELECT business_id FROM public.business_users 
                    WHERE user_id = auth.user_id() 
                    AND status = ''active''
                    AND role IN (''owner'', ''admin'')
                )
            )',
            table_name, full_table_name
        );
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create optimized RLS helper functions
CREATE OR REPLACE FUNCTION public.user_business_ids()
RETURNS TABLE(business_id uuid) 
LANGUAGE sql 
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT business_id 
    FROM public.business_users 
    WHERE user_id = auth.user_id() 
    AND status = 'active'
$$;

CREATE OR REPLACE FUNCTION public.user_business_ids_with_role(required_roles user_role[])
RETURNS TABLE(business_id uuid) 
LANGUAGE sql 
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT business_id 
    FROM public.business_users 
    WHERE user_id = auth.user_id() 
    AND status = 'active'
    AND role = ANY(required_roles)
$$;

-- Create materialized view for performance (refresh periodically)
CREATE MATERIALIZED VIEW IF NOT EXISTS public.active_user_businesses AS
SELECT 
    user_id,
    business_id,
    role,
    array_agg(role) OVER (PARTITION BY user_id) as all_roles
FROM public.business_users
WHERE status = 'active'
WITH DATA;

CREATE UNIQUE INDEX idx_active_user_businesses_unique 
ON public.active_user_businesses (user_id, business_id);

CREATE INDEX idx_active_user_businesses_user 
ON public.active_user_businesses (user_id);

CREATE INDEX idx_active_user_businesses_business 
ON public.active_user_businesses (business_id);

-- Function to refresh materialized view
CREATE OR REPLACE FUNCTION public.refresh_active_user_businesses()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.active_user_businesses;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create generic RLS policies for common patterns
-- Policy for user-owned resources
CREATE OR REPLACE FUNCTION public.create_user_rls_policies(
    schema_name text,
    table_name text
)
RETURNS void AS $$
DECLARE
    full_table_name text;
BEGIN
    full_table_name := schema_name || '.' || table_name;
    
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', full_table_name);
    
    EXECUTE format(
        'CREATE POLICY "Users can view own %s" ON %s
        FOR SELECT USING (user_id = auth.user_id())',
        table_name, full_table_name
    );
    
    EXECUTE format(
        'CREATE POLICY "Users can insert own %s" ON %s
        FOR INSERT WITH CHECK (user_id = auth.user_id())',
        table_name, full_table_name
    );
    
    EXECUTE format(
        'CREATE POLICY "Users can update own %s" ON %s
        FOR UPDATE USING (user_id = auth.user_id())',
        table_name, full_table_name
    );
    
    EXECUTE format(
        'CREATE POLICY "Users can delete own %s" ON %s
        FOR DELETE USING (user_id = auth.user_id())',
        table_name, full_table_name
    );
END;
$$ LANGUAGE plpgsql;

-- Create public read policies
CREATE OR REPLACE FUNCTION public.create_public_read_policy(
    schema_name text,
    table_name text,
    condition text DEFAULT 'true'
)
RETURNS void AS $$
DECLARE
    full_table_name text;
BEGIN
    full_table_name := schema_name || '.' || table_name;
    
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', full_table_name);
    
    EXECUTE format(
        'CREATE POLICY "Public can read %s" ON %s
        FOR SELECT USING (%s)',
        table_name, full_table_name, condition
    );
END;
$$ LANGUAGE plpgsql;

-- Create service role bypass policies
CREATE OR REPLACE FUNCTION public.create_service_role_policies(
    schema_name text,
    table_name text
)
RETURNS void AS $$
DECLARE
    full_table_name text;
BEGIN
    full_table_name := schema_name || '.' || table_name;
    
    EXECUTE format(
        'CREATE POLICY "Service role has full access to %s" ON %s
        TO service_role USING (true) WITH CHECK (true)',
        table_name, full_table_name
    );
END;
$$ LANGUAGE plpgsql;

-- RLS policy templates for different access patterns
-- Template 1: Hierarchical access (owner > admin > manager > staff)
CREATE OR REPLACE FUNCTION public.check_hierarchical_access(
    target_role user_role,
    required_permission text
)
RETURNS boolean AS $$
DECLARE
    user_role_value user_role;
BEGIN
    SELECT role INTO user_role_value
    FROM public.business_users
    WHERE user_id = auth.user_id()
    AND business_id = auth.business_id()
    AND status = 'active'
    LIMIT 1;
    
    -- Owner can do everything
    IF user_role_value = 'owner' THEN
        RETURN true;
    END IF;
    
    -- Admin can do most things except owner-level
    IF user_role_value = 'admin' AND required_permission != 'owner_only' THEN
        RETURN true;
    END IF;
    
    -- Manager can manage staff and below
    IF user_role_value = 'manager' AND target_role IN ('staff', 'client') 
       AND required_permission IN ('read', 'write') THEN
        RETURN true;
    END IF;
    
    -- Staff can only read
    IF user_role_value = 'staff' AND required_permission = 'read' THEN
        RETURN true;
    END IF;
    
    RETURN false;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Add comments
COMMENT ON FUNCTION public.create_rls_policies IS 'Helper to create standard RLS policies for business-scoped tables';
COMMENT ON FUNCTION public.user_business_ids IS 'Returns all active business IDs for current user';
COMMENT ON FUNCTION public.user_business_ids_with_role IS 'Returns business IDs where user has specific roles';
COMMENT ON MATERIALIZED VIEW public.active_user_businesses IS 'Cached view of active user-business relationships for performance';