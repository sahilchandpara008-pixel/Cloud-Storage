-- Behaviour tests for the schema: audience rules, approvals, attribution,
-- membership, admin permissions. Run with supabase/tests/run_tests.sh.
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create schema t;
grant usage on schema t to anon, authenticated, service_role;

-- Most tests below check the paid-plan rules; free mode is tested at the end.
update public.app_mode set free_mode = false;

create function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then
    raise exception 'FAIL: %', msg;
  end if;
  raise notice 'ok - %', msg;
end $$;

create function t.fails(sql text, msg text) returns void language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    raise notice 'ok - % (%)', msg, sqlerrm;
    return;
  end;
  raise exception 'FAIL: expected error: %', msg;
end $$;
grant execute on all functions in schema t to anon, authenticated, service_role;

-- Fixed ids make the tests readable.
create table t.ids (name text primary key, id uuid not null);
insert into t.ids values
  ('owner',          '00000000-0000-0000-0000-000000000001'),
  ('content_admin',  '00000000-0000-0000-0000-000000000002'),
  ('ads_guest',      '00000000-0000-0000-0000-000000000003'),
  ('organic_guest',  '00000000-0000-0000-0000-000000000004'),
  ('ads_user',       '00000000-0000-0000-0000-000000000005'),
  ('organic_user',   '00000000-0000-0000-0000-000000000006'),
  ('organic_buyer',  '00000000-0000-0000-0000-000000000007');
grant select on t.ids to anon, authenticated;
create function t.id(p text) returns uuid language sql stable as $$ select id from t.ids where name = p $$;
grant execute on function t.id(text) to anon, authenticated;

-- Switch the session to a user (role authenticated) or back to superuser.
create function t.act_as(p text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(t.id(p)::text, ''), false);
end $$;

-- ---------------------------------------------------------------------------
-- Fixtures (as superuser)
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, is_anonymous) values
  (t.id('owner'),         'owner@example.com', false),
  (t.id('content_admin'), 'staff@example.com', false),
  (t.id('ads_guest'),     null,                true),
  (t.id('organic_guest'), null,                true),
  (t.id('ads_user'),      null,                true),
  (t.id('organic_user'),  null,                true),
  (t.id('organic_buyer'), null,                true);

insert into public.admins (user_id, role) values
  (t.id('owner'), 'owner'), (t.id('content_admin'), 'content_admin');

select t.ok((select count(*) from public.profiles) = 7, 'profile created for every auth user');
select t.ok((select display_name from public.profiles where id = t.id('ads_guest')) like 'User-%',
            'guest gets a generated User-xxxx name');

-- Channels and posts
insert into public.channels (id, name, audience, status) values
  ('10000000-0000-0000-0000-000000000001', 'Everyone channel', 'all',     'published'),
  ('10000000-0000-0000-0000-000000000002', 'Ads channel',      'ads',     'published'),
  ('10000000-0000-0000-0000-000000000003', 'Organic channel',  'organic', 'published'),
  ('10000000-0000-0000-0000-000000000004', 'Draft channel',    'all',     'draft');

insert into public.posts (id, channel_id, title, audience, status, published_at) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'all/all',      'all',     'published', now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'all/ads',      'ads',     'published', now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'all/organic',  'organic', 'published', now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', 'ads/ads',      'ads',     'published', now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000003', 'org/org',      'organic', 'published', now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000001', 'hidden',       'all',     'hidden',    now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000001', 'draft',        'all',     'draft',     null),
  ('20000000-0000-0000-0000-000000000008', '10000000-0000-0000-0000-000000000001', 'scheduled',    'all',     'published', now() + interval '1 day'),
  ('20000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000001', 'processing',   'all',     'published', now() - interval '1 hour'),
  ('20000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000004', 'in draft ch',  'all',     'published', now() - interval '1 hour');

insert into public.post_items (post_id, kind, is_premium, media_key, hls_key, processing_status)
select id, 'video', true, 'orig/' || id, 'hls/' || id,
       case when title = 'processing' then 'pending'::public.processing_status else 'ready' end
  from public.posts;

select t.fails($$insert into public.posts (channel_id, title, audience)
                 values ('10000000-0000-0000-0000-000000000002', 'x', 'organic')$$,
               'organic post cannot be placed in an ads-only channel');

-- ---------------------------------------------------------------------------
-- Attribution
-- ---------------------------------------------------------------------------
select t.ok(public.parse_source('ok', 'utm_source=facebook&utm_medium=paid_social') = 'meta', 'facebook → meta');
select t.ok(public.parse_source('ok', 'utm_source%3Dig%26utm_campaign%3Dx') = 'meta', 'url-encoded ig → meta');
select t.ok(public.parse_source('apk', 'utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download') = 'meta', 'ads APK → meta');
select t.ok(public.parse_source('ok', 'utm_source=google-play&utm_medium=organic') = 'organic', 'play organic → organic');
select t.ok(public.parse_source('not_available', null) = 'direct', 'plain APK → direct');
select t.ok(public.parse_source('ok', 'utm_source=newsletter') = 'other', 'other source → other');

set role authenticated;

select t.act_as('ads_guest');
select t.ok(public.record_install('30000000-0000-0000-0000-000000000003', 'apk',
            'utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download') = 'meta',
            'ads guest install recorded as meta');
select t.ok(public.user_source() = 'ads', 'ads guest is an ads user');

select t.act_as('organic_guest');
select t.ok(public.record_install('30000000-0000-0000-0000-000000000004', 'not_available') = 'direct',
            'organic guest install recorded as direct');
select t.ok(public.user_source() = 'organic', 'organic guest is organic');

select t.act_as('ads_user');
select public.record_install('30000000-0000-0000-0000-000000000005', 'apk',
       'utm_source=instagram&utm_campaign=diwali');
select t.act_as('organic_user');
select public.record_install('30000000-0000-0000-0000-000000000006', 'not_available');
select t.act_as('organic_buyer');
select public.record_install('30000000-0000-0000-0000-000000000007', 'not_available');

select t.ok(not exists (select 1 from public.installs), 'app users cannot read installs');

reset role;
-- Guests that link Email/Google become registered.
update auth.users set is_anonymous = false
 where id in (t.id('ads_user'), t.id('organic_user'), t.id('organic_buyer'));
select t.ok((select count(*) from public.profiles where not is_guest) = 5, 'linked users are no longer guests');

-- Test 6: first touch never changes after reinstall via the other link.
set role authenticated;
select t.act_as('ads_user');
select public.record_install('30000000-0000-0000-0000-000000000099', 'not_available');
select t.ok(public.user_source() = 'ads', 'reinstall via organic APK keeps first touch = ads');
select t.ok((select last_touch_install_id from public.user_attribution where user_id = t.id('ads_user'))
            = '30000000-0000-0000-0000-000000000099', 'last touch is updated');
select t.act_as('organic_user');
select public.record_install('30000000-0000-0000-0000-000000000098', 'apk', 'utm_source=meta');
select t.ok(public.user_source() = 'organic', 'reinstall via ads APK keeps first touch = organic');
reset role;
select t.fails($$update public.user_attribution set first_touch_source = 'meta'
                  where user_id = t.id('organic_user')$$,
               'first touch cannot be overwritten even by a direct update');

