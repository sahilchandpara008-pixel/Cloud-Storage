# Flixvault — complete app-building prompt

Copy everything below the line into an AI coding agent (one message). It
describes Flixvault exactly as it runs today: app, admin panel, website,
database, payments, ads/organic/guest users, Meta tracking, Google Play,
APK/AAB builds. No secrets are included — supply your own where marked `<…>`.

---

# BUILD "FLIXVAULT" FROM SCRATCH

You are building **Flixvault — Cloud & Channel**, an Indian video-channel and
personal cloud-storage product. Build it stage by stage (section 14). After
each stage: run the tests, show me what works, then continue. Rules for the
whole project:

- All business rules live in the **database** (Postgres Row Level Security +
  `security definer` functions with `set search_path = ''`). The app and the
  admin panel can never bypass them.
- **Never** put a secret (service-role key, Meta token, Bunny key, Google
  service account, signing keys) in the app, the website code or the repo.
  Secrets live in Supabase secrets, Vercel env vars or GitHub Actions secrets.
- Every database rule gets a SQL test. Every stage keeps all tests green.
- Server time decides everything time-based (never the phone clock).
- Plain, friendly English in every message the user sees.

## 1. Product summary

Three parts:

1. **Android app (Flutter)**, one codebase, three builds:
   - **Organic APK** — package `com.cloudstorage.app`, shared by you directly.
   - **Ads APK** — same package, shared from Meta ads; every install from it counts as a Meta-ads install.
   - **Google Play AAB** — package `com.flixvault.app`, sells the same UPI plans under Google Play "alternative billing only" (India).
2. **Supabase backend**: Postgres 17, Auth (anonymous + email + Google), Storage, Edge Functions (Deno), pg_cron, pg_net.
3. **Next.js admin panel + public website** on Vercel: admin login, download page, privacy/terms/delete-account/report-content pages.

Plus: **Bunny Stream** for videos (main + preview/trailer), **UPI** payments
straight to the owner's UPI ID, **Meta Conversions API** app events sent by
the server, and **Google Play** alternative-billing reporting.

## 2. Tech stack (use these exactly)

**App (Flutter, Android only):** `supabase_flutter ^2.18`, `shared_preferences`,
`video_player`, `chewie`, `cached_network_image`, `file_picker`, `url_launcher`,
`uuid`, `intl`, `fc_native_video_thumbnail`, `package_info_plus`, `http`,
`cross_file`, `play_install_referrer`, `tus_client_dart` (resumable Bunny upload),
`screen_brightness`, `volume_controller`.

**Admin + website:** Next.js 15 (App Router, server components, server actions),
React 19, Tailwind CSS v4 (`@theme` tokens), `@supabase/ssr`, `@supabase/supabase-js`.
Middleware protects every route except the public list
`/home, /site, /d, /api/click, /privacy, /terms, /delete-account, /report-content`.

**Backend:** Supabase Postgres + pg_cron + pg_net, Edge Functions in Deno.

**CI (GitHub Actions):**
- `mobile.yml` — builds organic APK, ads APK, Play AAB; uploads artifacts.
- `admin.yml` — `tsc --noEmit`, `next lint`, `next build`.
- `db-tests.yml` — starts a throwaway Postgres, applies every migration in order, runs `supabase/tests/rls_test.sql` (all tests must print `ok`).
- `supabase-deploy.yml` — pushes migrations and edge functions (needs project secrets).

## 3. Brand and design

- Name **Flixvault**, store title "Flixvault: Cloud & Channel".
- Colours: brand `#FF7A1A` (500), `#E25A00` (600), `#B84A00` (700, buttons/links on white); dark surfaces `#0B0B0D`, `#16161A`, `#1F1F25`, `#2A2A31`. Red only for destructive actions and errors. Green for success.
- Logo: orange cloud with a white up-arrow on a dark rounded square; export 1024×1024 (stores, Meta), 512 (Play), favicon.
- App: dark theme, orange gradient accents, rounded cards, skeleton loaders, counts formatted like 1.2K / 3.4M.
- Admin: light content area (`gray-50`), dark sidebar (`ink-900`) with the logo, orange active item with a left bar, compact items, red count badges, `max-w-6xl` content, toast pop-ups, keyboard focus rings, reduced-motion support, works at phone width with no sideways scroll.

