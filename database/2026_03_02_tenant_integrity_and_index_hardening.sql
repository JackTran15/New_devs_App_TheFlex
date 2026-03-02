-- Tenant integrity + performance hardening (idempotent)
-- Safe to run multiple times in Supabase SQL editor.

BEGIN;

-- =========================================================
-- 1) Core table hardening for this repo schema
-- =========================================================

-- properties.tenant_id should be required
DO $$
BEGIN
  IF to_regclass('public.properties') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.properties WHERE tenant_id IS NULL) THEN
      RAISE NOTICE 'Skipped NOT NULL on properties.tenant_id because NULL rows exist';
    ELSE
      EXECUTE 'ALTER TABLE public.properties ALTER COLUMN tenant_id SET NOT NULL';
    END IF;
  END IF;
END $$;

-- reservations.property_id / tenant_id should be required
DO $$
BEGIN
  IF to_regclass('public.reservations') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.reservations WHERE property_id IS NULL) THEN
      RAISE NOTICE 'Skipped NOT NULL on reservations.property_id because NULL rows exist';
    ELSE
      EXECUTE 'ALTER TABLE public.reservations ALTER COLUMN property_id SET NOT NULL';
    END IF;

    IF EXISTS (SELECT 1 FROM public.reservations WHERE tenant_id IS NULL) THEN
      RAISE NOTICE 'Skipped NOT NULL on reservations.tenant_id because NULL rows exist';
    ELSE
      EXECUTE 'ALTER TABLE public.reservations ALTER COLUMN tenant_id SET NOT NULL';
    END IF;
  END IF;
END $$;

-- Ensure non-negative revenue amounts
DO $$
BEGIN
  IF to_regclass('public.reservations') IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'reservations_total_amount_nonnegative'
    ) THEN
      ALTER TABLE public.reservations
      ADD CONSTRAINT reservations_total_amount_nonnegative
      CHECK (total_amount >= 0);
    END IF;
  END IF;
END $$;

-- =========================================================
-- 2) Query performance indexes (dashboard + search)
-- =========================================================

CREATE INDEX IF NOT EXISTS idx_reservations_tenant_property_checkin
  ON public.reservations (tenant_id, property_id, check_in_date);

CREATE INDEX IF NOT EXISTS idx_reservations_tenant_checkin
  ON public.reservations (tenant_id, check_in_date);

CREATE INDEX IF NOT EXISTS idx_properties_tenant_name
  ON public.properties (tenant_id, name);

CREATE INDEX IF NOT EXISTS idx_properties_tenant_lower_name
  ON public.properties (tenant_id, lower(name));

-- =========================================================
-- 3) Supabase auth-related uniqueness hardening
--    (these tables exist in the real app DB, not local seed schema)
-- =========================================================

-- user_tenants: ensure one row per (tenant_id, user_id)
DO $$
BEGIN
  IF to_regclass('public.user_tenants') IS NOT NULL THEN
    DELETE FROM public.user_tenants t
    USING public.user_tenants d
    WHERE t.ctid < d.ctid
      AND t.tenant_id = d.tenant_id
      AND t.user_id = d.user_id;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'user_tenants_tenant_user_unique'
    ) THEN
      ALTER TABLE public.user_tenants
      ADD CONSTRAINT user_tenants_tenant_user_unique
      UNIQUE (tenant_id, user_id);
    END IF;
  END IF;
END $$;

-- user_permissions: prevent duplicate permission triples
DO $$
BEGIN
  IF to_regclass('public.user_permissions') IS NOT NULL THEN
    DELETE FROM public.user_permissions t
    USING public.user_permissions d
    WHERE t.ctid < d.ctid
      AND t.user_id = d.user_id
      AND t.section = d.section
      AND t.action = d.action;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'user_permissions_user_section_action_unique'
    ) THEN
      ALTER TABLE public.user_permissions
      ADD CONSTRAINT user_permissions_user_section_action_unique
      UNIQUE (user_id, section, action);
    END IF;
  END IF;
END $$;

-- users_city: prevent duplicate city assignment rows
DO $$
BEGIN
  IF to_regclass('public.users_city') IS NOT NULL THEN
    DELETE FROM public.users_city t
    USING public.users_city d
    WHERE t.ctid < d.ctid
      AND t.user_id = d.user_id
      AND t.city_name = d.city_name;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = 'users_city_user_city_unique'
    ) THEN
      ALTER TABLE public.users_city
      ADD CONSTRAINT users_city_user_city_unique
      UNIQUE (user_id, city_name);
    END IF;
  END IF;
END $$;

-- Supporting indexes for auth lookup-heavy paths
CREATE INDEX IF NOT EXISTS idx_user_tenants_tenant_active_user
  ON public.user_tenants (tenant_id, is_active, user_id);

CREATE INDEX IF NOT EXISTS idx_user_permissions_user
  ON public.user_permissions (user_id);

CREATE INDEX IF NOT EXISTS idx_users_city_user
  ON public.users_city (user_id);

COMMIT;