-- First successful referrer read wins.
select public.record_install('30000000-0000-0000-0000-000000000050', 'error');
select public.record_install('30000000-0000-0000-0000-000000000050', 'ok', 'utm_source=fb');
select public.record_install('30000000-0000-0000-0000-000000000050', 'ok', 'utm_source=google-play&utm_medium=organic');
select t.ok((select source from public.installs where install_id = '30000000-0000-0000-0000-000000000050') = 'meta',
            'failed read is replaced by the first successful one, which is then kept');

-- ---------------------------------------------------------------------------
-- Visibility (tests 1, 4, 5)
-- ---------------------------------------------------------------------------
create function t.visible_titles() returns text language sql as $$
  select coalesce(string_agg(title, ',' order by title), '') from public.posts
$$;
grant execute on function t.visible_titles() to authenticated;

set role authenticated;

select t.act_as('ads_guest');
select t.ok(t.visible_titles() = 'ads/ads,all/ads,all/all', 'ads guest: everyone + ads posts only');
select t.ok((select count(*) from public.channels) = 2, 'ads guest: Everyone + Ads channels');

select t.act_as('organic_guest');
select t.ok(t.visible_titles() = 'all/all,all/organic,org/org', 'organic guest: everyone + organic posts only');
select t.ok((select count(*) from public.channels) = 2, 'organic guest: Everyone + Organic channels');

select t.act_as('ads_user');
select t.ok(t.visible_titles() = 'ads/ads,all/ads,all/all', 'logged-in ads user: everyone + ads');

select t.act_as('organic_user');
select t.ok(t.visible_titles() = 'all/all,all/organic,org/org', 'logged-in organic user: everyone + organic');
select t.ok((select count(*) from public.post_items) = 3, 'items follow post visibility');
select t.ok(not exists (select 1 from public.posts where title in
            ('hidden', 'draft', 'scheduled', 'processing', 'in draft ch')),
            'hidden, draft, scheduled, still-processing, and draft-channel posts never appear');
select t.ok((select count(*) from public.explore('latest')) = 3, 'explore() respects the same rules');
select t.fails($$select hls_key from public.post_items$$, 'app users cannot read processing keys');

-- ---------------------------------------------------------------------------
-- Approvals for organic buyers
-- ---------------------------------------------------------------------------
select t.act_as('organic_buyer');
select t.fails($$select public.grant_premium(t.id('organic_buyer'), 'gold')$$,
               'users cannot grant themselves premium');
select t.fails($$update public.profiles set ads_access_status = 'approved' where id = t.id('organic_buyer')$$,
               'users cannot approve themselves');

select t.act_as('owner');
select public.grant_premium(t.id('organic_buyer'), 'gold');
select public.grant_premium(t.id('ads_user'), 'trial');
select t.ok((select ads_access_status from public.profiles where id = t.id('organic_buyer')) = 'pending',
            'organic buyer is highlighted as pending');
select t.ok((select ads_access_status from public.profiles where id = t.id('ads_user')) = 'none',
            'ads buyer is not sent for approval');

select t.act_as('organic_buyer');
select t.ok(public.is_premium_user(), 'buyer is premium');
select t.ok(t.visible_titles() = 'all/all,all/organic,org/org', 'pending organic buyer still cannot see ads content');

select t.act_as('content_admin');
select t.fails($$select public.set_ads_access(t.id('organic_buyer'), 'approved')$$,
               'content admins cannot approve');

select t.act_as('owner');
select public.set_ads_access(t.id('organic_buyer'), 'approved');

select t.act_as('organic_buyer');
select t.ok(t.visible_titles() = 'ads/ads,all/ads,all/all,all/organic,org/org',
            'approved organic buyer sees everything');

select t.act_as('owner');
select public.set_ads_access(t.id('organic_buyer'), 'rejected');
select t.act_as('organic_buyer');
select t.ok(t.visible_titles() = 'all/all,all/organic,org/org', 'revoked approval removes ads content again');

-- ---------------------------------------------------------------------------
-- Channel membership
-- ---------------------------------------------------------------------------
select t.act_as('ads_guest');
select t.fails($$insert into public.channel_members (channel_id, user_id)
                 values ('10000000-0000-0000-0000-000000000001', t.id('ads_guest'))$$,
               'guests must log in to join');

select t.act_as('organic_user');
insert into public.channel_members (channel_id, user_id)
values ('10000000-0000-0000-0000-000000000001', t.id('organic_user'));
select t.ok(true, 'logged-in user joins a channel');
select t.fails($$insert into public.channel_members (channel_id, user_id)
                 values ('10000000-0000-0000-0000-000000000002', t.id('organic_user'))$$,
               'organic user cannot join an ads-only channel');
select t.ok((select string_agg(title, ',' order by title) from public.feed()) = 'all/all,all/organic',
            'feed shows visible posts from joined channels');

reset role;
select t.ok((select members_count from public.channels
              where id = '10000000-0000-0000-0000-000000000001') = 1, 'members_count updated');

-- ---------------------------------------------------------------------------
-- Admin permissions
-- ---------------------------------------------------------------------------
set role authenticated;
select t.act_as('content_admin');
select t.ok((select count(*) from public.posts) = 10, 'admins see all posts, including drafts');
update public.posts set title = 'all/all' where id = '20000000-0000-0000-0000-000000000001';
select t.ok(true, 'content admin can edit posts');

reset role;
insert into public.admin_channel_access values (t.id('content_admin'), '10000000-0000-0000-0000-000000000002');
set role authenticated;
select t.act_as('content_admin');
update public.posts set caption = 'nope' where id = '20000000-0000-0000-0000-000000000001';
reset role;
select t.ok((select caption from public.posts where id = '20000000-0000-0000-0000-000000000001') is null,
            'content admin limited to one channel cannot edit other channels');

set role authenticated;
select t.act_as('organic_user');
update public.posts set title = 'hacked' where id = '20000000-0000-0000-0000-000000000001';
reset role;
select t.ok((select title from public.posts where id = '20000000-0000-0000-0000-000000000001') = 'all/all',
            'app users cannot edit posts');

-- ---------------------------------------------------------------------------
-- Analytics & report (test 7)
-- ---------------------------------------------------------------------------
set role authenticated;
select t.act_as('ads_user');
select public.log_event('30000000-0000-0000-0000-000000000005', 'content_view',
       '20000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000001');
select public.log_event('30000000-0000-0000-0000-000000000005', 'content_view',
       '20000000-0000-0000-0000-000000000004', '40000000-0000-0000-0000-000000000001');
select t.fails($$select public.log_event(null, 'purchase')$$, 'clients cannot log purchases');

select t.act_as('organic_user');
select t.fails($$select * from public.attribution_report()$$, 'only the owner sees the report');

select t.act_as('owner');
select t.ok((select count(*) from public.analytics_events where event = 'special_content_view') = 1,
            'special_content_view logged once per view');
select t.ok((select installs from public.attribution_report() where source = 'meta' and campaign = 'apk_download') = 1,
            'report counts installs per source and campaign');
select t.ok((select registrations from public.attribution_report() where source = 'meta' and campaign = 'diwali') = 1,
            'report counts registrations');
select t.ok((select buyers from public.attribution_report() where source = 'direct') = 1,
            'report counts buyers');

reset role;

