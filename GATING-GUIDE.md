# How to Gate an Existing App
## SCQ Learning Portal — Developer Reference Guide

> Keep this file. You can follow it top-to-bottom any time you want to add a
> new app to the portal, even months after the initial setup.

---

## Quick-Start Checklist

Run through this list for every app you gate. Details for each step are in the
sections below.

- [ ] 1. Add the three auth files to the app's repo
- [ ] 2. Add the CDN script + three `<script>` tags to the app's `<head>`
- [ ] 3. Add the loading overlay as the first element inside `<body>`
- [ ] 4. Wrap the app's init call with `requireAppAccess()`
- [ ] 5. Register the app in the Admin Panel → Applications tab
- [ ] 6. Assign the app to one or more plans in the Admin Panel → Plans tab
- [ ] 7. Add the app's domain to Supabase → Auth → URL Configuration
- [ ] 8. Push all changes and run through the test cases

---

## Before You Start — One-Time Setup

These steps are done **once** when you first set up the portal. If you already
did them, skip to [Step 1](#step-1--copy-the-three-auth-files).

### Supabase Project
1. Create a project at [supabase.com](https://supabase.com).
2. Go to **SQL Editor → New Query**, paste the entire contents of
   `supabase/schema.sql`, and click **Run**.
3. Note your **Project URL** and **anon/public key** from
   Settings → API.

### Auth Repo Setup
1. Clone or create your auth repo (this is where `index.html`, `admin.html`,
   `launcher.html`, `no-access.html`, and `js/` live).
2. Edit `js/config.js` and fill in:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
   - `AUTH_BASE_URL` (the GitHub Pages URL of this auth repo)
   - `PORTAL_CONFIG` (your institution name, etc.)
3. Push to GitHub and enable GitHub Pages (Settings → Pages → Deploy from
   branch `main`, folder `/root`).
4. In Supabase → Authentication → URL Configuration, add your auth repo URL
   to **Site URL** and the following to **Redirect URLs**:
   ```
   https://YOUR_AUTH_REPO_URL/**
   ```

### First Admin Account
1. Open your live `index.html` and sign up using your own email.
2. In Supabase → SQL Editor, run:
   ```sql
   UPDATE public.profiles
   SET role = 'admin', is_active = TRUE
   WHERE email = 'your@email.com';
   ```
3. Sign in — you will land on `admin.html`.

---

## Step 1 — Copy the Three Auth Files

Every app repo that participates in the gating system needs these three files.
They are **identical** across every repo — copy them without changing anything.

```
your-app-repo/
├── js/
│   ├── config.js      ← copy from auth repo (same Supabase keys)
│   └── auth.js        ← copy from auth repo (same file, no changes)
└── no-access.html     ← copy from auth repo root
```

**Important:** `config.js` and `auth.js` point to the same Supabase project,
so they literally are the same files. If you ever update `auth.js` in the auth
repo, you must copy the new version to every app repo as well. See
[Keeping auth.js in sync](#keeping-authjs-in-sync) below for a better strategy.

---

## Step 2 — Add Scripts to the App's HTML `<head>`

Open your app's main HTML file (e.g. `index.html`, `app.html`, `mcq.html`).

Inside `<head>`, **before** your own scripts, add these four lines:

```html
<!-- SCQ Auth System — add these in this order -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
<script src="js/config.js"></script>
<script src="js/auth.js"></script>
```

> **Cross-repo tip:** If the app lives in a different repo from the auth repo,
> the paths above assume `js/config.js` and `js/auth.js` are in the app repo
> itself. Alternatively, load them from a fixed CDN URL:
> ```html
> <script src="https://raw.githack.com/YOURUSERNAME/AUTH_REPO/main/js/auth.js"></script>
> ```

---

## Step 3 — Add the Loading Overlay

Inside `<body>`, as the **very first element** (before everything else), add:

```html
<div id="page-loader" style="
  position:fixed;inset:0;background:#050911;
  display:flex;align-items:center;justify-content:center;
  z-index:9999;font-family:monospace;color:#2563eb;font-size:1.1rem;
  flex-direction:column;gap:12px;
">
  <span style="font-size:2rem">🔒</span>
  Verifying access…
</div>
```

This overlay covers the entire page while the auth check runs. The user never
sees a flash of the app's content before the redirect happens.

---

## Step 4 — Wrap the App's Init Call

Find the line that **starts your app**. It is usually one of these patterns:

```js
// Pattern A — DOMContentLoaded listener
document.addEventListener('DOMContentLoaded', init);

// Pattern B — direct call at the bottom of a script
init();

// Pattern C — window.onload
window.onload = init;
```

Replace that line (and only that line) with the following wrapper. Everything
else in your app stays **exactly the same**.

```js
document.addEventListener('DOMContentLoaded', async () => {

  // ── Replace 'YOUR_SLUG_HERE' with the slug you register in Step 5 ──
  const auth = await requireAppAccess('YOUR_SLUG_HERE', 'no-access.html');
  if (!auth) return;   // auth handles the redirect; just stop here

  // Remove the loading overlay
  const loader = document.getElementById('page-loader');
  if (loader) loader.remove();

  // Call your original init function — completely unchanged
  await init();   // ← replace init() with your actual function name

});
```

### What if my app has no init function?

If your app runs its code directly at the bottom of a `<script>` block instead
of inside a named function, wrap the whole block like this:

```js
document.addEventListener('DOMContentLoaded', async () => {
  const auth = await requireAppAccess('YOUR_SLUG_HERE', 'no-access.html');
  if (!auth) return;
  document.getElementById('page-loader').remove();

  // ── All of your original code goes here ──
  // (paste it in directly, no function needed)

});
```

### What if my app already has a DOMContentLoaded listener?

If you already have:
```js
document.addEventListener('DOMContentLoaded', function() {
  // ... app code
});
```

Just make it async and add the three lines at the top:

```js
document.addEventListener('DOMContentLoaded', async function() {
  const auth = await requireAppAccess('YOUR_SLUG_HERE', 'no-access.html');
  if (!auth) return;
  document.getElementById('page-loader').remove();

  // ... rest of your existing code, unchanged
});
```

---

## Step 5 — Register the App in the Admin Panel

1. Open your portal and sign in as admin.
2. Go to **Applications** in the sidebar.
3. Click **+ Register App**.
4. Fill in:
   - **App Name** — human readable, e.g. `Chemistry MCQ`
   - **Slug** — short identifier, **must match** what you put in Step 4.
     Rules: lowercase only, letters/numbers/hyphens, no spaces.
     Examples: `mcq`, `uvvis`, `chemistry-mcq`, `electrolysis-lab`
   - **App URL** — the full URL to the app's HTML file (used for the launcher
     card). Example: `https://yourusername.github.io/mcq-repo/app.html`
   - **Description** — one sentence shown on the launcher card.
   - **Icon** — a single emoji shown on the launcher card (e.g. `⚗️`).
5. Leave **App is active** checked.
6. Click **Save App**.

> **Slug is the critical field.** The slug you type here must exactly match
> the first argument you pass to `requireAppAccess()` in the app's code.
> Capitalisation matters: `mcq` ≠ `MCQ`.

---

## Step 6 — Assign the App to Plans

Registering an app does not give any user access to it yet. You must assign it
to at least one plan.

1. In the Admin Panel, go to **Plans**.
2. Find the plan(s) that should include this app (e.g. Student, Teacher).
3. Click **🗂 Manage Apps** on a plan card.
4. Tick the checkbox next to your new app.
5. Click **Save Changes**.
6. Repeat for each plan that should include the app.

All users already on those plans now have access immediately — no need to touch
their individual accounts.

---

## Step 7 — Add the Domain to Supabase Redirect URLs

If the app repo is on a **different domain or subdomain** from the auth repo,
you must tell Supabase to allow redirects back to it.

1. Go to Supabase → **Authentication** → **URL Configuration**.
2. Under **Redirect URLs**, click **Add URL** and add:
   ```
   https://yourusername.github.io/your-app-repo/**
   ```
   The `**` wildcard covers all pages in that repo.
3. Save.

If the app is in the **same repo** as the auth system (same domain), you
already added `https://yourusername.github.io/your-auth-repo/**` and no
further action is needed.

---

## Step 8 — Test the Integration

Run every one of these tests before considering an integration complete.

| Test | Expected Result |
|------|----------------|
| Visit the app URL while **not logged in** | Redirect to `index.html` on auth repo |
| Log in with an account that has **no plan** | Redirect to `no-access.html` with "No Plan" message |
| Log in with an account on a plan that **does not include** this app | Redirect to `no-access.html` with "Plan denied" message |
| Log in with an account on a plan that **does include** this app | App loads normally |
| Log in from a **second device** with the same account | First device gets ejected on next page load |
| Admin **disables the app** in the panel | Active users see "App unavailable" on next page load |
| Admin **deactivates a user** | User is blocked on next page load |
| Admin **revokes session** | User must re-login; no other devices can use old session |
| User clicks **Sign Out** anywhere in the app | Redirect to `index.html` |

---

## Adding a Sign-Out Button to Your App

Any page that has `auth.js` loaded can use the global `scqLogout()` function:

```html
<!-- Simple button -->
<button onclick="scqLogout()">Sign Out</button>

<!-- As a link -->
<a href="#" onclick="scqLogout(); return false;">Sign Out</a>
```

---

## Adding a "Back to Portal" / Nav Link

```html
<a href="https://YOUR_AUTH_REPO_URL/launcher.html">← My Apps</a>
```

Or using the config variable in a script block:

```js
const backUrl = AUTH_BASE_URL + '/launcher.html';
document.getElementById('back-link').href = backUrl;
```

---

## Keeping auth.js in Sync

Every app repo holds a copy of `auth.js`. When you update it (e.g. to fix a
bug), you must copy it to every repo. To avoid this, you can load `auth.js`
from a stable URL instead:

```html
<!-- In every app's <head>, instead of a local file: -->
<script src="https://raw.githack.com/YOURUSERNAME/AUTH_REPO_NAME/main/js/auth.js"></script>
```

`raw.githack.com` serves raw GitHub files with proper caching headers.
Updating `auth.js` in your auth repo then automatically updates all apps.
Use this approach once you have more than 3–4 gated apps.

---

## Multi-Repo Tracking Table

Copy this table and update it as you integrate each app.

| App Name | Slug | Repo | config.js | auth.js | no-access.html | Registered | Plans |
|----------|------|------|-----------|---------|----------------|------------|-------|
| — | — | — | — | — | — | — | — |

---

## Common Problems and Fixes

**App loads before auth check completes (flash of content)**
: The loading overlay was not added as the first element in `<body>`, or it was
  styled with `display:none`. Confirm it uses `position:fixed` and `z-index:9999`.

**User is redirected to login even though they are signed in**
: Check that `AUTH_BASE_URL` in `config.js` is set correctly and has no
  trailing slash. Also confirm the app domain is in Supabase's Redirect URLs list.

**"App not found" shown instead of the app**
: The slug in `requireAppAccess('your-slug', ...)` does not match what is
  registered in the Admin Panel → Applications tab. They must be identical,
  including case.

**User on the correct plan still sees "Plan denied"**
: The app is not linked to that plan. Go to Plans → Manage Apps → tick the app
  → Save Changes.

**User logs in on Device B and Device A gets kicked out**
: This is the intended single-device enforcement behaviour. Device A will see a
  "session conflict" message and be redirected to login. To allow a specific
  user to use multiple devices, you can revoke their session in the admin panel
  so neither device is locked in, then they can log in fresh on the device they
  want to use.

**Session conflict after admin revokes session**
: After revocation, the user's `device_token` in Supabase is cleared. When they
  next load any page that calls `requireAuth()` or `requireAppAccess()`, they
  are redirected to login because the local token no longer matches. This is
  correct. They simply sign in again.

---

*SCQ Learning Portal — Developer Guide*  
*Last updated: March 2026*
