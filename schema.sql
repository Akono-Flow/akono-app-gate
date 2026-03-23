-- ═══════════════════════════════════════════════════════════════════════════════
-- SCQ LEARNING PORTAL — SUPABASE SCHEMA
-- Version 2.0  |  Single-device enforcement, plan-based access, admin RPC layer
--
-- HOW TO APPLY:
--   1. Open Supabase Dashboard → SQL Editor → New Query
--   2. Paste this entire file and click RUN
--   3. After running, promote your admin account (see bottom of this file)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Extensions ───────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Enum-like domains ────────────────────────────────────────────────────────
-- (Using check constraints instead for portability)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TABLES
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── plans ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.plans (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL UNIQUE,
  description TEXT,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.plans IS
  'Subscription tiers (Free, Student, Teacher, etc.). Each plan grants access to a set of apps.';

-- ─── apps ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.apps (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT        NOT NULL,
  slug        TEXT        NOT NULL UNIQUE,
  url         TEXT,
  description TEXT,
  icon        TEXT        NOT NULL DEFAULT '🔬',
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT  apps_slug_format CHECK (slug ~ '^[a-z0-9\-]+$')
);

COMMENT ON TABLE public.apps IS
  'Registry of every gated app. The slug must exactly match the string used in requireAppAccess().';
COMMENT ON COLUMN public.apps.slug IS
  'Lowercase identifier, letters/numbers/hyphens only. Must match the app code exactly.';

-- ─── plan_apps ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.plan_apps (
  plan_id UUID NOT NULL REFERENCES public.plans(id) ON DELETE CASCADE,
  app_id  UUID NOT NULL REFERENCES public.apps(id)  ON DELETE CASCADE,
  PRIMARY KEY (plan_id, app_id)
);

COMMENT ON TABLE public.plan_apps IS
  'Junction table: which apps are included in each plan.';

-- ─── profiles ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id               UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email            TEXT        NOT NULL,
  full_name        TEXT        NOT NULL DEFAULT '',
  role             TEXT        NOT NULL DEFAULT 'user'
                               CHECK (role IN ('user', 'admin')),
  is_active        BOOLEAN     NOT NULL DEFAULT FALSE,
  plan_id          UUID        REFERENCES public.plans(id) ON DELETE SET NULL,
  -- Single-device enforcement
  device_token     TEXT,
  device_info      TEXT,       -- JSON: {ua, lang, tz, ts}
  device_last_seen TIMESTAMPTZ,
  -- Admin notes
  notes            TEXT        DEFAULT '',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.profiles IS
  'One row per authenticated user. Extends auth.users with role, plan, and device tracking.';
COMMENT ON COLUMN public.profiles.device_token IS
  'Single-device UUID. If a second device logs in, a new token is written here and the first device is ejected.';
COMMENT ON COLUMN public.profiles.is_active IS
  'Admin must manually set TRUE before the user can access any gated app.';

-- ─── audit_log ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.audit_log (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id          UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_email       TEXT,
  target_user_id    UUID,
  target_user_email TEXT,
  action            TEXT        NOT NULL,
  details           JSONB       NOT NULL DEFAULT '{}',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.audit_log IS
  'Immutable log of all admin actions and important auth events.';
CREATE INDEX IF NOT EXISTS audit_log_created_at_idx ON public.audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_actor_idx      ON public.audit_log (actor_id);
CREATE INDEX IF NOT EXISTS audit_log_target_idx     ON public.audit_log (target_user_id);

-- ═══════════════════════════════════════════════════════════════════════════════
-- UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── Auto-stamp updated_at ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_update_timestamp()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_timestamp();

CREATE OR REPLACE TRIGGER trg_plans_updated_at
  BEFORE UPDATE ON public.plans
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_timestamp();

CREATE OR REPLACE TRIGGER trg_apps_updated_at
  BEFORE UPDATE ON public.apps
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_timestamp();

-- ─── Auto-create profile on signup ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role, is_active)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    'user',
    FALSE   -- ALL new users start inactive; admin must approve
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.fn_handle_new_user();

-- ─── is_admin() helper ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plans     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.apps      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_apps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

-- Drop any existing policies to avoid conflicts on re-run
DO $$ BEGIN
  EXECUTE (
    SELECT string_agg('DROP POLICY IF EXISTS ' || quote_ident(policyname) || ' ON ' || schemaname || '.' || tablename || ';', E'\n')
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename IN ('profiles','plans','apps','plan_apps','audit_log')
  );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ── profiles ──────────────────────────────────────────────────────────────────
-- Authenticated users can read their own row
CREATE POLICY "profiles: user reads own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- Admins can read all rows
CREATE POLICY "profiles: admin reads all"
  ON public.profiles FOR SELECT
  USING (public.is_admin());

-- Users can update their own device fields (for device registration)
CREATE POLICY "profiles: user updates own device"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Admins can update any row
CREATE POLICY "profiles: admin updates all"
  ON public.profiles FOR UPDATE
  USING (public.is_admin());

-- Admins can delete rows (soft delete preferred; hard delete via fn)
CREATE POLICY "profiles: admin deletes"
  ON public.profiles FOR DELETE
  USING (public.is_admin());

-- ── plans ─────────────────────────────────────────────────────────────────────
CREATE POLICY "plans: authenticated reads"
  ON public.plans FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "plans: admin full access"
  ON public.plans FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ── apps ──────────────────────────────────────────────────────────────────────
CREATE POLICY "apps: authenticated reads"
  ON public.apps FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "apps: admin full access"
  ON public.apps FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ── plan_apps ─────────────────────────────────────────────────────────────────
CREATE POLICY "plan_apps: authenticated reads"
  ON public.plan_apps FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "plan_apps: admin full access"
  ON public.plan_apps FOR ALL
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ── audit_log ─────────────────────────────────────────────────────────────────
CREATE POLICY "audit_log: admin reads"
  ON public.audit_log FOR SELECT
  USING (public.is_admin());

CREATE POLICY "audit_log: authenticated inserts"
  ON public.audit_log FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- ═══════════════════════════════════════════════════════════════════════════════
-- ADMIN REMOTE PROCEDURE CALLS (all SECURITY DEFINER to bypass RLS)
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── admin_get_users() ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_users()
RETURNS TABLE (
  id               UUID,
  email            TEXT,
  full_name        TEXT,
  role             TEXT,
  is_active        BOOLEAN,
  plan_id          UUID,
  plan_name        TEXT,
  device_token     TEXT,
  device_last_seen TIMESTAMPTZ,
  device_info      TEXT,
  notes            TEXT,
  created_at       TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
    SELECT
      p.id, p.email, p.full_name, p.role,
      p.is_active, p.plan_id, pl.name AS plan_name,
      p.device_token, p.device_last_seen, p.device_info,
      p.notes, p.created_at, p.updated_at
    FROM public.profiles p
    LEFT JOIN public.plans pl ON p.plan_id = pl.id
    ORDER BY p.created_at DESC;
END;
$$;

-- ─── admin_get_stats() ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_stats()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v JSONB;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  SELECT jsonb_build_object(
    'total_users',     (SELECT COUNT(*) FROM public.profiles WHERE role = 'user'),
    'active_users',    (SELECT COUNT(*) FROM public.profiles WHERE role = 'user' AND is_active = TRUE),
    'pending_users',   (SELECT COUNT(*) FROM public.profiles WHERE role = 'user' AND is_active = FALSE),
    'users_with_plan', (SELECT COUNT(*) FROM public.profiles WHERE role = 'user' AND plan_id IS NOT NULL),
    'total_plans',     (SELECT COUNT(*) FROM public.plans),
    'active_plans',    (SELECT COUNT(*) FROM public.plans WHERE is_active = TRUE),
    'total_apps',      (SELECT COUNT(*) FROM public.apps),
    'active_apps',     (SELECT COUNT(*) FROM public.apps WHERE is_active = TRUE),
    'active_sessions', (SELECT COUNT(*) FROM public.profiles WHERE device_token IS NOT NULL),
    'recent_logins',   (
      SELECT COUNT(*) FROM public.audit_log
      WHERE action = 'login' AND created_at > NOW() - INTERVAL '24 hours'
    )
  ) INTO v;

  RETURN v;
END;
$$;

-- ─── admin_update_user(target_id, field, value) ───────────────────────────────
-- field values: 'is_active', 'plan_id', 'clear_plan', 'role', 'notes'
CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_target_id UUID,
  p_field     TEXT,
  p_value     TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  IF p_field = 'is_active' THEN
    UPDATE public.profiles
    SET is_active = (p_value = 'true')
    WHERE id = p_target_id;

  ELSIF p_field = 'plan_id' THEN
    UPDATE public.profiles
    SET plan_id = p_value::UUID
    WHERE id = p_target_id;

  ELSIF p_field = 'clear_plan' THEN
    UPDATE public.profiles
    SET plan_id = NULL
    WHERE id = p_target_id;

  ELSIF p_field = 'role' THEN
    IF p_value NOT IN ('user', 'admin') THEN
      RAISE EXCEPTION 'Invalid role value: %', p_value;
    END IF;
    UPDATE public.profiles
    SET role = p_value
    WHERE id = p_target_id;

  ELSIF p_field = 'notes' THEN
    UPDATE public.profiles
    SET notes = COALESCE(p_value, '')
    WHERE id = p_target_id;

  ELSE
    RAISE EXCEPTION 'Unknown field: %', p_field;
  END IF;
END;
$$;

-- ─── admin_revoke_session(target_id) ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_revoke_session(p_target_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  UPDATE public.profiles
  SET device_token = NULL, device_info = NULL
  WHERE id = p_target_id;
END;
$$;

-- ─── admin_delete_user(target_id) ─────────────────────────────────────────────
-- NOTE: This attempts to remove the row from auth.users (cascades to profiles).
-- If it fails due to permissions, use Supabase Dashboard → Authentication → Users.
CREATE OR REPLACE FUNCTION public.admin_delete_user(p_target_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;
  -- Soft-delete first: clear sensitive data
  UPDATE public.profiles
  SET
    is_active    = FALSE,
    plan_id      = NULL,
    device_token = NULL,
    device_info  = NULL,
    notes        = '[DELETED] ' || COALESCE(notes, '')
  WHERE id = p_target_id;

  -- Attempt hard delete from auth.users (requires postgres-level permissions)
  DELETE FROM auth.users WHERE id = p_target_id;
END;
$$;

-- ─── admin_set_plan_apps(plan_id, app_ids[]) ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_plan_apps(
  p_plan_id UUID,
  p_app_ids UUID[]
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  -- Remove all current assignments for this plan
  DELETE FROM public.plan_apps WHERE plan_id = p_plan_id;

  -- Insert the new set (if any selected)
  IF p_app_ids IS NOT NULL AND array_length(p_app_ids, 1) > 0 THEN
    INSERT INTO public.plan_apps (plan_id, app_id)
    SELECT p_plan_id, unnest(p_app_ids)
    ON CONFLICT DO NOTHING;
  END IF;
END;
$$;

-- ─── get_my_apps() ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_apps()
RETURNS TABLE (
  id          UUID,
  name        TEXT,
  slug        TEXT,
  url         TEXT,
  description TEXT,
  icon        TEXT,
  is_active   BOOLEAN
) LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT a.id, a.name, a.slug, a.url, a.description, a.icon, a.is_active
  FROM public.apps a
  JOIN public.plan_apps pa ON a.id = pa.app_id
  JOIN public.profiles  p  ON p.plan_id = pa.plan_id
  WHERE p.id      = auth.uid()
    AND a.is_active = TRUE
    AND p.is_active = TRUE
  ORDER BY a.sort_order, a.name;
$$;

-- ─── check_app_access(slug) → reason string ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.check_app_access(app_slug TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_app_exists  BOOLEAN;
  v_app_active  BOOLEAN;
  v_user_active BOOLEAN;
  v_has_plan    BOOLEAN;
  v_can_access  BOOLEAN;
BEGIN
  -- Check app registry
  SELECT EXISTS(SELECT 1 FROM public.apps WHERE slug = app_slug)
  INTO v_app_exists;
  IF NOT v_app_exists THEN RETURN 'app_not_found'; END IF;

  SELECT is_active FROM public.apps WHERE slug = app_slug
  INTO v_app_active;
  IF NOT v_app_active THEN RETURN 'app_unavailable'; END IF;

  -- Check user profile
  SELECT is_active, (plan_id IS NOT NULL)
  FROM public.profiles WHERE id = auth.uid()
  INTO v_user_active, v_has_plan;

  IF NOT FOUND         THEN RETURN 'no_profile'; END IF;
  IF NOT v_user_active THEN RETURN 'user_inactive'; END IF;
  IF NOT v_has_plan    THEN RETURN 'no_plan'; END IF;

  -- Check plan → app linkage
  SELECT EXISTS(
    SELECT 1
    FROM public.plan_apps pa
    JOIN public.apps      a  ON a.id = pa.app_id
    JOIN public.profiles  p  ON p.plan_id = pa.plan_id
    WHERE p.id = auth.uid() AND a.slug = app_slug AND a.is_active = TRUE
  ) INTO v_can_access;

  IF NOT v_can_access THEN RETURN 'plan_denied'; END IF;

  RETURN 'ok';
END;
$$;

-- ─── log_audit(action, details, target_id, target_email) ─────────────────────
CREATE OR REPLACE FUNCTION public.log_audit(
  p_action             TEXT,
  p_details            JSONB  DEFAULT '{}',
  p_target_user_id     UUID   DEFAULT NULL,
  p_target_user_email  TEXT   DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_actor_email TEXT;
BEGIN
  SELECT email INTO v_actor_email
  FROM public.profiles WHERE id = auth.uid();

  INSERT INTO public.audit_log
    (actor_id, actor_email, target_user_id, target_user_email, action, details)
  VALUES
    (auth.uid(), v_actor_email, p_target_user_id, p_target_user_email, p_action, p_details);
END;
$$;

-- ─── admin_get_recent_audit(limit) ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_recent_audit(p_limit INT DEFAULT 100)
RETURNS TABLE (
  id                UUID,
  actor_email       TEXT,
  target_user_email TEXT,
  action            TEXT,
  details           JSONB,
  created_at        TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Access denied: admin role required';
  END IF;

  RETURN QUERY
    SELECT l.id, l.actor_email, l.target_user_email, l.action, l.details, l.created_at
    FROM public.audit_log l
    ORDER BY l.created_at DESC
    LIMIT p_limit;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- SEED DATA — Default plans
-- ═══════════════════════════════════════════════════════════════════════════════

INSERT INTO public.plans (name, description, sort_order, is_active)
VALUES
  ('Free',    'Limited access to selected free resources',       1, TRUE),
  ('Student', 'Full student access to all learning applications', 2, TRUE),
  ('Teacher', 'Complete access including teacher-only resources', 3, TRUE),
  ('Trial',   'Two-week trial with limited app access',           4, TRUE)
ON CONFLICT (name) DO NOTHING;

-- ═══════════════════════════════════════════════════════════════════════════════
-- PROMOTE YOUR FIRST ADMIN
-- ═══════════════════════════════════════════════════════════════════════════════
-- After signing up on index.html for the first time, run this query in the
-- Supabase SQL Editor, replacing the email address with your own:
--
--   UPDATE public.profiles
--   SET role = 'admin', is_active = TRUE
--   WHERE email = 'your@email.com';
--
-- You only need to do this ONCE for the first admin. All subsequent admins
-- can be promoted through the Admin Panel → Users tab.
-- ═══════════════════════════════════════════════════════════════════════════════