-- ---------------------------------------------------------------------------
-- Admin panel read models
-- ---------------------------------------------------------------------------
set role authenticated;
select t.act_as('organic_user');
select t.fails($$select * from public.admin_users()$$, 'app users cannot list users');
select t.fails($$select public.admin_dashboard()$$, 'app users cannot read the dashboard');
select t.act_as('content_admin');
select t.fails($$select * from public.admin_list_admins()$$, 'content admins cannot list admins');
select t.ok((public.admin_dashboard()->>'posts_published')::int = 8, 'content admins can read the dashboard');

select t.act_as('owner');
select t.ok((select count(*) from public.admin_users()) = 5, 'owner lists app users (admins excluded)');
select t.ok((select source from public.admin_users() where id = t.id('ads_user')) = 'ads', 'user list shows source');
select t.ok((select plan_name from public.admin_users() where id = t.id('organic_buyer')) = 'Gold Plan',
            'user list shows the active plan');
select t.ok((select count(*) from public.admin_users('rejected')) = 1, 'filter by approval status');
select t.ok((select count(*) from public.admin_users('all', 'staff@')) = 0, 'search does not return admins');
select t.ok((select email from public.admin_list_admins() where role = 'content_admin') = 'staff@example.com',
            'owner lists admins with emails');
select t.ok((select array_length(channel_ids, 1) from public.admin_list_admins() where role = 'content_admin') = 1,
            'admin list shows channel limits');
select t.ok((public.admin_dashboard()->>'installs_ads')::int >= 2, 'dashboard counts ads installs');
reset role;

-- ---------------------------------------------------------------------------
-- Storage, personal cloud, plan requests, status
-- ---------------------------------------------------------------------------
-- Media objects for the "all/all" (visible) and "all/ads" posts.
update public.post_items set media_key = 'posts/' || post_id || '.mp4';
insert into storage.objects (bucket_id, name)
select 'media', media_key from public.post_items;
-- Make the all/all item free so non-premium users can read it.
update public.post_items set is_premium = false where post_id = '20000000-0000-0000-0000-000000000001';

set role authenticated;
select t.act_as('organic_guest');
select t.ok((select count(*) from storage.objects where bucket_id = 'media') = 1,
            'organic guest can read only the free, visible media file');
select t.act_as('ads_user');  -- has a trial plan → premium
select t.ok((select count(*) from storage.objects where bucket_id = 'media') = 3,
            'premium ads user reads premium media of visible posts only (everyone + ads)');
select t.fails($$insert into storage.objects (bucket_id, name) values ('media', 'x.mp4')$$,
               'app users cannot upload media');

-- Personal cloud
select t.act_as('organic_user');  -- not premium
select t.fails($$insert into public.cloud_files (name, is_folder) values ('Docs', true)$$,
               'non-premium users cannot use cloud storage');
select t.fails($$insert into storage.objects (bucket_id, name)
                 values ('cloud', t.id('organic_user') || '/a.txt')$$,
               'non-premium users cannot upload cloud files');

select t.act_as('ads_user');
insert into public.cloud_files (id, name, is_folder) values ('50000000-0000-0000-0000-000000000001', 'Docs', true);
insert into public.cloud_files (parent_id, name, storage_key, mime, size)
values ('50000000-0000-0000-0000-000000000001', 'a.pdf', t.id('ads_user') || '/1-a.pdf', 'application/pdf', 1000);
insert into storage.objects (bucket_id, name) values ('cloud', t.id('ads_user') || '/1-a.pdf');
select t.ok((select used_bytes from public.profiles where id = t.id('ads_user')) = 1000, 'used bytes tracked');
select t.ok((public.my_status()->>'quota_bytes')::bigint = 2199023255552, 'premium quota is 2 TB');
select t.ok((select count(*) from public.cloud_folder_keys('50000000-0000-0000-0000-000000000001')) = 1,
            'folder keys include nested files');
select t.fails($$insert into storage.objects (bucket_id, name) values ('cloud', t.id('organic_user') || '/x')$$,
               'cannot upload into another user''s folder');
select t.fails($$update public.cloud_files set size = 1 where name = 'a.pdf'$$,
               'file size cannot be changed after upload');

select t.act_as('organic_user');
select t.ok((select count(*) from public.cloud_files) = 0, 'users cannot see others'' cloud files');
select t.ok((select count(*) from storage.objects where bucket_id = 'cloud') = 0, 'users cannot read others'' cloud objects');

select t.act_as('ads_user');
delete from public.cloud_files where id = '50000000-0000-0000-0000-000000000001';
select t.ok((select used_bytes from public.profiles where id = t.id('ads_user')) = 0,
            'deleting a folder frees the space of its files');

-- Plan requests
select t.act_as('ads_guest');
select t.fails($$insert into public.plan_requests (plan_id) select id from public.plans where code = 'gold'$$,
               'guests must log in before requesting a plan');
select t.act_as('organic_user');
insert into public.plan_requests (plan_id) select id from public.plans where code = 'gold';
select t.ok(public.my_status()->>'open_request' = 'Gold Plan', 'status shows the open request');
select t.act_as('owner');
select t.ok((select count(*) from public.admin_plan_requests()) = 1, 'owner sees open plan requests');
select public.grant_premium(t.id('organic_user'), 'gold');
select t.ok((select count(*) from public.admin_plan_requests()) = 0, 'granting a plan closes the request');

select t.act_as('organic_user');
select t.ok((public.my_status()->>'is_premium')::boolean, 'status shows premium after grant');
select t.ok(public.my_status()->>'source' = 'organic', 'status shows source');

reset role;

-- ---------------------------------------------------------------------------
-- User-created channels
-- ---------------------------------------------------------------------------
set role authenticated;
select t.act_as('ads_guest');
select t.fails($$insert into public.channels (name) values ('Guest channel')$$,
               'guests must log in to create a channel');

select t.act_as('organic_user');
insert into public.channels (id, name, audience, status)
values ('60000000-0000-0000-0000-000000000001', 'My Vlogs', 'ads', 'published');
select t.ok((select review_status || '/' || status || '/' || audience from public.channels
              where id = '60000000-0000-0000-0000-000000000001') = 'pending/draft/all',
            'new user channel starts as a pending request (status/audience forced)');
select t.ok((select created_by from public.channels where id = '60000000-0000-0000-0000-000000000001')
            = t.id('organic_user'), 'creator recorded');
update public.channels set audience = 'ads', status = 'published', review_status = 'approved', name = 'My Vlogs 2'
 where id = '60000000-0000-0000-0000-000000000001';
select t.ok((select name || '/' || review_status || '/' || audience from public.channels
              where id = '60000000-0000-0000-0000-000000000001') = 'My Vlogs 2/pending/all',
            'creator can rename but cannot approve, publish or set audience');
select t.fails($$insert into public.posts (channel_id, title, status)
                 values ('60000000-0000-0000-0000-000000000001', 'too early', 'published')$$,
               'creator cannot post before approval');
insert into public.channels (name) values ('Two'), ('Three');
select t.fails($$insert into public.channels (name) values ('Four')$$, 'max 3 pending channel requests');

select t.act_as('ads_user');
select t.ok(not exists (select 1 from public.channels where id = '60000000-0000-0000-0000-000000000001'),
            'pending channel is invisible to other users');

select t.act_as('content_admin');
select t.fails($$select public.review_channel('60000000-0000-0000-0000-000000000001', true, 'ads')$$,
               'content admins cannot review channel requests');

