-- Create Default Admin User (Development Only)
-- This migration creates a default admin user for development purposes
-- DO NOT RUN IN PRODUCTION

-- Only run in development environment
DO $$
BEGIN
    -- Check if we're in development (you can adjust this check based on your setup)
    IF current_setting('app.environment', true) = 'development' OR 
       current_database() LIKE '%_dev%' OR
       current_database() LIKE '%_local%' THEN
        
        -- Create admin user if doesn't exist
        IF NOT EXISTS (
            SELECT 1 FROM auth.users WHERE email = 'admin@oblivionstack.com'
        ) THEN
            -- Note: In a real scenario, you'd use Supabase Auth API to create users
            -- This is a placeholder to show the structure
            RAISE NOTICE 'Default admin user should be created via Supabase Auth API';
            
            -- Insert a record to track that we need to create this user
            INSERT INTO public.marketing_leads (
                email,
                full_name,
                lead_status,
                lead_score,
                interests,
                created_at
            ) VALUES (
                'admin@oblivionstack.com',
                'System Administrator',
                'converted',
                100,
                ARRAY['system_admin'],
                CURRENT_TIMESTAMP
            ) ON CONFLICT (email) DO NOTHING;
        END IF;
    END IF;
END $$;

-- Create function to initialize demo data (development only)
CREATE OR REPLACE FUNCTION public.initialize_demo_data()
RETURNS void AS $$
BEGIN
    -- Check environment
    IF current_setting('app.environment', true) != 'development' THEN
        RAISE EXCEPTION 'Demo data can only be initialized in development environment';
    END IF;
    
    -- Create sample onboarding sessions
    INSERT INTO public.onboarding_sessions (
        email,
        business_name,
        industry,
        status,
        questionnaire_responses,
        recommended_tier,
        source
    ) VALUES 
    (
        'demo.salon@example.com',
        'Elegant Cuts Salon',
        'salons_barbershops',
        'completed',
        jsonb_build_object(
            'business_size', '3-5',
            'locations', '1',
            'current_booking', 'paper',
            'growth_goals', ARRAY['efficiency', 'revenue']
        ),
        'advanced',
        'demo'
    ),
    (
        'demo.mechanic@example.com',
        'Quick Fix Auto',
        'auto_mechanics',
        'in_progress',
        jsonb_build_object(
            'shop_size', '3-5',
            'mechanics_count', '3-5',
            'service_types', ARRAY['oil_change', 'maintenance', 'repairs']
        ),
        'basic',
        'demo'
    ),
    (
        'demo.spa@example.com',
        'Serenity Wellness Spa',
        'massage_therapy',
        'completed',
        jsonb_build_object(
            'practice_type', 'spa',
            'treatment_types', ARRAY['massage', 'facial', 'body_treatments'],
            'client_records', 'paper'
        ),
        'professional',
        'demo'
    );
    
    -- Create sample marketing leads
    INSERT INTO public.marketing_leads (
        email,
        full_name,
        company_name,
        industry,
        lead_status,
        lead_score,
        newsletter_subscribed
    ) VALUES 
    (
        'interested.salon@example.com',
        'Sarah Johnson',
        'Style Studio',
        'salons_barbershops',
        'qualified',
        75,
        true
    ),
    (
        'potential.mechanic@example.com',
        'Mike Thompson',
        'Thompson Auto Care',
        'auto_mechanics',
        'contacted',
        60,
        true
    ),
    (
        'new.spa@example.com',
        'Emma Williams',
        'Tranquil Touch Therapy',
        'massage_therapy',
        'new',
        40,
        false
    );
    
    -- Create sample consultation bookings
    INSERT INTO public.consultation_bookings (
        name,
        email,
        company_name,
        preferred_date,
        preferred_time,
        meeting_type,
        status,
        customer_notes
    ) VALUES 
    (
        'John Smith',
        'john@smithsalon.com',
        'Smith & Co Salon',
        CURRENT_DATE + interval '3 days',
        '14:00:00',
        'video',
        'confirmed',
        'Looking to modernize our booking system'
    ),
    (
        'Lisa Chen',
        'lisa@zenauto.com',
        'Zen Auto Repair',
        CURRENT_DATE + interval '7 days',
        '10:00:00',
        'phone',
        'pending',
        'Need help with inventory management'
    );
    
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to clean up demo data
CREATE OR REPLACE FUNCTION public.cleanup_demo_data()
RETURNS void AS $$
BEGIN
    -- Delete demo data
    DELETE FROM public.onboarding_sessions WHERE source = 'demo';
    DELETE FROM public.marketing_leads WHERE email LIKE '%@example.com';
    DELETE FROM public.consultation_bookings WHERE email LIKE '%@example.com';
    
    -- Reset sequences if needed
    -- ALTER SEQUENCE ... RESTART WITH 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add helpful development functions
CREATE OR REPLACE FUNCTION public.get_system_stats()
RETURNS jsonb AS $$
DECLARE
    v_stats jsonb;
BEGIN
    SELECT jsonb_build_object(
        'total_users', (SELECT COUNT(*) FROM auth.users),
        'total_businesses', (SELECT COUNT(*) FROM public.businesses WHERE id != '00000000-0000-0000-0000-000000000000'),
        'active_sessions', (SELECT COUNT(*) FROM public.onboarding_sessions WHERE status = 'in_progress'),
        'total_leads', (SELECT COUNT(*) FROM public.marketing_leads),
        'pending_consultations', (SELECT COUNT(*) FROM public.consultation_bookings WHERE status = 'pending'),
        'questionnaire_templates', (SELECT COUNT(*) FROM public.questionnaire_templates WHERE is_active = true),
        'environment', current_setting('app.environment', true),
        'database', current_database(),
        'timestamp', CURRENT_TIMESTAMP
    ) INTO v_stats;
    
    RETURN v_stats;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Grant execute permissions on helper functions
GRANT EXECUTE ON FUNCTION public.initialize_demo_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_demo_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_system_stats() TO authenticated, anon;

-- Add comments
COMMENT ON FUNCTION public.initialize_demo_data() IS 'Creates demo data for development environment';
COMMENT ON FUNCTION public.cleanup_demo_data() IS 'Removes all demo data';
COMMENT ON FUNCTION public.get_system_stats() IS 'Returns system statistics for monitoring';