## 4. Users, audiences and access (the core rule)

### 4.1 User types

| Type | Detected by | What they see |
|---|---|---|
| **Guest** | Anonymous Supabase session created on first launch | Can browse; actions that need an account ask to log in |
| **Ads user** | First install came from a Meta ad / ads APK (4.2) | Ads-audience channels and content **as a guest, no login**; premium **previews** without login or plan |
| **Organic user** | Any other install (Play search, organic APK, direct) | Organic + "all" content; ads content only after **login + admin approval** |
| **Geo-blocked ads user** | Ads install whose first install request comes from Gujarat or Maharashtra (4.4) | Treated as organic; approval cannot unlock ads content |
| **Premium user** | Active subscription | Full premium videos, can create a channel |
| **Admin** | Row in `admins` (`owner` or `content_admin`) | Admin panel; content admins can be limited to channels |

Every channel and post has `audience` = `all | ads | organic`.

```
can_see(aud) = is_admin() or case aud
   when 'all'     then true
   when 'organic' then user_source() = 'organic' or geo_blocked()
   when 'ads'     then has_ads_access() end
has_ads_access() = not geo_blocked() and
   (source_of(auth.uid()) = 'ads' or profile.ads_access_status = 'approved')
```

### 4.2 Install attribution

- First launch: create a random `install_id` (uuid), keep it on the phone forever.
- Read the referrer:
  - Play build: **Google Play Install Referrer** (`play_install_referrer`), status `ok` or an error status; on error retry on the next launches.
  - APK builds: no Play referrer, use the build-time `--dart-define=APK_REFERRER=…` with status `apk` (organic APK: empty, status `not_available`).
- Call `record_install(install_id, referrer_status, referrer, click_ts, install_ts)`:
  - stores the row in `installs` (utm fields parsed with `referrer_param`, client IP + user agent from request headers);
  - matches a recent download-page ad click (`install_match_click`) to copy `fbc/fbp`;
  - a later successful referrer read may upgrade a failed one (`not_available/error` → `ok/apk`), never the other way;
  - then calls `attribute_user`; returns the source.
- `parse_source(status, referrer)`:
  - `utm_source` in (meta, facebook, fb, instagram, ig, messenger, threads, audience_network) **or** referrer contains `facebook.com` / `instagram.com` (Meta App-promotion referrer `utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content={…}`; also URL-encoded) → `meta`
  - `utm_source=google-play` and `utm_medium=organic` → `organic`
  - empty referrer → `direct` (status not_available/apk) else `unknown`
  - any other utm_source → `other`
- `attribute_user(install_id)` (after sign-in and on every launch): links the install to `auth.uid()` in `user_attribution`; **first touch is immutable** (trigger `protect_first_touch`), except a first touch of `direct` may be upgraded once by a successful retried referrer read of the same install. Last touch always updates.
- `source_of(user)` = `ads` if first-touch source = `ad_source()` ('meta') else `organic`.

### 4.3 Guests and login

- On first launch sign in **anonymously** (guest profile created by trigger `handle_new_user`).
- Login screen: email + password (sign up / sign in) and Google. Logging in **links** the anonymous user (same user id), so attribution, plans, uploads and history stay. Trigger `handle_user_upgraded` sets `is_guest = false` and fires the CompleteRegistration event.
- `profiles(id, display_name, avatar_url, is_guest, quota_bytes, used_bytes, status, ads_access_status none|pending|approved|rejected, ads_access_decided_by/at, free_cloud_bytes, created_at, updated_at)`.

### 4.4 Gujarat / Maharashtra rule (hard-coded, server only)