select t.act_as('owner');
select t.ok((select count(*) from public.admin_channel_requests()) = 3, 'owner sees pending channel requests');
select t.ok((public.admin_dashboard()->>'pending_channels')::int = 3, 'dashboard counts channel requests');
select public.review_channel('60000000-0000-0000-0000-000000000001', true, 'ads');
select t.ok((select review_status || '/' || status || '/' || audience from public.channels
              where id = '60000000-0000-0000-0000-000000000001') = 'approved/published/ads',
            'owner approves and sets the audience');
select t.ok(exists (select 1 from public.channel_members
                     where channel_id = '60000000-0000-0000-0000-000000000001' and user_id = t.id('organic_user')),
            'creator follows their approved channel');

select t.act_as('organic_user');
insert into public.posts (id, channel_id, title, audience, status)
values ('70000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'Vlog 1', 'organic', 'published');
select t.ok((select audience || '/' || status from public.posts where id = '70000000-0000-0000-0000-000000000001')
            = 'ads/published', 'creator post follows the channel audience');
insert into public.post_items (post_id, kind, is_premium, media_key, processing_status)
values ('70000000-0000-0000-0000-000000000001', 'video', false,
        'posts/70000000-0000-0000-0000-000000000001/v.mp4', 'ready');
select t.ok((select is_premium from public.post_items where post_id = '70000000-0000-0000-0000-000000000001'),
            'creator items are premium by default (owner decides)');
update public.post_items set is_premium = false where post_id = '70000000-0000-0000-0000-000000000001';
select t.ok((select is_premium from public.post_items where post_id = '70000000-0000-0000-0000-000000000001'),
            'creator cannot make items free');
insert into storage.objects (bucket_id, name)
values ('media', 'posts/70000000-0000-0000-0000-000000000001/v.mp4');
select t.ok(true, 'creator uploads media for their post');
select t.fails($$insert into storage.objects (bucket_id, name)
                 values ('media', 'posts/20000000-0000-0000-0000-000000000001/x.mp4')$$,
               'creator cannot upload into other channels'' posts');
select t.fails($$insert into public.posts (channel_id, title) values ('10000000-0000-0000-0000-000000000001', 'x')$$,
               'creator cannot post in channels they did not create');

select t.act_as('ads_user');
select t.ok(exists (select 1 from public.posts where id = '70000000-0000-0000-0000-000000000001'),
            'ads users see the approved ads channel''s posts');
insert into public.channel_members (channel_id, user_id)
values ('60000000-0000-0000-0000-000000000001', t.id('ads_user'));
select public.log_event(null, 'content_view', '70000000-0000-0000-0000-000000000001', gen_random_uuid());

select t.act_as('organic_guest_2');
reset role;
select t.ok((select members_count from public.channels where id = '60000000-0000-0000-0000-000000000001') = 2,
            'member counter still updates (guards skip internal updates)');
select t.ok((select view_count from public.posts where id = '70000000-0000-0000-0000-000000000001') = 1,
            'view counter still updates');

set role authenticated;
select t.act_as('organic_buyer');  -- organic, approval was revoked earlier
select t.ok(not exists (select 1 from public.posts where id = '70000000-0000-0000-0000-000000000001'),
            'organic users do not see the ads channel''s posts');
select t.act_as('owner');
select public.review_channel(id, false) from public.channels where name = 'Two';
reset role;
select t.ok((select review_status from public.channels where name = 'Two') = 'rejected', 'owner can reject');

-- ---------------------------------------------------------------------------
-- Trailers and creator access
-- ---------------------------------------------------------------------------
-- Vlog 1 (ads channel, premium item by organic_user the creator) gets a trailer.
update public.post_items set trailer_key = 'posts/70000000-0000-0000-0000-000000000001/t.mp4'
 where post_id = '70000000-0000-0000-0000-000000000001';
insert into storage.objects (bucket_id, name) values ('media', 'posts/70000000-0000-0000-0000-000000000001/t.mp4');
-- ads_guest is a guest (not premium); remove ads_user's plan to test a non-premium ads user too.
delete from public.subscriptions where user_id = t.id('ads_user');

set role authenticated;
select t.act_as('ads_guest');
select t.ok(exists (select 1 from storage.objects where name = 'posts/70000000-0000-0000-0000-000000000001/t.mp4'),
            'ads guest can play the trailer without login or plan');
select t.ok(not exists (select 1 from storage.objects where name = 'posts/70000000-0000-0000-0000-000000000001/v.mp4'),
            'ads guest cannot play the full premium video');
select t.ok((select trailer_key from public.post_items where post_id = '70000000-0000-0000-0000-000000000001') is not null,
            'app can read the trailer key');

select t.act_as('ads_user');
select t.ok(not exists (select 1 from storage.objects where name = 'posts/70000000-0000-0000-0000-000000000001/v.mp4'),
            'ads user without a plan cannot play the full video');

select t.act_as('organic_buyer');  -- organic, approval revoked earlier
select t.ok(not exists (select 1 from storage.objects where name = 'posts/70000000-0000-0000-0000-000000000001/t.mp4'),
            'organic user cannot get the trailer');

select t.act_as('organic_user');   -- the creator; has a plan from earlier, remove it
reset role;
delete from public.subscriptions where user_id = t.id('organic_user');
set role authenticated;
select t.act_as('organic_user');
select t.ok(not public.is_premium_user(), 'creator has no plan');
select t.ok(exists (select 1 from storage.objects where name = 'posts/70000000-0000-0000-0000-000000000001/v.mp4'),
            'creator plays their own full video without a plan');
reset role;

-- ---------------------------------------------------------------------------
-- UPI payments
-- ---------------------------------------------------------------------------
create table t.v (k text primary key, v text);
grant all on t.v to authenticated, service_role;
grant select on t.ids to service_role;
create function t.get(p text) returns text language sql stable as $$ select v from t.v where k = p $$;
create function t.put(p text, val text) returns void language sql as $$
  insert into t.v values (p, val) on conflict (k) do update set v = excluded.v $$;
grant execute on function t.get(text), t.put(text, text) to authenticated;
create function t.order_status(p text) returns text language sql stable security definer as $$
  select status from public.payment_orders where id = t.get(p)::uuid $$;
create function t.plan_end(p text) returns timestamptz language sql stable security definer as $$
  select max(ends_at) from public.subscriptions where user_id = t.id(p) $$;
grant execute on function t.order_status(text), t.plan_end(text) to authenticated;

set role authenticated;
select t.act_as('ads_guest');
select t.fails($$select public.create_payment_order((select id from public.plans where code = 'gold'))$$,
               'guest cannot create a payment order');

select t.act_as('ads_user');
select t.put('o1', public.create_payment_order((select id from public.plans where code = 'silver'))->>'order_id');
select t.ok((select amount_paise from public.payment_orders where id = t.get('o1')::uuid) = 12900,
            'order amount comes from the server (₹129.00 exactly)');
select t.ok((select reference ~ '^CS[0-9]{6}[0-9A-F]{12}$' and length(reference) <= 35
               and status = 'initiated' and upi_response is null and txn_id is null
               and verified_at is null and verification_source is null and reviewed_by is null
               from public.payment_orders where id = t.get('o1')::uuid),
            'new order: alphanumeric reference ≤35, initiated, empty result fields');
select t.ok((public.create_payment_order((select id from public.plans where code = 'silver'))->>'order_id') = t.get('o1'),
            'same plan within 24 h reuses the open order');
select t.ok((public.create_payment_order((select id from public.plans where code = 'silver'))->>'amount') = '129.00',
            'amount is sent with two decimals');
select t.put('o2', public.create_payment_order((select id from public.plans where code = 'gold'))->>'order_id');
select t.ok(t.order_status('o1') = 'cancelled' and t.order_status('o2') = 'initiated',
            'a new order for another plan closes the other open order');

-- Clients cannot write orders or call the activation function.
select t.fails($$update public.payment_orders set status = 'approved' where id = t.get('o2')::uuid$$,
               'user cannot set an order status directly');
select t.fails($$insert into public.payment_orders (reference, user_id, plan_id, amount_paise)
                 select 'X1', t.id('ads_user'), id, 100 from public.plans where code = 'gold'$$,
               'user cannot insert orders');
select t.fails($$select public.activate_payment(t.get('o2')::uuid, 25900, 'ABC123456', 'admin')$$,
               'user cannot call activate_payment');
select t.fails($$select public.provider_confirm_payment('X', 25900, 'ABC123456')$$,
               'user cannot call the provider hook');
select t.fails($$select public.admin_mark_payment_paid(t.get('o2')::uuid, 'ABC123456', 259)$$,
               'user cannot mark an order as paid');
select t.fails($$insert into public.subscriptions (user_id, plan_id, ends_at)
                 select t.id('ads_user'), id, now() + interval '1 day' from public.plans where code = 'gold'$$,
               'user cannot grant themselves a plan');

-- Wrong txnRef → pending, nothing granted.
select t.ok((public.report_payment_result(t.get('o2')::uuid,
              'txnId=AXI111111&responseCode=00&Status=SUCCESS&txnRef=CS000000WRONG')->>'status') = 'pending',
            'SUCCESS with another order''s txnRef stays pending');
select t.ok(not public.is_premium_user(), '… and grants nothing');
select t.ok((select upi_response from public.payment_orders where id = t.get('o2')::uuid) like '%CS000000WRONG%',
            '… and the raw answer is saved');
-- Missing txn id → pending.
select t.ok((public.report_payment_result(t.get('o2')::uuid, 'Status=SUCCESS&responseCode=00')->>'status') = 'pending',
            'SUCCESS without a transaction id stays pending');
-- Unparseable / NO_RESPONSE / SUBMITTED → pending, answer saved.
select t.ok((public.report_payment_result(t.get('o2')::uuid, 'Status=NO_RESPONSE')->>'status') = 'pending',
            'no answer from the UPI app stays pending');
select t.ok((public.report_payment_result(t.get('o2')::uuid, 'garbage %ZZ %C3')->>'status') = 'pending',
            'unreadable answer is saved and stays pending');
select t.ok((select report_count from public.payment_orders where id = t.get('o2')::uuid) = 4,
            'every answer was recorded');

-- Other user's order.
select t.act_as('organic_user');
select t.fails($$select public.report_payment_result(t.get('o2')::uuid, 'Status=SUCCESS&txnId=AXI222222')$$,
               'user cannot report a result for someone else''s order');
select t.ok(not exists (select 1 from public.payment_orders where user_id = t.id('ads_user')),
            'user cannot see someone else''s orders');
select t.ok(not exists (select 1 from public.payment_settings), 'app users cannot read payment settings');

-- Real success.
select t.act_as('ads_user');
select t.ok((public.report_payment_result(t.get('o2')::uuid,
              'txnId=AXI333333&responseCode=00&Status=SUCCESS&txnRef=' ||
              (select reference from public.payment_orders where id = t.get('o2')::uuid) ||
              '&ApprovalRefNo=627312345678')->>'status') = 'approved',
            'real SUCCESS with matching txnRef + transaction id activates');
select t.ok(public.is_premium_user(), '… user now has a plan');
select t.ok((select txn_id = '627312345678' and verification_source = 'upi_app' and verified_at is not null
               from public.payment_orders where id = t.get('o2')::uuid),
            '… ApprovalRefNo is stored as the UTR with source upi_app');
select t.ok(t.plan_end('ads_user') between now() + interval '29 days 23 hours' and now() + interval '30 days 1 hour',
            '… Gold plan lasts 30 days');
select t.put('end1', t.plan_end('ads_user')::text);

-- Double report → no second grant.
select t.ok((public.report_payment_result(t.get('o2')::uuid,
              'txnId=AXI333333&Status=SUCCESS&ApprovalRefNo=627312345678')->>'status') = 'approved',
            'reporting again returns approved');
select t.ok((select count(*) from public.subscriptions where user_id = t.id('ads_user')) = 1,
            '… and does not grant a second plan');

-- Reused transaction id on a new order → pending.
select t.put('o3', public.create_payment_order((select id from public.plans where code = 'trial'))->>'order_id');
select t.ok((public.report_payment_result(t.get('o3')::uuid,
              'Status=SUCCESS&ApprovalRefNo=627312345678')->>'status') = 'pending',
            'a transaction id that was already used stays pending');
select t.ok((select count(*) from public.subscriptions where user_id = t.id('ads_user')) = 1, '… nothing granted');

-- Failure.
select t.ok((public.report_payment_result(t.get('o3')::uuid, 'Status=FAILURE&responseCode=ZD')->>'status') = 'failed',
            'FAILURE marks the order failed');
select t.ok((public.report_payment_result(t.get('o3')::uuid, 'Status=SUCCESS&ApprovalRefNo=AXI999999')->>'status') = 'failed',
            'a failed order cannot become successful from the app');

-- Order older than 2 hours → pending.
select t.put('o4', public.create_payment_order((select id from public.plans where code = 'silver'))->>'order_id');
reset role;
update public.payment_orders set created_at = now() - interval '3 hours' where id = t.get('o4')::uuid;
set role authenticated;
select t.act_as('ads_user');
select t.ok((public.report_payment_result(t.get('o4')::uuid, 'Status=SUCCESS&ApprovalRefNo=AXI444444')->>'status') = 'pending',
            'SUCCESS for an order older than 2 hours stays pending');

-- Owner: Mark as paid / Revoke.
select t.act_as('content_admin');
select t.fails($$select public.admin_mark_payment_paid(t.get('o4')::uuid, 'BANKUTR4444', 129)$$,
               'content admin cannot mark payments as paid');
select t.fails($$select * from public.admin_payment_orders()$$, 'content admin cannot list payments');
select t.act_as('owner');
select t.ok((select count(*) from public.admin_payment_orders('all')) = 4, 'owner sees all orders');
select t.ok((select count(*) from public.admin_payment_orders('pending')) = 1, 'owner can filter pending orders');
select t.ok((select upi_response from public.admin_payment_orders('pending')) like '%AXI444444%',
            'owner sees the raw UPI answer');
select t.fails($$select public.admin_mark_payment_paid(t.get('o4')::uuid, 'BANKUTR4444', 100)$$,
               'Mark as paid needs the exact amount');
select t.fails($$select public.admin_mark_payment_paid(t.get('o4')::uuid, '', 129)$$,
               'Mark as paid needs a UTR');
select t.fails($$select public.admin_mark_payment_paid(t.get('o4')::uuid, '627312345678', 129)$$,
               'Mark as paid refuses a UTR already used');
select t.ok((public.admin_mark_payment_paid(t.get('o4')::uuid, 'BANKUTR4444', 129)->>'status') = 'approved',
            'owner marks a pending order as paid with the bank UTR');
select t.ok((public.admin_mark_payment_paid(t.get('o4')::uuid, 'BANKUTR4444', 129)->>'already')::boolean,
            'marking twice is idempotent');
select t.ok((select verification_source = 'admin' and reviewed_by = t.id('owner')
               from public.payment_orders where id = t.get('o4')::uuid), '… recorded as admin + reviewer');
select t.ok(t.plan_end('ads_user') between t.get('end1')::timestamptz + interval '6 days 23 hours'
                                       and t.get('end1')::timestamptz + interval '7 days 1 hour',
            'plans stack: new expiry = current expiry + 7 days');
select t.ok((select count(*) from public.subscriptions where user_id = t.id('ads_user')) = 2, '… one grant per paid order');

select public.admin_revoke_payment(t.get('o4')::uuid, 'not in bank statement');
select public.admin_revoke_payment(t.get('o2')::uuid, 'not in bank statement');
select t.ok(t.order_status('o2') = 'revoked' and t.order_status('o4') = 'revoked', 'owner revokes payments');
select t.fails($$select public.admin_revoke_payment(t.get('o3')::uuid)$$, 'only approved payments can be revoked');
select t.act_as('ads_user');
select t.ok(not public.is_premium_user(), 'revoked payments remove access');
select t.ok((public.report_payment_result(t.get('o2')::uuid, 'Status=SUCCESS&ApprovalRefNo=627312345678')->>'status') = 'revoked',
            'a revoked order cannot be re-activated from the app');

-- Provider hook (service role).
select t.put('o5', public.create_payment_order((select id from public.plans where code = 'trial'))->>'order_id');
set role service_role;
select t.fails($$select public.provider_confirm_payment((select reference from public.payment_orders where id = t.get('o5')::uuid), 100, 'PROV55555')$$,
               'provider hook checks the amount');
select t.ok((public.provider_confirm_payment((select reference from public.payment_orders where id = t.get('o5')::uuid), 6900, 'PROV55555')->>'status') = 'approved',
            'provider hook activates with source provider_api');
reset role;
select t.ok((select verification_source from public.payment_orders where id = t.get('o5')::uuid) = 'provider_api',
            '… recorded as provider_api');

-- Auto-cancel after 24 h.
set role authenticated;
select t.act_as('organic_user');
select t.put('o6', public.create_payment_order((select id from public.plans where code = 'gold'))->>'order_id');
reset role;
update public.payment_orders set created_at = now() - interval '25 hours' where id = t.get('o6')::uuid;
select public.cancel_stale_payment_orders();
select t.ok(t.order_status('o6') = 'cancelled', 'orders open for more than 24 hours are cancelled');

-- ---------------------------------------------------------------------------
-- Admin creating a channel from the app → approval request
-- ---------------------------------------------------------------------------
set role authenticated;
select t.act_as('owner');
insert into public.channels (name) values ('Owner app channel');
select t.ok((select review_status = 'pending' and status = 'draft' and created_by = t.id('owner')
               from public.channels where name = 'Owner app channel'),
            'admin creating a channel from the app makes a pending request with them as creator');
select t.ok(exists (select 1 from public.admin_channel_requests() where name = 'Owner app channel'),
            '… and it shows in the owner''s channel requests');
select public.review_channel((select id from public.channels where name = 'Owner app channel'), true, 'all');
select t.ok((select review_status = 'approved' and status = 'published'
               from public.channels where name = 'Owner app channel'), '… and the owner can approve it');
insert into public.channels (name, created_by, status, audience) values ('Panel channel', t.id('owner'), 'published', 'ads');
select t.ok((select review_status = 'approved' and status = 'published' and audience = 'ads'
               from public.channels where name = 'Panel channel'),
            'admin panel channels (with created_by) are unchanged');
reset role;

-- ---------------------------------------------------------------------------
-- Meta Pixel / Conversions API events
-- ---------------------------------------------------------------------------
-- Disabled by default: nothing is queued.
insert into public.installs (install_id, referrer_status, source) values (gen_random_uuid(), 'apk', 'meta');
select t.ok((select count(*) from public.meta_events) = 0, 'no Meta events while tracking is off');

update public.meta_settings set pixel_id = '1234567890', access_token = 'TEST_TOKEN', enabled = true where id = 1;
insert into public.installs (install_id, referrer_status, source) values ('99999999-0000-0000-0000-000000000001', 'apk', 'meta');
select t.ok((select count(*) from public.meta_events where event_name = 'AppInstall') = 1, 'install → AppInstall');

insert into auth.users (id, email, is_anonymous) values ('99999999-0000-0000-0000-0000000000aa', null, true);
update auth.users set email = 'Buyer@Example.com', is_anonymous = false where id = '99999999-0000-0000-0000-0000000000aa';
select t.ok((select count(*) from public.meta_events where event_name = 'CompleteRegistration'
               and user_id = '99999999-0000-0000-0000-0000000000aa') = 1, 'guest → account = CompleteRegistration');

set role authenticated;
select t.act_as('ads_user');
select public.log_event('99999999-0000-0000-0000-000000000001', 'content_view',
                        '20000000-0000-0000-0000-000000000001', gen_random_uuid());
select t.ok(not exists (select 1 from public.meta_events), 'app users cannot read Meta events');
select t.ok(not exists (select 1 from public.meta_settings), 'app users cannot read the Meta token');
select t.fails($$select public.meta_dispatch()$$, 'app users cannot run the sender');
select t.put('mo', public.create_payment_order((select id from public.plans where code = 'gold'))->>'order_id');
reset role;
select t.ok((select count(*) from public.meta_events where event_name = 'ViewContent') = 1, 'content view → ViewContent');
select t.ok((select custom_data->>'value' from public.meta_events where event_name = 'InitiateCheckout'
               and event_id = 'checkout-' || t.get('mo')) = '259.00', 'payment order → InitiateCheckout with plan price');

set role authenticated;
select t.act_as('owner');
select public.admin_mark_payment_paid(t.get('mo')::uuid, 'METAUTR12345', 259);
select public.admin_mark_payment_paid(t.get('mo')::uuid, 'METAUTR12345', 259);
reset role;
select t.ok((select count(*) from public.meta_events where event_id = 'purchase-' || t.get('mo')) = 1
            and (select count(*) from public.meta_events where event_id = 'subscribe-' || t.get('mo')) = 1,
            'approved payment → one Purchase + one Subscribe (no duplicates)');
select t.ok((select p->'custom_data'->>'value' = '259.00' and p->'custom_data'->>'currency' = 'INR'
                    and p->>'action_source' = 'app' and p->'app_data'->'extinfo'->>1 = 'com.cloudstorage.app'
                    and jsonb_array_length(p->'user_data'->'external_id') = 1
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'purchase-' || t.get('mo')) x),
            'Purchase payload has value, INR, app data and hashed user id');
