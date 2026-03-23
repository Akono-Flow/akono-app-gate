// ─────────────────────────────────────────────────────────────────────────────
// config.js — Portal Configuration
//
// SETUP INSTRUCTIONS:
//   1. Replace SUPABASE_URL with your project URL
//      → Supabase Dashboard → Settings → API → Project URL
//   2. Replace SUPABASE_ANON_KEY with your anon/public key
//      → Supabase Dashboard → Settings → API → anon public
//   3. Replace AUTH_BASE_URL with the GitHub Pages URL of THIS auth repo
//      → e.g. https://yourusername.github.io/auth-repo
//      → If using a custom domain: https://portal.yourdomain.com
//   4. Customise PORTAL_CONFIG with your institution name and details
// ─────────────────────────────────────────────────────────────────────────────

// ── Supabase Connection ────────────────────────────────────────────────────────
const SUPABASE_URL      = 'https://YOUR_PROJECT_ID.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY_HERE';

// ── Auth Repo Base URL ─────────────────────────────────────────────────────────
// The URL where index.html, launcher.html, and no-access.html live.
// No trailing slash. Cross-repo apps use this to redirect to the login page.
const AUTH_BASE_URL = 'https://YOUR_GITHUB_USERNAME.github.io/YOUR_AUTH_REPO';

// ── Portal Branding ────────────────────────────────────────────────────────────
const PORTAL_CONFIG = {
  institutionName  : 'SCQ Learning Portal',   // Full name shown in headings
  institutionShort : 'SCQ',                    // Abbreviation shown in badges/nav
  tagline          : 'Science & Competition Excellence',
  supportEmail     : 'admin@yourdomain.com',
  logoInitials     : 'SCQ',                    // 2–4 letters for the circular emblem
  footerText       : 'SCQ Educational Technology Platform',
  // Theme override (optional — leave as-is for the default academic blue)
  accentColor      : '#2563eb',
};
