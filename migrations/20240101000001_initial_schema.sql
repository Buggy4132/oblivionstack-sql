-- Initial Schema Setup
-- This migration creates the foundational schema structure for OblivionStack

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Create custom types
CREATE TYPE business_status AS ENUM ('active', 'inactive', 'suspended', 'trial', 'cancelled');
CREATE TYPE user_role AS ENUM ('owner', 'admin', 'manager', 'staff', 'client');
CREATE TYPE subscription_tier AS ENUM ('basic', 'advanced', 'professional', 'enterprise');
CREATE TYPE subscription_status AS ENUM ('active', 'cancelled', 'past_due', 'trialing', 'paused');
CREATE TYPE industry_type AS ENUM ('salons_barbershops', 'auto_mechanics', 'massage_therapy', 'fitness_wellness', 'other');
CREATE TYPE onboarding_status AS ENUM ('not_started', 'in_progress', 'completed', 'abandoned');
CREATE TYPE module_category AS ENUM ('transform', 'flow', 'connect');

-- Create schemas for logical separation
CREATE SCHEMA IF NOT EXISTS auth_helpers;
CREATE SCHEMA IF NOT EXISTS business_logic;
CREATE SCHEMA IF NOT EXISTS analytics;

-- Grant schema usage
GRANT USAGE ON SCHEMA auth_helpers TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA business_logic TO postgres, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA analytics TO postgres, anon, authenticated, service_role;

-- Immutable function for current user ID (optimized for RLS)
CREATE OR REPLACE FUNCTION auth.user_id() 
RETURNS uuid 
LANGUAGE sql 
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    auth.jwt() ->> 'sub',
    '00000000-0000-0000-0000-000000000000'
  )::uuid
$$;

-- Immutable function for current user's business ID
CREATE OR REPLACE FUNCTION auth.business_id() 
RETURNS uuid 
LANGUAGE sql 
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT business_id 
  FROM public.business_users 
  WHERE user_id = auth.user_id() 
  AND status = 'active'
  LIMIT 1
$$;

-- Immutable function for checking user role
CREATE OR REPLACE FUNCTION auth.has_role(required_role user_role) 
RETURNS boolean 
LANGUAGE sql 
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.business_users 
    WHERE user_id = auth.user_id() 
    AND status = 'active'
    AND (
      role = required_role 
      OR role = 'owner'
      OR (role = 'admin' AND required_role IN ('manager', 'staff'))
      OR (role = 'manager' AND required_role = 'staff')
    )
  )
$$;

-- Helper function to check if user belongs to a business
CREATE OR REPLACE FUNCTION auth.belongs_to_business(check_business_id uuid) 
RETURNS boolean 
LANGUAGE sql 
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.business_users 
    WHERE user_id = auth.user_id() 
    AND business_id = check_business_id
    AND status = 'active'
  )
$$;

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create audit log function
CREATE OR REPLACE FUNCTION public.create_audit_log()
RETURNS TRIGGER AS $$
DECLARE
    audit_user_id uuid;
    audit_business_id uuid;
    old_data jsonb;
    new_data jsonb;
BEGIN
    audit_user_id := auth.user_id();
    audit_business_id := auth.business_id();
    
    IF TG_OP = 'DELETE' THEN
        old_data := to_jsonb(OLD);
        new_data := null;
    ELSIF TG_OP = 'UPDATE' THEN
        old_data := to_jsonb(OLD);
        new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'INSERT' THEN
        old_data := null;
        new_data := to_jsonb(NEW);
    END IF;
    
    INSERT INTO public.audit_logs (
        table_name,
        record_id,
        action,
        user_id,
        business_id,
        old_data,
        new_data,
        ip_address,
        user_agent
    ) VALUES (
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        audit_user_id,
        audit_business_id,
        old_data,
        new_data,
        current_setting('request.headers', true)::json->>'x-real-ip',
        current_setting('request.headers', true)::json->>'user-agent'
    );
    
    RETURN NEW;
END;
$$ language 'plpgsql' SECURITY DEFINER;

-- Create index creation helper
CREATE OR REPLACE FUNCTION public.create_standard_indexes(table_name text)
RETURNS void AS $$
BEGIN
    -- Create indexes for common columns
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_business_id ON public.%s (business_id)', table_name, table_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_created_at ON public.%s (created_at DESC)', table_name, table_name);
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_updated_at ON public.%s (updated_at DESC)', table_name, table_name);
    
    -- Create composite index for business_id and created_at
    EXECUTE format('CREATE INDEX IF NOT EXISTS idx_%s_business_created ON public.%s (business_id, created_at DESC)', table_name, table_name);
END;
$$ language 'plpgsql';

-- Add comments for documentation
COMMENT ON FUNCTION auth.user_id() IS 'Returns the current authenticated user ID';
COMMENT ON FUNCTION auth.business_id() IS 'Returns the current user''s active business ID';
COMMENT ON FUNCTION auth.has_role(user_role) IS 'Checks if current user has the specified role or higher';
COMMENT ON FUNCTION auth.belongs_to_business(uuid) IS 'Checks if current user belongs to the specified business';