select t.ok((select public.meta_event_payload(e, s)->'user_data'->'em'->>0
               from public.meta_events e, public.meta_settings s
              where e.event_name = 'CompleteRegistration' and e.user_id = '99999999-0000-0000-0000-0000000000aa')
            = encode(sha256(convert_to('buyer@example.com', 'UTF8')), 'hex'),
            'email is sent only as a lower-cased SHA-256 hash');
select t.ok(public.meta_dispatch() = 0, 'sender is a no-op without pg_net (local tests)');
set role authenticated;
select t.act_as('owner');
select t.ok((select count(*) from public.admin_meta_events()) >= 5, 'owner sees the event log');
reset role;

-- Meta ROAS: download page click → install → purchase carries fbc/fbp/IP
set role anon;
select t.ok((public.download_page_config()->>'pixel_id') = '1234567890', 'download page gets the Pixel id');
select t.ok(not (public.download_page_config() ? 'access_token'), 'download page never gets the token');
select t.ok(public.record_ad_click('lead-evt-1', 'fb.1.1700000000000.ABCclick', 'fb.1.1700000000000.123',
                                   '203.0.113.7', 'Mozilla/5.0 (Linux; Android 14)') is not null, 'download tap is recorded');
reset role;
select t.ok((select count(*) from public.meta_events where event_id = 'lead-evt-1' and event_name = 'Lead') = 1,
            'download tap → Lead (same event id as the browser Pixel)');
