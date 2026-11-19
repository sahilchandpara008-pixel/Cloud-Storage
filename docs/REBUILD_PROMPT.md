# Flixvault — full rebuild prompt

Paste everything below the line into an AI coding agent to rebuild Flixvault
from scratch. It describes the product exactly as it runs today. No secrets
are included; you supply your own keys where marked `<…>`.

---

## 0. What to build

Build **Flixvault**, an Indian video-channel + cloud-storage app with:

1. A **Flutter Android app** (one codebase, three builds):
   - **Organic APK** (shared yourself, package `com.cloudstorage.app`)
   - **Ads APK** (shared from Meta ads, package `com.cloudstorage.app`, marks every install as a Meta-ads install)
   - **Google Play AAB** (package `com.flixvault.app`, with UPI plans via Google Play "alternative billing only")
2. A **Supabase backend** (Postgres + Auth + Storage + Edge Functions + pg_cron + pg_net). All business rules live in the database (RLS + `security definer` functions), so the app can never bypass them.
3. A **Next.js admin panel + public website** on Vercel (admin login, public download page, privacy/terms/delete-account/report-content pages).
4. **Bunny Stream** for video hosting (main video + preview/trailer), Supabase Storage for images and user cloud files.
5. **Meta tracking** by the server (Conversions API, app events), no Meta SDK in the app.
6. **UPI payments** straight to the owner's UPI ID, with automatic and manual verification.

Work rule: build stage by stage, write database tests for every rule, and never put a secret in the app or the repo.

---

## 1. Tech stack

- **App:** Flutter (Dart 3), Android only. Packages: `supabase_flutter`, `shared_preferences`, `video_player`, `chewie`, `cached_network_image`, `file_picker`, `url_launcher`, `uuid`, `intl`, `fc_native_video_thumbnail`, `package_info_plus`, `http`, `cross_file`, `play_install_referrer`, `tus_client_dart` (resumable Bunny uploads), `screen_brightness`, `volume_controller`.
- **Admin + website:** Next.js 15 (App Router, server actions), React 19, Tailwind CSS v4, `@supabase/ssr`, `@supabase/supabase-js`. Deployed on Vercel.
- **Backend:** Supabase (Postgres 17), pg_cron, pg_net, Edge Functions (Deno).
- **Video:** Bunny Stream (library per environment, TUS upload, signed playback URLs).
- **CI:** GitHub Actions — `mobile.yml` (builds the 3 Android outputs), `admin.yml` (typecheck/lint/build), `db-tests.yml` (runs all migrations + SQL tests on a throwaway Postgres), `supabase-deploy.yml`.

---

## 2. Brand

- Name **Flixvault**, tagline "Cloud & Channel".
- Colours: brand orange `#FF7A1A`, dark orange `#E25A00`, near-black backgrounds `#0B0B0D / #16161A / #1F1F25`. Red only for destructive actions and errors.
- Logo: orange cloud with a white up-arrow on a dark rounded square (1024×1024 for stores, favicon from the same file).

---

## 3. Users and audiences (the core rule)

Every install records **how the app was installed**; that decides what the user sees.

| Type | How detected | Sees |
|---|---|---|
| **Ads user** | Play install referrer / APK referrer contains a Meta source (see 3.1) | Ads-audience channels + content **as a guest without login**, plus premium previews |
| **Organic user** | Anything else (Play organic, organic APK, direct) | Organic + "all" content. Ads content only after **login + admin approval** |
| **Geo-blocked ads user** | Ads install whose **first** install request IP is in Gujarat or Maharashtra (new installs only) | Treated as organic, admin approval can't unlock ads content |
| **Admin / owner** | `admins` table | Everything |

Content and channels have an `audience` of `all | ads | organic`.
`can_see(audience)`: admin → true; `all` → true; `organic` → user is organic **or** geo-blocked; `ads` → `has_ads_access()`.
`has_ads_access()` = not geo-blocked **and** (source is ads **or** profile `ads_access_status = 'approved'`).