- Table `geo_blocked_ranges(start_ip inet, end_ip inet, state 'GJ'|'MH')`, btree index on `start_ip`, RLS on, no client grants. Load from a GeoLite2 City snapshot: India rows whose state is Gujarat or Maharashtra, IPv4 + IPv6, adjacent ranges merged (~5,200 rows).
- `request_geo_state()`: read **`cf-connecting-ip`** from `current_setting('request.headers')` (Cloudflare sets it; clients cannot); never use `x-forwarded-for`. Find the range with the largest `start_ip <= ip` and check `end_ip >= ip` and same family. Bad/missing header → null (let through).
- `record_install` sets `installs.geo_state` and `geo_blocked` **only when the row is first inserted**. Existing installs are never flagged, and the flag is never recomputed.
- `geo_blocked()` = current user's first-touch install is flagged.
- Attribution is not changed (reports and Meta still count them as ads). `my_status().source` returns `organic` for them; `request_full_access()` does nothing for them; admin approval does not unlock ads content.
- Also exclude Gujarat and Maharashtra in the Meta ad campaign locations.

## 5. The Flutter app

### 5.1 Structure
- `lib/main.dart`, `lib/state/app_state.dart` (status, source, has_ads_access, premium, free mode, guest), `lib/services/backend.dart` (all RPC calls), `lib/services/payments.dart`, `lib/services/play_queue.dart`, `lib/widgets/gates.dart` (all access decisions in one place), `lib/widgets/player_controls.dart`, `lib/widgets/expandable_caption.dart`, `lib/widgets/common.dart`.
- Screens: home_shell, explore, feed, channels, channel, post, player, premium, payment_status, payment_history, cloud, create_channel, new_post, login, profile, settings, policy.
- Build-time flags: `PLAY_STORE` (Play build), `PLAY_SELLS_UPI` (Play build sells UPI plans), `APK_REFERRER` (APK attribution).

### 5.2 Start-up
1. Supabase init → anonymous session if none.
2. Record install (once) + attribute user (every launch, retries referrer if it failed).
3. Load `my_status()`: user_id, display_name, avatar_url, is_guest, source, has_ads_access, is_premium, plan_name, plan_ends_at, used_bytes, quota_bytes, open_request, free_mode, access_status.
4. Policy consent screen on first launch (stores `consents`).
5. Open the **Explore** tab — always, also when the app comes back from background.

### 5.3 Tabs and screens
- **Explore**: `explore(tab, limit, offset, search)` — tabbed lists, search box (posts + channels), infinite scroll, skeletons.
- **Feed**: `feed(before, limit)` — posts from joined channels.
- **Channels**: list + search; join/leave (`channel_members`). Channel page: icon, name, handle, description (collapsed), follower count = real joins + `followers_offset`, Join button, posts via `channel_posts(channel, before, limit)`. **Do not show upload time, folder icons or folder counts.**
- **Post page**: title, caption collapsed to ~8 words with **"see more"**, items (video/image) with premium badge, share, report (`report_content_in_app`).
- **Player** (chewie/video_player, landscape support):
  - vertical swipe on the **left half = brightness**, **right half = volume**, with an overlay indicator;
  - double-tap left/right = seek −10 s / +10 s;
  - **Next / Previous** buttons through a play queue that crosses posts and channels;
  - Back returns to the screen where viewing started (players replace each other).
- **Access gates (`gates.dart`)**:
  - `canWatchFull` = creator of the post **or** item not premium **or** user is premium.
  - `canWatchTrailer` = item has a trailer **and** not canWatchFull **and** `hasAdsAccess`.
  - Tap a premium item as an **ads user without plan** → play the **trailer first** (unlimited, no login). After **10 seconds** show **Skip**: guest → login screen → then plans/full video; registered without plan → **Plans**; with plan → full video. Player also offers "Watch full video".
  - Tap as **organic user** → login (if guest) → plan check → Plans or full video.
  - Free items → login (if guest) → play.
  - Logged events: `log_event(install_id, 'content_view' | 'preview_view', content_id, view_id)` → analytics + Meta ViewContent.