select set_config('request.headers', '{"x-forwarded-for": "203.0.113.7, 10.0.0.1", "user-agent": "Dart/3.9"}', false);
set role authenticated;
select t.act_as('ads_user');
select public.record_install('99999999-0000-0000-0000-0000000000c1', 'apk', 'utm_source=meta');
select t.put('ro', public.create_payment_order((select id from public.plans where code = 'silver'))->>'order_id');
reset role;
select set_config('request.headers', '', false);
select t.ok((select fbc from public.installs where install_id = '99999999-0000-0000-0000-0000000000c1')
            = 'fb.1.1700000000000.ABCclick', 'app install is matched to the ad click by IP');
select t.ok((select install_id from public.ad_clicks where event_id = 'lead-evt-1')
            = '99999999-0000-0000-0000-0000000000c1', 'click is marked as matched');
set role authenticated;
select t.act_as('owner');
select public.admin_mark_payment_paid(t.get('ro')::uuid, 'ROASUTR12345', 129);
reset role;
select t.ok((select p->'user_data'->>'fbc' = 'fb.1.1700000000000.ABCclick'
                    and p->'user_data'->>'fbp' = 'fb.1.1700000000000.123'
                    and p->'user_data'->>'client_ip_address' = '203.0.113.7'
                    and p->'user_data'->>'client_user_agent' like 'Mozilla%'
                    and p->'custom_data'->>'value' = '129.00'
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'purchase-' || t.get('ro')) x),
            'Purchase carries the ad click (fbc, fbp, IP, browser) and value');
