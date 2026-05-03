-- ============================================================
-- MIGRATION 014 — Seed Test Users
-- Adds users for all roles (owner, manager, staff, cashier)
-- Password for all users is: password123
-- ============================================================

DO $$ 
DECLARE
    -- Use the existing business from 02_seed_usecase.sql or create a new one
    biz_spa_id UUID := 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'::UUID;

    -- User UUIDs
    owner2_id UUID := gen_random_uuid();
    manager_id UUID := gen_random_uuid();
    staff_id UUID := gen_random_uuid();
    cashier_id UUID := gen_random_uuid();
    
    -- Default password hash for 'password123'
    default_password_hash text := crypt('password123', gen_salt('bf'));
BEGIN
    -- Ensure the business exists before inserting profiles
    IF EXISTS (SELECT 1 FROM businesses WHERE id = biz_spa_id) THEN
        
        -- 1. Owner User
        INSERT INTO auth.users (id, instance_id, role, aud, email, raw_app_meta_data, raw_user_meta_data, encrypted_password, email_confirmed_at, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
        VALUES (owner2_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.com', '{"provider":"email","providers":["email"]}', '{}', default_password_hash, NOW(), NOW(), NOW(), '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), owner2_id, owner2_id::text, 'email', format('{"sub":"%s","email":"%s"}', owner2_id::text, 'owner@test.com')::jsonb, NOW(), NOW(), NOW());

        INSERT INTO profiles (id, business_id, full_name, role)
        VALUES (owner2_id, biz_spa_id, 'Test Owner', 'owner');

        -- 2. Manager User
        INSERT INTO auth.users (id, instance_id, role, aud, email, raw_app_meta_data, raw_user_meta_data, encrypted_password, email_confirmed_at, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
        VALUES (manager_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'manager@test.com', '{"provider":"email","providers":["email"]}', '{}', default_password_hash, NOW(), NOW(), NOW(), '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), manager_id, manager_id::text, 'email', format('{"sub":"%s","email":"%s"}', manager_id::text, 'manager@test.com')::jsonb, NOW(), NOW(), NOW());

        INSERT INTO profiles (id, business_id, full_name, role)
        VALUES (manager_id, biz_spa_id, 'Test Manager', 'manager');

        -- 3. Staff User
        INSERT INTO auth.users (id, instance_id, role, aud, email, raw_app_meta_data, raw_user_meta_data, encrypted_password, email_confirmed_at, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
        VALUES (staff_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff@test.com', '{"provider":"email","providers":["email"]}', '{}', default_password_hash, NOW(), NOW(), NOW(), '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), staff_id, staff_id::text, 'email', format('{"sub":"%s","email":"%s"}', staff_id::text, 'staff@test.com')::jsonb, NOW(), NOW(), NOW());

        INSERT INTO profiles (id, business_id, full_name, role)
        VALUES (staff_id, biz_spa_id, 'Test Staff', 'staff');

        -- 4. Cashier User
        INSERT INTO auth.users (id, instance_id, role, aud, email, raw_app_meta_data, raw_user_meta_data, encrypted_password, email_confirmed_at, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
        VALUES (cashier_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'cashier@test.com', '{"provider":"email","providers":["email"]}', '{}', default_password_hash, NOW(), NOW(), NOW(), '', '', '', '');
        
        INSERT INTO auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
        VALUES (gen_random_uuid(), cashier_id, cashier_id::text, 'email', format('{"sub":"%s","email":"%s"}', cashier_id::text, 'cashier@test.com')::jsonb, NOW(), NOW(), NOW());

        INSERT INTO profiles (id, business_id, full_name, role)
        VALUES (cashier_id, biz_spa_id, 'Test Cashier', 'cashier');

    END IF;
END $$;