- **Premium**: plan cards (name, price ₹, days, perks), current plan + expiry, open order/request banner, Buy button → payment flow (section 7). Variants: free mode or Play-without-plans shows a "free account" card (log in for 15 GB cloud, request full access).
- **Payment status / history**: order reference, amount, status, reason, retry/open UPI app again.
- **Cloud**: logged-in users get **15 GB** free (`free_cloud_bytes`; Play build enables via `enable_play_free_cloud`); folders, upload (files to Storage, videos to Bunny), download, rename, delete, usage bar (`cloud_files_usage`).
- **Create channel / New post**: Premium feature (gate shows "Premium needed to create a channel → See plans"); user channels and posts wait for **admin approval**; upload main video + optional preview + thumbnail (thumbnail auto-made with `fc_native_video_thumbnail` if missing).
- **Profile / Settings**: name, avatar, plan, payment history, policies (privacy, terms, community, refund), contact, **Delete account** (edge function `delete-account`), version.

## 6. Admin panel and website (Next.js)

### 6.1 Shared UI kit (`components/ui.tsx`)
PageHeader, Card, Field, Input/Textarea/Select (orange focus), Button/LinkButton (primary orange-700, secondary, danger red, success green), Badge (gray/red/green/amber/blue/purple), AudienceBadge, StatusBadge, SourceBadge, Table/Th/Td, Empty (icon + text), SegmentTabs (link tabs), SectionTitle, Stat (label, value, hint, icon, tone, link), Notice. `Flash` → client **Toast** (top-right): green "Done" auto-closes after 5 s, red "That didn't work" stays until closed; then removes `?ok=`/`?error=` from the URL. Server actions redirect with `?ok=` or `?error=`. Login page: dark background, logo, password field with show/hide **eye**.

### 6.2 Menu and pages
- **Dashboard** (`admin_dashboard`): installs split ads vs organic (bar + %), users, guests vs registered, premium users, revenue today/7 d/30 d, pending payments, pending approvals, pending requests, quick upload button.
- **Content → Channels**: list with audience/status badges; create/edit (name, handle, description, icon, category, audience); **follower count** field (`admin_set_followers` → `followers_offset`); delete; per-channel admin access for content admins.
- **Content → Posts / Upload**:
  - **Single upload**: channel, title, caption, audience, items; each item = **main video/image**, **preview (trailer)**, **thumbnail**, premium on/off.
  - **Bulk upload**: many files at once, each row with its own preview + thumbnail pickers and premium toggle; "add another" rows.
  - Videos upload **resumably (TUS) to Bunny** via `bunny-stream-create`; show upload % then "encoding…" progress; success toast "Video uploaded — it appears in the app when encoding finishes"; clear error + **Try again** (fixes "can't read thumbnail").
  - Posts publish by server time; list, edit, delete.
- **Approvals**: user channels and posts → approve (choose audience) / reject (`review_channel`).
- **Requests**: organic users asking for ads-content access → approve/reject (`set_ads_access`); support/takedown requests (`admin_open_support_requests`, `admin_close_support_request`).
- **People → Users** (`admin_users(filter, search, limit, offset)`): source badge (ads/organic), guest/registered, plan, purchases, joined; grant premium (`grant_premium`).
- **People → Admins** (`admin_list_admins`): owner / content admin, invite, channel access.
- **Revenue → Payments**: see 7.4.
- **Revenue → Plans**: one compact row per plan (name, price ₹, days, order, "In app" toggle, Save; perks under "Edit perks", one per line); **Free mode** bar.
- **Meta Pixel**: Pixel/dataset ID + Conversions API token (saved server-side; a test event is sent on save), tracking on/off, download-page settings (APK URL, title, subtitle), recent events (`admin_meta_events`), match health (`admin_meta_health`), attribution report.
- **Settings**: general.

### 6.3 Public website
- `/home` landing, `/d` download page (ads + organic APK buttons, Meta Pixel PageView + Lead/Download click; `/api/click` calls `record_ad_click` with fbc/fbp/IP/UA/utm so the app install can be matched).
- `/privacy`, `/terms` (also community guidelines + refund policy sections), `/delete-account` (form → `submit_support_request`), `/report-content` (DMCA/takedown form).
- Favicon + logo under `/site/` (public path), `robots: index` on public pages.