select set_config('request.headers', '{"x-forwarded-for": "198.51.100.9"}', false);
insert into public.installs (install_id, referrer_status, source) values ('99999999-0000-0000-0000-0000000000c2', 'apk', 'meta');
select set_config('request.headers', '', false);
select t.ok((select ad_click_id is null from public.installs where install_id = '99999999-0000-0000-0000-0000000000c2'),
            'installs from other networks are not matched');
set role authenticated;
select t.act_as('owner');
select t.ok((public.admin_meta_health()->>'matched_7d')::int = 1, 'owner sees attribution health');
select t.act_as('ads_user');
select t.fails($$select public.admin_meta_health()$$, 'app users cannot see attribution health');
select t.ok(not exists (select 1 from public.ad_clicks), 'app users cannot read ad clicks');
reset role;

-- Admin: channel creators
set role authenticated;
select t.act_as('owner');
select t.ok((select email from public.admin_channel_creators() a join public.channels c on c.id = a.channel_id
              where c.name = 'Owner app channel') = 'owner@example.com', 'admins see who created each channel');
select t.act_as('ads_user');
select t.fails($$select * from public.admin_channel_creators()$$, 'app users cannot see channel creators');
reset role;

-- Admin posting from the app into a restricted channel
set role authenticated;
select t.act_as('owner');
update public.channels set audience = 'ads' where name = 'Owner app channel';
insert into public.posts (channel_id, title, status)
  select id, 'Owner app post', 'published' from public.channels where name = 'Owner app channel';
select t.ok((select audience = 'ads' and created_by = t.id('owner') and published_at is not null
               from public.posts where title = 'Owner app post'),
            'admin posting from the app gets the channel audience and is the creator');
insert into public.post_items (post_id, kind, media_key, processing_status)
  select id, 'video', 'posts/x/owner.mp4', 'ready' from public.posts where title = 'Owner app post';
select t.ok((select is_premium from public.post_items where media_key = 'posts/x/owner.mp4'),
            'app uploads are premium by default');
insert into public.posts (channel_id, title, audience, status, created_by)
  select id, 'Panel post', 'ads', 'draft', t.id('owner') from public.channels where name = 'Owner app channel';
select t.fails($$insert into public.posts (channel_id, title, audience, created_by)
                 select id, 'Panel wrong', 'all', t.id('owner') from public.channels where name = 'Owner app channel'$$,
               'admin panel posts still must match the channel audience');
reset role;

-- Payments reports (owner only)
set role authenticated;
select t.act_as('content_admin');
select t.fails($$select * from public.admin_buyers()$$, 'content admin cannot list buyers');
select t.fails($$select * from public.admin_plan_sales()$$, 'content admin cannot see plan sales');
select t.act_as('owner');
select t.ok((select count(*) from public.admin_payment_orders_filtered('all')) =
            (select count(*) from public.admin_payment_orders('all')), 'filtered orders: all matches');
select t.ok((select count(*) from public.admin_payment_orders_filtered('all',
               (select id from public.plans where code = 'silver'))) =
            (select count(*) from public.payment_orders where plan_id = (select id from public.plans where code = 'silver')),
            'filtered orders: by plan');
select t.ok((select count(*) from public.admin_payment_orders_filtered('all', null, null, now() + interval '1 day')) = 0,
            'filtered orders: date range');
select t.ok((select amount_paise from public.admin_payment_orders_filtered('all', null, null, null, null, 'amount_desc') limit 1) =
            (select max(amount_paise) from public.payment_orders), 'filtered orders: sort by amount');
select t.ok((select sum(purchases) from public.admin_plan_sales()) =
            (select count(*) from public.payment_orders where status = 'approved'), 'plan sales count approved purchases');
select t.ok((select sum(purchases) from public.admin_buyers()) =
            (select count(*) from public.payment_orders where status = 'approved'), 'buyers cover every purchase');
select t.ok((select bool_and(jsonb_array_length(history) = purchases) from public.admin_buyers()), 'buyer history lists every purchase');
select t.ok((select count(*) from public.admin_buyers(2)) =
            (select count(*) from (select user_id from public.payment_orders where status = 'approved'
                                    group by user_id having count(*) > 1) x), 'repeat buyers filter');
reset role;

