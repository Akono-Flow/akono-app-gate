// ─────────────────────────────────────────────────────────────────────────────
// auth.js — SCQ Auth System v3.0
//
// Exposes:
//   requireAuth()                          → use on launcher.html, admin.html
//   requireAppAccess(slug, noAccessPage)   → use on every gated app page
//   scqLogout()                            → sign-out button handler
//   getMyApps()                            → fetch apps for current user
//   _scqSupabase                           → raw Supabase client (advanced use)
//
// Depends on: supabase-js v2 (CDN), config.js  (must both load before this)
//
// v3.0 changes: Removed single-device enforcement. Any number of concurrent
// sessions per account are now permitted.
// ─────────────────────────────────────────────────────────────────────────────

(function (global) {
  'use strict';

  // ── Dependency guard ───────────────────────────────────────────────────────
  if (typeof supabase === 'undefined') {
    console.error('[SCQ] supabase-js not loaded. Add CDN script before auth.js.');
    return;
  }
  if (typeof SUPABASE_URL === 'undefined' || typeof SUPABASE_ANON_KEY === 'undefined') {
    console.error('[SCQ] config.js not loaded. Add it before auth.js.');
    return;
  }

  // ── Supabase client ────────────────────────────────────────────────────────
  var _sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      autoRefreshToken: true,
      persistSession:   true,
      storageKey:       'scq_sb_session',
      detectSessionInUrl: true,
    }
  });

  global._scqSupabase = _sb;

  // ── URL helpers ───────────────────────────────────────────────────────────
  function _base() {
    return (typeof AUTH_BASE_URL !== 'undefined')
      ? AUTH_BASE_URL.replace(/\/$/, '')
      : '';
  }

  function _authUrl(page) {
    var b = _base();
    return b ? (b + '/' + page) : page;
  }

  function _goLogin(reason) {
    var url = _authUrl('index.html');
    if (reason) url += '?reason=' + encodeURIComponent(reason);
    window.location.href = url;
  }

  function _goNoAccess(reason, override) {
    var page = override || _authUrl('no-access.html');
    if (reason) page += '?reason=' + encodeURIComponent(reason);
    window.location.href = page;
  }

  // ── getSession ─────────────────────────────────────────────────────────────
  async function _getSession() {
    try {
      var r = await _sb.auth.getSession();
      return (r && r.data && r.data.session) ? r.data.session : null;
    } catch (_) { return null; }
  }

  // ── getProfile ─────────────────────────────────────────────────────────────
  async function _getProfile(uid) {
    try {
      var r = await _sb.from('profiles')
        .select('id, email, full_name, role, is_active, plan_id')
        .eq('id', uid)
        .single();
      return (r && r.data) ? r.data : null;
    } catch (_) { return null; }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════════════════════════

  /**
   * requireAuth()
   *
   * Use on pages that need a logged-in + active user but don't gate a specific
   * app (e.g. launcher.html, admin.html).
   *
   * Checks:  session exists → profile exists → is_active
   * Returns: { session, profile }  if all pass
   *          null                  (and redirects) if any check fails
   */
  global.requireAuth = async function () {
    var session = await _getSession();
    if (!session) { _goLogin('not_logged_in'); return null; }

    var profile = await _getProfile(session.user.id);
    if (!profile) { _goLogin('no_profile'); return null; }

    if (!profile.is_active) {
      try { await _sb.auth.signOut(); } catch (_) {}
      _goLogin('inactive');
      return null;
    }

    return { session: session, profile: profile };
  };

  /**
   * requireAppAccess(slug, noAccessPageOverride)
   *
   * Use as the FIRST CALL inside DOMContentLoaded on every gated app page.
   *
   * @param {string} slug                 App slug matching admin registry (e.g. 'mcq')
   * @param {string} [noAccessPageOverride]  Local path to no-access.html for cross-repo apps
   *
   * Checks:  session → profile → is_active → plan includes slug → app is_active
   * Returns: { session, profile } or null (and redirects)
   *
   * Usage:
   *   document.addEventListener('DOMContentLoaded', async () => {
   *     const auth = await requireAppAccess('my-app-slug', 'no-access.html');
   *     if (!auth) return;
   *     document.getElementById('page-loader').remove();
   *     init(); // your existing init
   *   });
   */
  global.requireAppAccess = async function (slug, noAccessPageOverride) {
    var session = await _getSession();
    if (!session) { _goLogin('not_logged_in'); return null; }

    var profile = await _getProfile(session.user.id);
    if (!profile) { _goLogin('no_profile'); return null; }

    if (!profile.is_active) {
      try { await _sb.auth.signOut(); } catch (_) {}
      _goLogin('inactive');
      return null;
    }

    // App-level access check
    var reason = 'plan_denied';
    try {
      var r = await _sb.rpc('check_app_access', { app_slug: slug });
      var result = (r && r.data) ? r.data : 'plan_denied';
      if (result === 'ok') {
        return { session: session, profile: profile };
      }
      reason = result;
    } catch (_) {
      reason = 'plan_denied';
    }

    _goNoAccess(reason, noAccessPageOverride || null);
    return null;
  };

  /**
   * scqLogout()
   *
   * Sign out the current user and redirect to login.
   * Attach to any logout button: onclick="scqLogout()"
   */
  global.scqLogout = async function () {
    try { await _sb.auth.signOut(); } catch (_) {}
    _goLogin('logged_out');
  };

  /**
   * getMyApps()
   *
   * Returns the array of app objects the current user's plan grants access to.
   * Used by launcher.html to render the app grid.
   * @returns {Array<{id, name, slug, url, description, icon, is_active}>}
   */
  global.getMyApps = async function () {
    try {
      var r = await _sb.rpc('get_my_apps');
      return (r && r.data) ? r.data : [];
    } catch (_) { return []; }
  };

})(window);