## 7. Payments (UPI, no payment gateway)

### 7.1 Tables
- `plans(id, code, name, duration_days, price_inr, perks jsonb, active, position)` — e.g. Trial ₹49/3 d, Silver ₹129/7 d, Gold ₹259/30 d, Platinum ₹599/180 d, Diamond ₹999/365 d.
- `payment_settings(id=1, upi_id, payee_name, enabled)`.
- `payment_orders(id, reference, user_id, plan_id, amount_paise, status initiated|pending|approved|failed|cancelled|revoked, upi_response, client_status, txn_id, verified_at, verification_source upi_app|admin|provider_api, reviewed_by, status_reason, subscription_id, report_count, play_token, play_report_status, play_reported_at, play_report_error, play_attempts, created_at, updated_at)`.
- `payment_events(order_id, kind created|reported|approved|rejected|failed|cancelled|revoked, detail, actor_id, created_at)`.
- `subscriptions(id, user_id, plan_id, source payment|admin|…, starts_at, ends_at, granted_by)`.
- `app_mode(id=1, free_mode)`, `play_settings(id=1, package_name, enabled, function_url, last_run_at, last_error)`.

### 7.2 Flow
1. **`create_payment_order(plan_id)`** — requires a session (guests allowed); payments enabled and plan active; runs `cancel_stale_payment_orders`; reuses the user's open order for the same plan at the same price (< 24 h); cancels the user's other open orders; else creates reference `CS<YYMMDD IST><12 hex upper>`, `amount_paise = price × 100`. Returns order_id, reference, amount, plan_name, **upi_id + payee_name from settings** (never hard-coded), status.
2. App saves the open order locally (to resume) and opens the UPI intent `upi://pay?pa=<upi_id>&pn=<payee>&tr=<reference>&tn=<plan>&am=<amount>&cu=INR`. Money goes straight to the owner's bank.
3. App sends the raw UPI answer to **`report_payment_result(order_id, raw)`**:
   - parse key/values (`parse_upi_response`), normalise status (`normalize_upi_status`);
   - closed orders: log only;
   - `FAILURE` → failed;
   - `SUCCESS` and reference matches and txn id (`ApprovalRefNo`/`txnId`) matches `^[A-Z0-9]{6,40}$` and is unused and order < 2 h → **`activate_payment(…,'upi_app')`** → approved;
   - otherwise → **pending** with a reason (wrong reference, no valid txn id, txn id used, older than 2 h, no answer, still processing).
4. **`activate_payment(order, amount_paise, utr, source)`** — idempotent; amount must equal the order; UTR unique across orders; **plans stack**: start = max(now, latest ends_at), end = start + days; insert subscription; mark approved; log event; triggers fire Meta Purchase/Subscribe and close plan requests.
5. pg_cron `cancel-stale-payment-orders` every 30 min: open orders > 24 h → cancelled.
6. `provider_confirm_payment(reference, amount_paise, utr)` for a future gateway webhook (`upi-webhook` edge function).

### 7.3 Google Play build
- Before the UPI flow show Google's **alternative billing** information screen (Play Billing alternative-billing-only API), attach the external transaction token to the order (`attach_play_token`).
- Edge function `play-report` + pg_cron every 5 min (`play_report_tick`): report every approved **Play-version** order to Google (externaltransactions API) within 24 h using secret `GOOGLE_SERVICE_ACCOUNT_JSON`; report refunds after revoke; retry with errors stored. APK orders are never reported.
- Release notes never mention plans or subscriptions.