### 3.1 Install attribution
- On first launch the app reads the **Google Play Install Referrer** (`play_install_referrer`). APK builds have no Play referrer, so they use a build-time `--dart-define=APK_REFERRER=…` (ads APK: `utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download`; organic APK: empty → `direct`).
- App calls `record_install(install_id uuid, referrer_status 'ok'|'apk'|'not_available'|…, referrer, click_ts, install_ts)`. A random `install_id` is generated once and stored on the phone.
- `parse_source(status, referrer)`: `utm_source` in (meta, facebook, fb, instagram, ig, messenger, threads, audience_network) **or** the referrer contains `facebook.com` / `instagram.com` (Meta's own App-promotion referrer `utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=…`) → `meta`; `google-play` + `organic` → `organic`; empty → `direct`/`unknown`; anything else → `other`.
- `attribute_user(install_id)` links the install to the signed-in user: **first touch is immutable** (trigger `protect_first_touch`), except that a failed referrer read (`direct`) may be upgraded once when the same install later reads the referrer successfully (retry on next launch). Last touch always updates.
- `source_of(user)` = `ads` if first-touch source is `meta`, else `organic`.

### 3.2 Geo rule (hard-coded, server-side, no app update)
- Table `geo_blocked_ranges(start_ip inet, end_ip inet, state 'GJ'|'MH')` loaded from a GeoLite2 City snapshot (India rows for Gujarat + Maharashtra, adjacent ranges merged, IPv4 + IPv6), RLS on, no client access.
- `request_geo_state()` reads **Cloudflare `cf-connecting-ip`** from `request.headers` (clients can't set it; ignore `x-forwarded-for`), looks up the range, returns `GJ`/`MH`/null; bad/missing header → null (let through).
- `record_install` stores `geo_state` + `geo_blocked` **only on the first insert** of an install row. Older installs are never flagged; the flag is never recomputed.
- Attribution itself is not changed (reports and Meta still say "ads"). `my_status().source` returns `organic` for flagged users; `request_full_access()` does nothing for them.
- Also exclude Gujarat + Maharashtra in the Meta campaign locations.

### 3.3 Guests and login
- The app signs in **anonymously** on first launch (guest). Guests can browse, and ads users can watch previews.
- Login: email/password and Google, by **linking** the anonymous user (same user id, keeps attribution, plans and history).
- `profiles` row per user (`is_guest`, `display_name`, `avatar_url`, `ads_access_status none|pending|approved|rejected`, `used_bytes`, `free_cloud_bytes`).

---

## 4. App features (Flutter)

Bottom tabs; the app **always opens on Explore** (also when resumed).

- **Explore:** posts feed + search across posts and channels.
- **Channels:** list, search, join/follow; channel page shows name, avatar, follower count (`members_count = real joins + admin-set followers_offset`), posts. **No upload time and no folder icon/count shown.**
- **Post page:** title, description collapsed to ~8 words with **"see more"**, items (video/image), premium badge.
- **Player** (chewie/video_player):
  - swipe up/down on the **left = brightness**, **right = volume**; double-tap seek; **Next / Previous** across posts and channels (a play queue);
  - **preview-first:** for an **ads user without a plan** on a premium item with a trailer, play the trailer first (unlimited, no login). After **10 s** a **Skip** button: not subscribed → login (guests) → Plans; subscribed → full video.
  - Organic user on a premium item → login → Plans.
  - Plan holder → full video. Creator always sees own content.
- **Premium page:** active plans with price, days, perks; current plan + expiry; payment status banner; free-mode/Play variants (see 6).
- **Cloud:** logged-in users get **15 GB** free; folders, upload, download, delete.
- **Create channel / new post:** Premium feature; created channels and posts need **admin approval** before they are visible.
- **Profile / Settings:** name, avatar, payment history, policies, **Delete account** (Play requirement), report content.

---

## 5. Admin panel (Next.js) — `https://<domain>/login`

Dark sidebar with logo, grouped menu, red count badges, toast pop-ups for every result (green "Done" auto-closes in 5 s, red "That didn't work" stays), favicon, password show/hide eye on login.

- **Dashboard:** installs split ads vs organic (bar), users, revenue, pending work tiles.
- **Content → Channels:** create/edit channels, audience (all/ads/organic), avatar, **set follower count** (followers_offset).
- **Content → Posts / Upload:** **Single** and **Bulk** upload modes; each item has **main video, preview (trailer), thumbnail** pickers; free/premium; resumable upload to Bunny with encoding progress, success message, thumbnail auto-generated if missing, "Try again" on failure.
- **Approvals:** user-created channels/posts approve/reject.
- **Requests:** organic users asking for ads-content access → approve/reject (`set_ads_access`).
- **People → Users** (source ads/organic, plan, guest/registered), **Admins** (owner vs content admin; content admins can be limited to channels).
- **Revenue → Payments:** tabs Orders / Plan summary / Customers & repeat buyers; status filters (All, Pending, Success, Failed, Cancelled, Revoked); filters plan, sort, date range; stat tiles; table (order + date, user + source badge + repeat badge, amount + plan, status, UTR/UPI answer, action). **Mark as paid…** (bank UTR + amount) and **Revoke…** (reason). UPI settings (UPI ID, payee name, accept payments on/off) and Google Play reporting card side by side.
- **Revenue → Plans:** one compact row per plan (name, price ₹, days, order, show in app, save, perks under "Edit perks"); **Free mode** switch (hides all plans and payments in every app version).
- **Meta Pixel:** Pixel/dataset ID + Conversions API token (stored server-side only), on/off, recent events + match health.
- **Settings.**
- Public pages: `/home`, `/d` (download page with ads/organic APK buttons, records ad clicks via `/api/click`), `/privacy`, `/terms`, `/delete-account`, `/report-content`.

---

## 6. Payments (UPI, no gateway)

Plans (example): Trial ₹49/3 days, Silver ₹129/7, Gold ₹259/30, Platinum ₹599/180, Diamond ₹999/365.

1. **`create_payment_order(plan_id)`** (user must be signed in; guests allowed): payments enabled? plan active? Reuse the user's open order for the same plan at the same price within 24 h, cancel the user's other open orders, else create one with reference `CS<YYMMDD><12 hex>` and `amount_paise`. Return order id, reference, amount, plan name, **UPI ID and payee from `payment_settings`** (never hard-coded in the app).
2. App opens the UPI intent `upi://pay?pa=<upi_id>&pn=<payee>&tr=<reference>&tn=…&am=<amount>&cu=INR`; money goes straight to the owner's bank.
3. App sends the raw UPI answer to **`report_payment_result(order_id, raw)`**:
   - **SUCCESS** + reference matches + valid unused transaction id (6–40 A-Z0-9) + order < 2 h old → **auto-approve** (`activate_payment`, source `upi_app`);
   - SUCCESS failing a check, NO_RESPONSE, SUBMITTED → **pending** with a reason;
   - FAILURE → **failed**.
4. **`activate_payment`** (idempotent): amount must equal the order, UTR unique across orders; plans **stack** (new expiry = max(now, current expiry) + days); insert `subscriptions`; log `payment_events`.
5. Admin **`admin_mark_payment_paid(order, utr, amount)`** (source `admin`) and **`admin_revoke_payment(order, reason)`** (ends the subscription).
6. pg_cron `cancel-stale-payment-orders` every 30 min: open orders older than 24 h → cancelled.
7. App keeps the open order locally to resume it; payment status + history screens.
8. **Google Play build:** shows Google's alternative-billing info screen before the UPI flow, and every approved Play-version payment is **reported to Google within 24 h** by an edge function (`play-report`, pg_cron every 5 min) using a Google service account (secret `GOOGLE_SERVICE_ACCOUNT_JSON`). APK payments are never reported.
9. **Free mode** (`app_mode.free_mode`): no plans/payments anywhere; logged-in ads users get full access; organic users ask for access.
10. Note in the UI: a UPI "SUCCESS" comes from the customer's phone and can be forged — owner reconciles with the bank and revokes if missing.

---

## 7. Meta tracking (server-side Conversions API, app events)

- Meta for Developers app (Business type, Android platform: package `com.flixvault.app`, class `<MainActivity>`, key hash from the Play **app signing** SHA-1 → base64, privacy/terms/data-deletion URLs, category Entertainment, Live mode), linked to the Business portfolio and ad account; the Pixel/dataset is **linked to the app** in Events Manager.
- `meta_settings` (pixel_id, access_token, action_source `app`, app_package `com.flixvault.app`, enabled), owner-only RLS; the token never reaches the app.
- Triggers enqueue `meta_events`, pg_cron `meta-dispatch` every minute posts them with pg_net to `https://graph.facebook.com/v21.0/<pixel>/events`:
  - `AppInstall` (first launch), `CompleteRegistration` (guest → account), `ViewContent` (video/trailer opened), `InitiateCheckout` (order created, value = plan price), `Purchase` + `Subscribe` (after approval, value = amount, INR, `event_id` = order id so Meta dedupes).
- `user_data`: SHA-256 external_id (user or install id), SHA-256 email, country `in`, client IP + user agent, fbc/fbp from ad clicks. `app_data`: `advertiser_tracking_enabled`, `application_tracking_enabled`, `extinfo` (`a2`, package, …).
- Never send fake events. App-promotion campaign: start with **Maximise number of app installs**; switch to Purchase after real purchases.

---

## 8. Database (Supabase) — tables

`profiles, admins, admin_channel_access, channels, channel_members, channel_folders, posts, post_items, plans, subscriptions, plan_requests, payment_settings, payment_orders, payment_events, play_settings, app_mode, installs, user_attribution, ad_clicks, analytics_events, meta_settings, meta_events, geo_blocked_ranges, cloud_files, consents, reports, support_requests, audit_logs, bunny_sync_settings`

Rules:
- RLS on every table; app users only read what `can_see` allows and only their own private rows; writes go through `security definer` RPCs with `set search_path = ''`.
- Storage buckets: media (images), cloud (per-user folder), avatars; private, signed URLs.
- Bunny: edge functions `bunny-stream-create`, `bunny-stream-status`, `bunny-stream-url` (signed, checks `can_read_media` / trailer rules), `bunny-stream-delete`, `bunny-stream-sync` (pg_cron every minute marks encoded videos ready, auto thumbnail).
- Other edge functions: `cloud-upload`, `cloud-download-url`, `cloud-delete`, `delete-account`, `upi-webhook`, `play-report`.
- Posts become visible by **server time** (publish time set by the server, never the phone clock).

---

## 9. Android builds (CI)

- Flavors: `direct` (package `com.cloudstorage.app`, no Google code, UPI only) and `play` (package `com.flixvault.app`).
- Outputs:
  - **Organic APK:** `flutter build apk --release --flavor direct`
  - **Ads APK:** `flutter build apk --release --flavor direct --dart-define=APK_REFERRER="utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download"`
  - **Play AAB:** `flutter build appbundle --release --flavor play --dart-define=PLAY_STORE=true --dart-define=PLAY_SELLS_UPI=true`
- Signing keys only from CI secrets; Play App Signing on. Version `x.y.z+build` bumped every release. Play release notes never mention plans/subscriptions.
- Play Console: Data safety (account info, app activity, purchase history; no advertising ID unless the Meta SDK is added), content rating, target audience 18+, alternative billing enrolment for India, Open testing → Production.

---

## 10. Acceptance checklist

- [ ] Fresh install via Meta ad link (`referrer=utm_source%3Dapps.facebook.com%26utm_campaign%3Dfb4a`) → server shows source `meta`, guest sees ads channels and plays previews.
- [ ] Play organic install → organic; ads content hidden until login + approval.
- [ ] New install from a Gujarat/Maharashtra IP → flagged, organic-only, approval does not unlock ads.
- [ ] UPI success → auto-approved, plan active, Purchase + Subscribe reach Meta once.
- [ ] Pending payment → Mark as paid with bank UTR → plan active; Revoke → plan removed.
- [ ] Changing the UPI ID in admin → next order uses it, no app update.
- [ ] Free mode hides all plans in every build.
- [ ] Admin upload (single + bulk, main/preview/thumbnail) appears in the app for the right audience after encoding.
- [ ] All SQL tests, admin typecheck/lint/build and Android CI green.