-- Google Play alternative billing reporting (Play build)
set role authenticated;
select t.act_as('ads_user');
select t.put('po', public.create_payment_order((select id from public.plans where code = 'gold'))->>'order_id');
select t.fails($$select public.attach_play_token(t.get('po')::uuid, 'x')$$, 'too-short Play token is rejected');
select public.attach_play_token(t.get('po')::uuid, 'GOOGLE-EXTERNAL-TOKEN-123');
select t.fails($$select public.attach_play_token(t.get('po')::uuid, 'GOOGLE-EXTERNAL-TOKEN-456')$$, 'token cannot be replaced');
select t.act_as('organic_user');
select t.fails($$select public.attach_play_token(t.get('o1')::uuid, 'GOOGLE-EXTERNAL-TOKEN-789')$$,
               'cannot attach a token to someone else''s order');
select t.fails($$select public.admin_play_report_summary()$$, 'app users cannot see Play reporting');
select t.act_as('owner');
select public.admin_mark_payment_paid(t.get('po')::uuid, 'PLAYUTR123456', 259);
reset role;
select t.ok((select play_report_status from public.payment_orders where id = t.get('po')::uuid) = 'pending',
            'approved Play-build payment is queued for the Google report');
select t.ok((select count(*) from public.payment_orders where play_report_status is not null and play_token is null) = 0,
            'direct-APK payments are never reported');
update public.payment_orders set play_report_status = 'reported' where id = t.get('po')::uuid;
set role authenticated;
select t.act_as('owner');
select public.admin_revoke_payment(t.get('po')::uuid, 'test');
select t.ok((public.admin_play_report_summary()->>'pending')::int >= 1, 'owner sees pending Google reports');
select t.ok((select play_report_status from public.admin_play_report_rows(array[t.get('po')::uuid])) = 'refund_pending',
            'owner sees the report status per order');
reset role;
select t.ok((select play_report_status from public.payment_orders where id = t.get('po')::uuid) = 'refund_pending',
            'revoking a reported payment queues a refund report');

-- Support requests (delete account / content reports)
select set_config('request.jwt.claim.sub', '', false);
set role anon;
select t.ok(public.submit_support_request('delete_account', ' Ads@Example.com ') is not null, 'anyone can request account deletion');
select t.fails($$select public.submit_support_request('delete_account', 'not-an-email')$$, 'email is validated');
select t.fails($$select public.submit_support_request('content_report', 'a@b.co')$$, 'report needs details');
select t.ok(public.submit_support_request('content_report', 'r@b.co', 'R', 'https://x', 'My video') is not null, 'anyone can report content');
select t.ok(not exists (select 1 from public.support_requests), 'visitors cannot read requests');
reset role;
set role authenticated;
select t.act_as('ads_user');
select t.fails($$select public.admin_close_support_request((select id from public.support_requests limit 1), 'done')$$,
               'app users cannot close requests');
select t.act_as('owner');
select t.ok(public.admin_open_support_requests() = 2, 'owner sees open requests');
select public.admin_close_support_request((select id from public.support_requests where kind = 'content_report'), 'done', 'removed');
select t.ok(public.admin_open_support_requests() = 1, 'owner can close a request');
reset role;

-- In-app reports
set role authenticated;
select t.act_as('ads_user');
select t.ok(public.report_content_in_app((select id from public.posts limit 1), null, 'Copyright') is not null, 'users can report a post in the app');
select t.ok(public.report_content_in_app(null, (select id from public.channels limit 1), 'Spam', 'details') is not null, 'users can report a channel');
select t.fails($$select public.report_content_in_app(null, null, 'Spam')$$, 'report needs a target');
select t.fails($$select public.report_content_in_app((select id from public.posts limit 1), null, '')$$, 'report needs a reason');
reset role;
select t.ok((select count(*) from public.support_requests where name = 'In-app report') = 2, 'in-app reports reach the admin Requests');

-- Google Play version: 15 GB free cloud after login (Premium stays 2 TB)
set role authenticated;
select t.act_as('organic_guest');
select public.enable_play_free_cloud();
select t.ok((public.my_status()->>'quota_bytes')::bigint = 0, 'guests get no free cloud');
select t.act_as('organic_user');
select t.fails($$insert into public.cloud_files (name, is_folder) values ('Free', true)$$,
               'without the Play allowance, free users still cannot use cloud');
select public.enable_play_free_cloud();
select t.ok((public.my_status()->>'quota_bytes')::bigint = 16106127360, 'Play users get 15 GB');
select t.ok(not (public.my_status()->>'is_premium')::boolean, 'free cloud does not make the user premium');
insert into public.cloud_files (id, name, is_folder) values ('50000000-0000-0000-0000-000000000002', 'Free', true);
insert into public.cloud_files (parent_id, name, storage_key, mime, size)
values ('50000000-0000-0000-0000-000000000002', 'b.pdf', t.id('organic_user') || '/1-b.pdf', 'application/pdf', 2000);
insert into storage.objects (bucket_id, name) values ('cloud', t.id('organic_user') || '/1-b.pdf');
select t.fails($$insert into public.cloud_files (name, storage_key, mime, size)
                 values ('big.bin', t.id('organic_user') || '/2-big.bin', 'application/octet-stream', 16106127360)$$,
               'the 15 GB limit is enforced');
select public.enable_play_free_cloud();
select t.ok((select used_bytes from public.profiles where id = t.id('organic_user')) = 2000, 'calling it again changes nothing');
select t.act_as('owner');
select public.grant_premium(t.id('organic_user'), 'gold');
select t.act_as('organic_user');
select t.ok((public.my_status()->>'quota_bytes')::bigint = 2199023255552, 'premium users get 2 TB, not 15 GB');
reset role;

-- Free mode: no plans; ads users (and approved organic users) get full access,
-- organic users ask for it; everyone logged in gets 15 GB of cloud.
delete from public.subscriptions;
update public.profiles set ads_access_status = 'none', free_cloud_bytes = 0
 where id in (t.id('organic_user'), t.id('ads_user'));
update public.app_mode set free_mode = true;
set role authenticated;
select t.act_as('ads_user');
select t.ok(public.is_premium_user(), 'free mode: ads users get full access without a plan');
select t.ok((public.my_status()->>'quota_bytes')::bigint = 16106127360, 'free mode: 15 GB cloud');
select t.ok((public.my_status()->>'free_mode')::boolean, 'status says free mode');
select t.act_as('organic_user');
select t.ok(not public.is_premium_user(), 'free mode: organic users need approval for full content');
select t.ok((public.my_status()->>'quota_bytes')::bigint = 16106127360, 'free mode: organic users get 15 GB cloud too');
insert into public.cloud_files (name, is_folder) values ('Mine', true);
select t.ok(public.request_full_access() = 'pending', 'organic user can ask for full access');
select t.ok(public.request_full_access() = 'pending', 'asking again keeps it pending');
select t.act_as('organic_guest');
select t.ok(not public.is_premium_user(), 'guests have no full access');
select t.ok((public.my_status()->>'quota_bytes')::bigint = 0, 'guests have no cloud');
select t.fails($$select public.request_full_access()$$, 'guests must log in to ask');
select t.act_as('owner');
select public.set_ads_access(t.id('organic_user'), 'approved');
select t.act_as('organic_user');
select t.ok(public.is_premium_user(), 'approved organic users get full access');
select t.ok(public.request_full_access() = 'approved', 'approved users see approved');
update public.app_mode set free_mode = false;  -- RLS: matches no rows for app users
reset role;
select t.ok((select free_mode from public.app_mode) , 'free mode unchanged by app users');
\echo
\echo 'All tests passed.'