### 7.4 Admin Payments page
- Collapsible "How to read this page": a UPI SUCCESS comes from the customer's phone and can be forged → check the bank; Pending → Mark as paid with bank UTR; open orders auto-cancel after 24 h.
- Tabs: **Orders / Plan summary / Customers & repeat buyers**; status tabs All, Pending, Success, Failed, Cancelled, Revoked; filter bar (plan, sort, from, to, Apply, Reset); tiles (orders, successful, ₹ received).
- Table (6 columns): Order (reference + date, tooltip with created/updated/verified), User (name, email/Guest, source badge, "Repeat · N purchases"), Plan · amount, Status (+ reason, Play report badge), UTR / UPI answer ("Show UPI answer"), Action: **Mark as paid…** (UTR + amount → `admin_mark_payment_paid`) or **Revoke…** (reason → `admin_revoke_payment`, ends the subscription).
- Cards side by side: **UPI settings** (UPI ID, payee name, accept payments) and **Google Play reporting** (package name, on/off, waiting/reported/refunds/failed counts, last run, one-time setup steps).
- Plan summary (`admin_plan_sales`) and buyers (`admin_buyers`).

### 7.5 Free mode
`free_mode()` true → no plans or payments anywhere; logged-in **ads** users get full access (`is_premium_user`), organic users request full access; everyone logged in gets 15 GB cloud.

## 8. Video and storage

- **Bunny Stream** (one library): `post_items.bunny_video_id` (main) and `trailer_bunny_video_id` (preview), `processing_status`/`trailer_status`, `has_trailer`.
- Edge functions: `bunny-stream-create` (create video, return TUS upload signature, check `can_post_in`), `bunny-stream-status`, `bunny-stream-url` (signed HLS URL; full video only if `can_read_media`; trailer via `bunny_trailer_path` if has_ads_access or premium), `bunny-stream-delete`, `bunny-stream-sync` (pg_cron `bunny-sync` every minute via `bunny_sync_tick`: mark encoded items ready, generate thumbnail if missing).
- Supabase Storage buckets (private, signed URLs): post media/thumbnails, avatars, `cloud` (per-user folder `<user_id>/…`). Edge functions `cloud-upload`, `cloud-download-url`, `cloud-delete`; quota enforced (`quota_bytes`, trigger on `cloud_files`).
- Posts become visible when `published_at <= now()` (default set by the server: `posts_default_publish_time`) and the item is ready, approved and `can_see(audience)` (`post_visible`, `channel_visible`).
- Guards: `guard_channel_write`, `guard_post_write`, `guard_item_write`, `check_post_audience` (a post can't be wider than its channel), `sync_members_count`.

## 9. Meta tracking (server-side, app events)

### 9.1 One-time setup (owner)
1. Meta for Developers → Create app → Other → **Business**, connect the Business portfolio.
2. App settings → Basic: privacy URL, terms URL, data-deletion instructions URL (`/delete-account`), category Entertainment, 1024 icon, App domains empty. Add platform **Android**: package `com.flixvault.app`, class `com.cloudstorage.cloud_storage.MainActivity` (your MainActivity), **key hash** = base64 of the Play Console **App signing key** SHA-1 bytes, single sign-on off, "Log in-app purchases automatically" **off**.
3. App settings → Advanced → Authorized ad account IDs → your ad account. Business settings → Apps → assign the ad account; People → full control.
4. Switch App Mode to **Live**.
5. Events Manager → select the app → **Link to dataset** → "Create from a pixel ID" → the existing Pixel (keeps history).
6. Ads Manager → App promotion → Google Play → Flixvault; exclude Gujarat + Maharashtra; start with **Maximise number of app installs**; move to Purchase after real purchases. Never send fake events.

### 9.2 Server implementation
- `meta_settings(id=1, pixel_id, access_token, test_event_code, action_source 'app'|'website', website_url, app_package 'com.flixvault.app', enabled, apk_url, page_title, page_subtitle)` — owner-only RLS; token never reaches the app.
- `meta_events(event_name, event_id unique, event_time, user_id, install_id, ad_click_id, client_ip, user_agent, custom_data, status, attempts, request_id, response, sent_at)`.
- Triggers enqueue (`meta_enqueue`): `meta_on_install` → **AppInstall**; `meta_on_registration` → **CompleteRegistration**; `meta_on_view` → **ViewContent** (content_ids, content_type video/trailer); order created → **InitiateCheckout** (value = plan price, INR); `meta_on_payment` on approval → **Purchase** + **Subscribe** (value = amount, INR, event_id `purchase-<order>` / `subscribe-<order>` for dedupe).
- pg_cron `meta-dispatch` every minute: batch POST with pg_net to `https://graph.facebook.com/v21.0/<pixel_id>/events?access_token=…`; store response; retry failures.
- Payload (`meta_event_payload`): `user_data` = SHA-256 `external_id` (user id or install id), SHA-256 lower-cased email, SHA-256 country `in`, `client_ip_address`, `client_user_agent`, `fbc`/`fbp` from matched ad clicks; `action_source` app; `app_data` = `advertiser_tracking_enabled 1`, `application_tracking_enabled 1`, `extinfo` (`a2`, package, version, OS, locale, timezone…).
- Admin "Meta Pixel" page saving never changes `action_source`.

## 10. Database — full table list

`ad_clicks, admin_channel_access, admins(user_id, role owner|content_admin), analytics_events, app_mode, audit_logs, bunny_sync_settings, channel_folders, channel_members, channels(id, name, handle, description, icon_url, category, audience, status, members_count, followers_offset, rating, created_by, review_status, reviewed_by, reviewed_at, …), cloud_files(id, user_id, parent_id, name, is_folder, storage_key, bunny_path, mime, size), consents, geo_blocked_ranges, installs(install_id, referrer_status, raw_referrer, source, utm_*, click_ts, install_ts, first_user_id, client_ip, user_agent, fbc, fbp, ad_click_id, geo_state, geo_blocked, …), meta_events, meta_settings, payment_events, payment_orders, payment_settings, plan_requests, plans, play_settings, post_items(id, post_id, position, kind, is_premium, media_key, preview_key, thumb_key, trailer_key, bunny_video_id, trailer_bunny_video_id, processing_status, trailer_status, has_trailer, duration_s, width, height), posts(id, channel_id, folder_id, title, caption, audience, status, published_at, view_count, like_count, created_by), profiles, reports, subscriptions, support_requests, user_attribution(user_id, first_touch_*, first_touch_install_id, first_touch_at, last_touch_*, last_touch_install_id, last_touch_at)`

Enums: `audience (all, ads, organic)`, `content_status`, `media_kind (video, image)`, `processing_status`, `ads_access_status (none, pending, approved, rejected)`, `admin_role (owner, content_admin)`.

Key functions (all `security definer`, `search_path = ''`, grants only where needed):
access — `is_admin, is_owner, is_registered, can_see, has_ads_access, user_source, source_of, ad_source, geo_blocked, request_geo_state, is_premium_user, free_mode, can_manage_channel, can_post_in, can_read_media, can_upload_post_media, channel_visible, post_visible, is_channel_creator, is_post_creator, quota_bytes`;
app — `my_status, explore, feed, channel_posts, record_install, attribute_user, log_event, request_full_access, report_content_in_app, submit_support_request, enable_play_free_cloud, cloud_files_usage, cloud_folder_keys, cloud_folder_bunny_paths, bunny_video_access, bunny_video_path, bunny_trailer_path`;
payments — `create_payment_order, report_payment_result, activate_payment, provider_confirm_payment, cancel_stale_payment_orders, parse_upi_response, normalize_upi_status, attach_play_token, play_queue_report, play_report_tick, on_plan_activated, close_plan_requests`;
admin — `admin_dashboard, admin_users, admin_list_admins, admin_channel_requests, admin_channel_creators, review_channel, set_ads_access, grant_premium, admin_set_followers, admin_payment_orders, admin_payment_orders_filtered, admin_pending_payments, admin_mark_payment_paid, admin_revoke_payment, admin_plan_sales, admin_buyers, admin_plan_requests, admin_play_report_rows, admin_play_report_summary, admin_meta_events, admin_meta_health, admin_meta_test_event, admin_open_support_requests, admin_close_support_request, attribution_report, download_page_config`;
attribution — `parse_source, referrer_param, url_decode, record_ad_click, install_match_click, protect_first_touch, request_ip, request_user_agent`;
meta — `meta_enqueue, meta_dispatch, meta_event_payload, meta_sha256, meta_on_install, meta_on_registration, meta_on_view, meta_on_payment`;
triggers — `handle_new_user, handle_user_upgraded, guard_channel_write, guard_post_write, guard_item_write, check_post_audience, sync_members_count, posts_default_publish_time`.

pg_cron jobs: `meta-dispatch` (every minute), `bunny-sync` (every minute), `play-report` (every 5 min), `cancel-stale-payment-orders` (every 30 min).

Edge functions: `bunny-stream-create, bunny-stream-status, bunny-stream-url, bunny-stream-delete, bunny-stream-sync, cloud-upload, cloud-download-url, cloud-delete, delete-account, upi-webhook, play-report`.

Security: RLS on every table; app users read only what `can_see` allows and their own private rows; all writes through RPCs; `audit_logs` for admin actions; run Supabase security advisors with zero errors.

## 11. Android builds

- Flavors: `direct` (applicationId `com.cloudstorage.app`, no Google Play code, UPI only) and `play` (applicationId `com.flixvault.app`).
- Commands:
  - Organic APK: `flutter build apk --release --flavor direct`
  - Ads APK: `flutter build apk --release --flavor direct --dart-define=APK_REFERRER="utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download"`
  - Play AAB: `flutter build appbundle --release --flavor play --dart-define=PLAY_STORE=true --dart-define=PLAY_SELLS_UPI=true`
- Signing from CI secrets only; Play App Signing on; version `x.y.z+build`, bump build every release; never change the signing key of a published app.
- Play Console: app content (privacy URL, data safety: account info, app activity, purchase history; no advertising ID unless the Meta SDK is added), content rating, target audience 18+, ads declaration, **Monetize → Alternative billing → alternative billing only (India)**, Open testing → Production.

## 12. Policies (text on the website and in the app)
Privacy (what is collected: account, content, usage + install source, payments; Meta advertising measurement with hashed data; no selling; delete account), Terms (lawful use, approvals, plans in INR, no auto-renew, UPI payments, revocation of invalid payments), Community guidelines + DMCA/report flow, Refund policy (activation on confirmation, double charges refunded, other cases reviewed). Contact email `<your support email>`.

## 13. Tests that must pass
- Attribution: facebook/ig/meta/url-encoded/`apps.facebook.com`/`apps.instagram.com` → meta; Play organic → organic; plain APK → direct; first touch immutable except the referrer retry.
- Audiences: ads guest sees ads content; organic user doesn't until approved; admin sees all.
- Geo: Gujarat IPv4 / Maharashtra IPv6 new install → organic only; other states keep ads; bad header doesn't break install; `x-forwarded-for` ignored; old installs unchanged; approval doesn't override.
- Payments: order reuse, cancel others, success auto-approve, each rejection reason, failure, idempotent approve, UTR reuse blocked, amount mismatch blocked, plan stacking, revoke, 24 h cancel, free mode.
- Meta: one Purchase + one Subscribe per order, hashed email only, app_data with `com.flixvault.app`.
- Storage quota, delete account, RLS on every table.

## 14. Build order
1. Supabase schema, enums, RLS, auth triggers, tests harness.
2. Attribution (installs, referrer, first touch) + audiences + tests.
3. Channels/posts/items + Bunny edge functions + visibility rules.
4. Flutter app shell: guest session, Explore/Feed/Channels/Post, player, gates.
5. Admin panel: login, shell, dashboard, channels, single + bulk upload, approvals, requests, users.
6. Payments: plans, orders, UPI intent, auto/manual verification, admin Payments + Plans, free mode.
7. Cloud storage (15 GB), create channel/post, profile, delete account, policies, public website + download page.
8. Meta Conversions API events + admin Meta page.
9. Gujarat/Maharashtra rule.
10. Google Play flavor, alternative billing + reporting, CI for organic APK, ads APK, Play AAB.
11. Polish: brand, toasts, empty states, phone-width layouts, accessibility; final test pass and a checklist run (install via Meta link → ads; Play search → organic; GJ/MH → organic; UPI success → plan + Purchase event; Mark as paid; Revoke; change UPI ID; free mode).
