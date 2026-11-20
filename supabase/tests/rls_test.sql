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
-- Referrers Meta itself adds to Play installs from App promotion (app install) ads.
select t.ok(public.parse_source('ok', 'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A123%2C%22t%22%3A1700000000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D') = 'meta',
            'Meta app install ad (Facebook) → meta');
select t.ok(public.parse_source('ok', 'utm_source=apps.instagram.com&utm_campaign=ig4a&utm_content=%7B%22app%22%3A123%7D') = 'meta',
            'Meta app install ad (Instagram) → meta');
select t.ok(public.parse_source('ok', 'utm_source%3Dapps.facebook.com%26utm_campaign%3Dfb4a') = 'meta',
            'url-encoded Meta app install referrer → meta');

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

-- Referrer retry: a Play install whose first referrer read failed becomes an
-- ads user when the app retries the SAME install and gets the ad referrer.
insert into t.ids values ('retry_guest', '00000000-0000-0000-0000-0000000000a1'),
                         ('retry_other', '00000000-0000-0000-0000-0000000000a2');
insert into auth.users (id, email, is_anonymous) values
  (t.id('retry_guest'), null, true), (t.id('retry_other'), null, true);
set role authenticated;
select t.act_as('retry_guest');
select public.record_install('30000000-0000-0000-0000-0000000000a1', 'not_available');
select t.ok(public.user_source() = 'organic', 'retry: failed first read -> organic for now');
select public.record_install('30000000-0000-0000-0000-0000000000a1', 'ok',
       'utm_source=meta&utm_medium=paid_social&utm_campaign=c1');
select t.ok(public.user_source() = 'ads', 'retry: same install, successful read -> ads user');
select public.record_install('30000000-0000-0000-0000-0000000000a1', 'ok', 'utm_source=google-play&utm_medium=organic');
select t.ok(public.user_source() = 'ads', 'retry: the first successful read is kept');
-- A different install never upgrades an organic first touch.
select t.act_as('retry_other');
select public.record_install('30000000-0000-0000-0000-0000000000a2', 'not_available');
select public.record_install('30000000-0000-0000-0000-0000000000a3', 'ok', 'utm_source=meta');
select t.ok(public.user_source() = 'organic', 'retry: another install cannot change the first touch');
reset role;
select t.ok((select first_touch_campaign from public.user_attribution where user_id = t.id('retry_guest')) = 'c1',
            'retry: campaign carried into first touch');
select t.fails($$update public.user_attribution set first_touch_source = 'meta'
                  where user_id = t.id('retry_other')$$,
               'retry: a direct update of a failed-read first touch is still refused');
-- Keep the user counts below unchanged.
delete from auth.users where id in (t.id('retry_guest'), t.id('retry_other'));
delete from public.installs where install_id in ('30000000-0000-0000-0000-0000000000a1',
  '30000000-0000-0000-0000-0000000000a2', '30000000-0000-0000-0000-0000000000a3');

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
select t.fails($$select public.set_ads_access(t.id('organic_buyer'), 'approved')$$,
               'organic users can no longer be approved for ads content');
reset role;
update public.profiles set ads_access_status = 'approved' where id = t.id('organic_buyer');  -- an old approval
set role authenticated;
select t.act_as('organic_buyer');
select t.ok(t.visible_titles() = 'all/all,all/organic,org/org',
            'an old approval gives no ads content');

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
select t.ok(coalesce((select buyers from public.attribution_report() where source = 'direct'), 0) = 0,
            'report: a free plan granted by an admin is not a purchase (buyers come from paid orders)');

reset role;

-- ---------------------------------------------------------------------------
-- Admin panel read models
-- ---------------------------------------------------------------------------
set role authenticated;
select t.act_as('organic_user');
select t.fails($$select * from public.admin_users()$$, 'app users cannot list users');
select t.fails($$select public.admin_user_stats()$$, 'app users cannot read user reports');
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
select t.ok((select max(total_count) from public.admin_users('all', null, 2)) = 5,
            'user list reports the total number of matches for paging');
select t.ok((select count(*) from public.admin_users('all', null, 2)) = 2, 'user list pages');
select t.ok((select count(*) from public.admin_users('premium')) = (public.admin_user_stats()->>'active_subscribers')::int,
            'premium filter matches the active subscriber count');
select t.ok((select count(*) from public.admin_users('all', null, 50, 0, now() + interval '1 day', null)) = 0,
            'sign-up date range filters users');
select t.ok((select count(*) from public.admin_users('registered')) + (select count(*) from public.admin_users('guest')) = 5,
            'registered + guest = all users');
select t.ok((public.admin_user_stats()->>'all_users')::int = 5
            and (public.admin_user_stats()->>'new_users')::int = 5
            and (public.admin_user_stats(now() + interval '1 day', null)->>'new_users')::int = 0,
            'user stats count users in a date range');
select t.ok(jsonb_array_length(public.admin_user_stats()->'by_plan') = (select count(*) from public.plans),
            'user stats break subscribers down per plan');
select t.ok((select array_agg(id order by created_at) from public.admin_users('all', null, 50, 0, null, null, 'oldest'))[1]
              = (select id from public.profiles p where not exists (select 1 from public.admins a where a.user_id = p.id)
                  order by created_at limit 1),
            'oldest-first sort');
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

-- Bunny-backed cloud files (storage_key and bunny_path are mutually exclusive)
select t.fails($$insert into public.cloud_files (name, storage_key, bunny_path, mime, size)
                 values ('both.pdf', t.id('ads_user') || '/x', t.id('ads_user') || '/y', 'application/pdf', 1)$$,
               'a cloud file cannot have both a storage_key and a bunny_path');
select t.fails($$insert into public.cloud_files (name, is_folder, bunny_path) values ('Bad', true, t.id('ads_user') || '/y')$$,
               'a folder cannot have a bunny_path');
insert into public.cloud_files (id, name, is_folder) values ('50000000-0000-0000-0000-000000000003', 'Bunny', true);
insert into public.cloud_files (parent_id, name, bunny_path, mime, size)
values ('50000000-0000-0000-0000-000000000003', 'b.pdf', t.id('ads_user') || '/2-b.pdf', 'application/pdf', 2000);
select t.ok((select used_bytes from public.profiles where id = t.id('ads_user')) = 2000,
            'bunny-backed files count toward used_bytes the same way');
select t.ok((select count(*) from public.cloud_folder_bunny_paths('50000000-0000-0000-0000-000000000003')) = 1,
            'folder bunny paths include nested files');
delete from public.cloud_files where id = '50000000-0000-0000-0000-000000000003';
select t.ok((select used_bytes from public.profiles where id = t.id('ads_user')) = 0,
            'deleting a bunny-backed folder frees its space too');

-- Plan requests
select t.act_as('ads_guest');
select t.fails($$insert into public.plan_requests (plan_id) select id from public.plans where code = 'gold'$$,
               'guests must log in before requesting a plan');
select t.act_as('organic_user');
insert into public.plan_requests (plan_id) select id from public.plans where code = 'gold';
select t.ok(public.my_status()->>'open_request' = 'Gold Plan', 'status shows the open request');
select t.act_as('owner');
select t.ok((select count(*) from public.admin_plan_requests()) = 1, 'owner sees open plan requests');

-- A registered but non-premium user cannot create a channel yet.
select t.act_as('organic_user');
select t.fails($$insert into public.channels (name) values ('Too early')$$,
               'a free (non-premium) user cannot create a channel');

select t.act_as('owner');
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

-- Followers shown in the app: set by the admin, real joins still add/remove one.
select public.admin_set_followers('60000000-0000-0000-0000-000000000001', 5000);
select t.ok((select members_count from public.channels where id = '60000000-0000-0000-0000-000000000001') = 5000,
            'admin sets the followers shown');
select t.act_as('ads_user');
insert into public.channel_members (channel_id, user_id)
values ('60000000-0000-0000-0000-000000000001', t.id('ads_user'));
select t.ok((select members_count from public.channels where id = '60000000-0000-0000-0000-000000000001') = 5001,
            'a join adds one to the admin number');
delete from public.channel_members
 where channel_id = '60000000-0000-0000-0000-000000000001' and user_id = t.id('ads_user');
select t.ok((select members_count from public.channels where id = '60000000-0000-0000-0000-000000000001') = 5000,
            'a leave removes one again');
select t.fails($$select public.admin_set_followers('60000000-0000-0000-0000-000000000001', 99999)$$,
               'app users cannot set followers');
select t.act_as('organic_user');
update public.channels set members_count = 123456, followers_offset = 123456
 where id = '60000000-0000-0000-0000-000000000001';
select t.act_as('owner');
select t.ok((select members_count || '/' || followers_offset from public.channels
              where id = '60000000-0000-0000-0000-000000000001') = '5000/4999',
            'creator cannot change followers or the offset');
select t.fails($$select public.admin_set_followers('60000000-0000-0000-0000-000000000001', -1)$$,
               'followers cannot be negative');
-- Back to the real count (1: the creator) for the tests below.
select public.admin_set_followers('60000000-0000-0000-0000-000000000001', 1);
select t.ok((select followers_offset from public.channels where id = '60000000-0000-0000-0000-000000000001') = 0,
            'setting the real count clears the offset');

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
-- Guest checkout: a guest can buy a plan too, without signing up first.
select t.act_as('ads_guest');
select t.put('go', public.create_payment_order((select id from public.plans where code = 'gold'))->>'order_id');
select t.ok((select user_id from public.payment_orders where id = t.get('go')::uuid) = t.id('ads_guest'),
            'a guest can create a payment order tied to their own (guest) account');
select t.ok((public.report_payment_result(t.get('go')::uuid, 'Status=SUCCESS&ApprovalRefNo=627312300099')->>'status') = 'approved',
            'a guest can complete checkout and become premium without signing up');
select t.ok(public.is_premium_user(), 'the guest is premium right after paying');

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
select t.ok((select count(*) from public.admin_payment_orders('all')) = 5, 'owner sees all orders');
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
-- Meta counts an install only under its own name; the installation ID ties
-- later events of the same phone to it.
select t.ok((select count(*) from public.meta_events where event_name = 'MobileAppInstall'
               and event_id = 'mobile-install-99999999-0000-0000-0000-000000000001') = 1,
            'install → Meta''s standard MobileAppInstall as well');
select t.ok((select p->>'event_name' = 'MobileAppInstall' and p->>'action_source' = 'app'
                    and not (p ? 'custom_data')
                    and p->'user_data'->>'anon_id' = '99999999-0000-0000-0000-000000000001'
                    and not (p->'app_data' ? 'install_referrer')
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'mobile-install-99999999-0000-0000-0000-000000000001') x),
            'MobileAppInstall: installation ID, no empty custom data, no referrer without a Play ad install');
select t.ok((select p->'user_data'->>'anon_id' = '99999999-0000-0000-0000-000000000001'
                    and p->'custom_data'->>'source' = 'meta'
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'install-99999999-0000-0000-0000-000000000001') x),
            'AppInstall is still sent, now with the installation ID');
insert into public.installs (install_id, referrer_status, source, raw_referrer) values
  ('99999999-0000-0000-0000-0000000000d1', 'ok', 'meta', 'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D'),
  ('99999999-0000-0000-0000-0000000000d2', 'ok', 'organic', 'utm_source=google-play&utm_medium=organic');
select t.ok((select p->'app_data'->>'install_referrer' = 'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D'
                    and p->'app_data'->>'installer_package' = 'com.android.vending'
                    and p->'user_data'->>'anon_id' = '99999999-0000-0000-0000-0000000000d1'
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'mobile-install-99999999-0000-0000-0000-0000000000d1') x),
            'Meta ad install from Google Play passes Meta''s click reference back');
select t.ok((select not (p->'app_data' ? 'install_referrer') and not (p->'app_data' ? 'installer_package')
                    and p->'user_data'->>'anon_id' = '99999999-0000-0000-0000-0000000000d2'
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'mobile-install-99999999-0000-0000-0000-0000000000d2') x),
            'an organic Play install sends no referrer to Meta');
update public.meta_settings set action_source = 'website' where id = 1;
insert into public.installs (install_id, referrer_status, source) values ('99999999-0000-0000-0000-0000000000d3', 'apk', 'meta');
select t.ok(exists (select 1 from public.meta_events where event_id = 'install-99999999-0000-0000-0000-0000000000d3')
            and not exists (select 1 from public.meta_events where event_id = 'mobile-install-99999999-0000-0000-0000-0000000000d3'),
            'website mode: no MobileAppInstall');
select t.ok((select not (p->'user_data' ? 'anon_id') and not (p ? 'app_data') and p ? 'event_source_url'
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'install-99999999-0000-0000-0000-0000000000d3') x),
            'website mode: no app-only fields');
update public.meta_settings set action_source = 'app' where id = 1;
delete from public.meta_events where install_id in ('99999999-0000-0000-0000-0000000000d1',
  '99999999-0000-0000-0000-0000000000d2', '99999999-0000-0000-0000-0000000000d3');
delete from public.installs where install_id in ('99999999-0000-0000-0000-0000000000d1',
  '99999999-0000-0000-0000-0000000000d2', '99999999-0000-0000-0000-0000000000d3');

insert into auth.users (id, email, is_anonymous) values ('99999999-0000-0000-0000-0000000000aa', null, true);
update auth.users set email = 'Buyer@Example.com', is_anonymous = false where id = '99999999-0000-0000-0000-0000000000aa';
select t.ok((select count(*) from public.meta_events where event_name = 'CompleteRegistration'
               and user_id = '99999999-0000-0000-0000-0000000000aa') = 1, 'guest → account = CompleteRegistration');

-- An account that never was a guest (first Google sign-in without linking)
-- reports its sign-up at its first login; old accounts and admins do not.
insert into auth.users (id, email, is_anonymous, created_at) values
  ('99999999-0000-0000-0000-0000000000bb', 'direct@example.com', false, now()),
  ('99999999-0000-0000-0000-0000000000cc', 'old@example.com', false, now() - interval '3 days');
select t.ok(not exists (select 1 from public.meta_events where event_name = 'CompleteRegistration'
                           and event_id in ('register-99999999-0000-0000-0000-0000000000bb',
                                            'register-99999999-0000-0000-0000-0000000000cc')),
            'a direct account sends no sign-up before its first login');
set role authenticated;
select set_config('request.jwt.claim.sub', '99999999-0000-0000-0000-0000000000bb', false);
select public.attribute_user('99999999-0000-0000-0000-000000000001');
select public.attribute_user('99999999-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', '99999999-0000-0000-0000-0000000000cc', false);
select public.attribute_user('99999999-0000-0000-0000-000000000001');
select t.act_as('owner');
select public.attribute_user('99999999-0000-0000-0000-000000000001');
select set_config('request.jwt.claim.sub', '99999999-0000-0000-0000-0000000000aa', false);
select public.attribute_user('99999999-0000-0000-0000-000000000001');
reset role;
select t.ok((select count(*) from public.meta_events where event_name = 'CompleteRegistration'
               and event_id = 'register-99999999-0000-0000-0000-0000000000bb') = 1,
            'new direct account: first login → one CompleteRegistration');
select t.ok(not exists (select 1 from public.meta_events
                         where event_id = 'register-99999999-0000-0000-0000-0000000000cc'),
            'an older account logging in sends no sign-up');
select t.ok(not exists (select 1 from public.meta_events where event_id = 'register-' || t.id('owner')),
            'an admin logging in sends no sign-up');
select t.ok((select count(*) from public.meta_events where event_name = 'CompleteRegistration'
               and user_id = '99999999-0000-0000-0000-0000000000aa') = 1,
            'a guest who became an account still sends exactly one sign-up');
delete from public.user_attribution where user_id in ('99999999-0000-0000-0000-0000000000aa', t.id('owner'));
delete from auth.users where id in ('99999999-0000-0000-0000-0000000000bb', '99999999-0000-0000-0000-0000000000cc');
delete from public.meta_events where event_id = 'register-99999999-0000-0000-0000-0000000000bb';

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
                    and p->>'action_source' = 'app' and p->'app_data'->'extinfo'->>1 = 'com.flixvault.app'
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
select public.admin_meta_test_event();
reset role;
select t.ok((select count(*) from public.meta_events where event_name = 'TestEvent') = 1
            and (select count(*) from public.meta_events where event_name = 'ViewContent') = 1,
            'the test button sends a TestEvent, not a ViewContent');

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
                    and p->'user_data'->>'anon_id' = '99999999-0000-0000-0000-0000000000c1'
                    and p->'custom_data'->>'value' = '129.00'
               from (select public.meta_event_payload(e, s) p
                       from public.meta_events e, public.meta_settings s
                      where e.event_id = 'purchase-' || t.get('ro')) x),
            'Purchase carries the ad click (fbc, fbp, IP, browser), the installation ID and value');
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
select t.fails($$select public.admin_payment_orders_totals()$$, 'content admin cannot see order totals');
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
select t.ok((select count(*) from public.admin_payment_orders_list('all')) =
            (select count(*) from public.payment_orders), 'orders list: all orders');
select t.ok((select bool_and(admin_test = public.is_admin_user(user_id)) from public.admin_payment_orders_list('all')),
            'orders list: admin test orders are marked');
select t.ok((public.admin_payment_orders_totals('all')->>'orders')::int =
            (select count(*) from public.payment_orders), 'order totals: count every order');
select t.ok((public.admin_payment_orders_totals('success')->>'received_paise')::bigint =
            (select coalesce(sum(amount_paise), 0) from public.payment_orders o
              where o.status = 'approved' and not public.is_admin_user(o.user_id)),
            'order totals: received leaves admin test payments out');
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

-- Bunny Stream videos: same visibility + premium rule as legacy media_key
-- items, checked by item id so the raw video id is never read back to anyone
-- who shouldn't have it.
insert into t.ids values ('bunny_nonpremium_user', '90000000-0000-0000-0000-000000000001');
insert into auth.users (id, email, is_anonymous) values
  (t.id('bunny_nonpremium_user'), null, true);

select t.fails($$insert into public.post_items (post_id, kind, is_premium, processing_status)
                 values ('20000000-0000-0000-0000-000000000001', 'video', false, 'ready')$$,
               'a post item needs either a media_key or a bunny_video_id');

insert into public.post_items (id, post_id, kind, is_premium, bunny_video_id, processing_status) values
  ('90000000-0000-0000-0000-000000000010', '20000000-0000-0000-0000-000000000001', 'video', true,
   '90000000-0000-0000-0000-000000000011', 'ready'),
  ('90000000-0000-0000-0000-000000000020', '20000000-0000-0000-0000-000000000001', 'video', false,
   '90000000-0000-0000-0000-000000000021', 'ready'),
  ('90000000-0000-0000-0000-000000000030', '20000000-0000-0000-0000-000000000006', 'video', false,
   '90000000-0000-0000-0000-000000000031', 'ready');  -- on the hidden post

set role authenticated;
select t.act_as('owner');
select t.ok(public.bunny_video_access('90000000-0000-0000-0000-000000000010'), 'admin can access any bunny video');
select t.ok(public.bunny_video_path('90000000-0000-0000-0000-000000000010') = '90000000-0000-0000-0000-000000000011',
             'admin gets the bunny video id back');

select t.act_as('bunny_nonpremium_user');
select t.ok(not public.bunny_video_access('90000000-0000-0000-0000-000000000010'),
             'non-premium user cannot access a premium bunny video');
select t.ok(public.bunny_video_access('90000000-0000-0000-0000-000000000020'),
             'non-premium user can access a free bunny video');
select t.fails($$select public.bunny_video_path('90000000-0000-0000-0000-000000000010')$$, 'Not allowed');
select t.ok(not public.bunny_video_access('90000000-0000-0000-0000-000000000030'),
             'a bunny video on a hidden post is not accessible');

select t.act_as('organic_user');  -- granted 'gold' premium above
select t.ok(public.bunny_video_access('90000000-0000-0000-0000-000000000010'),
             'premium user can access a premium bunny video');
reset role;

-- A freshly uploaded video must not stay invisible: the database clock (not the
-- uploader's computer clock) decides "publish now", and a post goes live as
-- soon as Bunny has finished encoding its video.
insert into public.posts (id, channel_id, title, audience, status)
select '91000000-0000-0000-0000-000000000001', channel_id, 'bulk upload', 'all', 'published'
  from public.posts where id = '20000000-0000-0000-0000-000000000001';
select t.ok((select published_at from public.posts where id = '91000000-0000-0000-0000-000000000001')
              between now() - interval '1 minute' and now() + interval '1 minute',
            'a published post with no time goes live now, by the database clock');
insert into public.post_items (id, post_id, kind, is_premium, bunny_video_id, processing_status) values
  ('91000000-0000-0000-0000-000000000010', '91000000-0000-0000-0000-000000000001', 'video', false,
   '91000000-0000-0000-0000-000000000011', 'pending');

set role authenticated;
select t.act_as('bunny_nonpremium_user');
select t.ok(not public.post_visible('91000000-0000-0000-0000-000000000001'),
            'a post whose video is still encoding is hidden from users');
select t.act_as('owner');
select t.ok(public.post_visible('91000000-0000-0000-0000-000000000001'),
            'an admin still sees a post whose video is encoding');
reset role;

update public.post_items set processing_status = 'ready' where id = '91000000-0000-0000-0000-000000000010';
set role authenticated;
select t.act_as('bunny_nonpremium_user');
select t.ok(public.post_visible('91000000-0000-0000-0000-000000000001'),
            'once Bunny finishes encoding, the post is visible to everyone allowed');
reset role;

insert into public.posts (id, channel_id, title, audience, status, published_at)
select '91000000-0000-0000-0000-000000000002', channel_id, 'scheduled', 'all', 'published', now() + interval '8 hours'
  from public.posts where id = '20000000-0000-0000-0000-000000000001';
insert into public.post_items (post_id, kind, is_premium, bunny_video_id, processing_status)
values ('91000000-0000-0000-0000-000000000002', 'video', false, '91000000-0000-0000-0000-000000000021', 'ready');
set role authenticated;
select t.act_as('bunny_nonpremium_user');
select t.ok(not public.post_visible('91000000-0000-0000-0000-000000000002'),
            'a post scheduled for later stays hidden until its time');
reset role;

select public.bunny_sync_tick();  -- must be a safe no-op when nothing is configured
select t.ok(true, 'bunny_sync_tick is safe when no function URL / pg_net is configured');

-- Search in Explore: narrows the list, never widens what a user may see.
set role authenticated;
select t.act_as('bunny_nonpremium_user');
select t.ok((select count(*) from public.explore('all', 30, 0, 'bulk upload')) = 1,
            'search finds a post by its title');
select t.ok((select count(*) from public.explore('all', 30, 0, 'BULK')) = 1,
            'search ignores case');
select t.ok((select count(*) from public.explore('all', 30, 0, 'everyone channel')) >= 1,
            'search finds posts by their channel name');
select t.ok((select count(*) from public.explore('all', 30, 0, 'hidden')) = 0,
            'search never returns a hidden post');
select t.ok((select count(*) from public.explore('all', 30, 0, 'scheduled')) = 0,
            'search never returns a scheduled post');
select t.ok((select count(*) from public.explore('all', 30, 0, 'processing')) = 0,
            'search never returns a post whose video is still encoding');
select t.ok((select count(*) from public.explore('all', 30, 0, '%')) = 0,
            'a % in the search is literal, not a wildcard');
select t.ok((select count(*) from public.explore('all', 30, 0, '')) = (select count(*) from public.explore('all', 30, 0)),
            'an empty search is the normal list');
select t.act_as('ads_user');
select t.ok((select count(*) from public.explore('all', 30, 0, 'all/ads')) = 1,
            'ads users find ads-audience posts by search');
select t.act_as('organic_user');
select t.ok((select count(*) from public.explore('all', 30, 0, 'all/ads')) = 0,
            'organic users never find ads-only posts by search');
reset role;

-- Trailers on Bunny: hidden until encoded, then same audience rule as legacy
-- trailers (+ plan holders), checked by item id.
update public.post_items
   set trailer_bunny_video_id = '91000000-0000-0000-0000-000000000031', trailer_status = 'pending'
 where id = '91000000-0000-0000-0000-000000000010';
select t.ok(not (select has_trailer from public.post_items where id = '91000000-0000-0000-0000-000000000010'),
            'a trailer still encoding is not offered');
set role authenticated;
select t.act_as('ads_user');
select t.fails($$select public.bunny_trailer_path('91000000-0000-0000-0000-000000000010')$$,
               'a trailer cannot be played before Bunny has finished encoding it');
reset role;

update public.post_items set trailer_status = 'ready' where id = '91000000-0000-0000-0000-000000000010';
select t.ok((select has_trailer from public.post_items where id = '91000000-0000-0000-0000-000000000010'),
            'an encoded Bunny trailer is offered');
set role authenticated;
select t.act_as('ads_user');
select t.ok(public.bunny_trailer_path('91000000-0000-0000-0000-000000000010') = '91000000-0000-0000-0000-000000000031',
            'ads users can play the trailer');
select t.act_as('organic_user');  -- holds a plan
select t.ok(public.bunny_trailer_path('91000000-0000-0000-0000-000000000010') = '91000000-0000-0000-0000-000000000031',
            'plan holders can play the trailer');
select t.act_as('owner');
select t.ok(public.bunny_trailer_path('91000000-0000-0000-0000-000000000010') = '91000000-0000-0000-0000-000000000031',
            'admins can play any trailer');
select t.act_as('bunny_nonpremium_user');
select t.fails($$select public.bunny_trailer_path('91000000-0000-0000-0000-000000000010')$$,
               'an organic user with no plan and no ads access cannot play the trailer');
select t.ok(not exists (select 1 from information_schema.column_privileges
                         where table_name = 'post_items' and column_name = 'trailer_bunny_video_id'
                           and grantee = 'authenticated' and privilege_type = 'SELECT'),
            'the Bunny trailer id is not readable by app users');
reset role;

-- Automatic preview: a premium video with no uploaded preview previews its
-- own start; an uploaded preview replaces it once encoded.
insert into public.post_items (id, post_id, kind, is_premium, bunny_video_id, processing_status) values
  ('91000000-0000-0000-0000-000000000040', '91000000-0000-0000-0000-000000000001', 'video', true,
   '91000000-0000-0000-0000-000000000041', 'ready');
insert into public.posts (id, channel_id, title, audience, status)
select '91000000-0000-0000-0000-000000000003', channel_id, 'encoding premium', 'all', 'published'
  from public.posts where id = '20000000-0000-0000-0000-000000000001';
insert into public.post_items (id, post_id, kind, is_premium, bunny_video_id, processing_status) values
  ('91000000-0000-0000-0000-000000000042', '91000000-0000-0000-0000-000000000003', 'video', true,
   '91000000-0000-0000-0000-000000000043', 'pending');
select t.ok((select has_trailer and auto_preview from public.post_items where id = '91000000-0000-0000-0000-000000000040'),
            'premium video without an uploaded preview gets the automatic preview');
select t.ok((select not has_trailer and not auto_preview from public.post_items where id = '91000000-0000-0000-0000-000000000042'),
            'no automatic preview while the main video is still encoding');
select t.ok((select not auto_preview from public.post_items where id = '91000000-0000-0000-0000-000000000010'),
            'free videos get no automatic preview');
set role authenticated;
select t.act_as('ads_user');
select t.ok(public.bunny_preview_info('91000000-0000-0000-0000-000000000040')
              = '{"video_id": "91000000-0000-0000-0000-000000000041", "auto": true}'::jsonb,
            'ads users get the automatic preview of the main video');
select t.ok(public.bunny_preview_info('91000000-0000-0000-0000-000000000010')
              = '{"video_id": "91000000-0000-0000-0000-000000000031", "auto": false}'::jsonb,
            'an uploaded preview is used as is');
select t.fails($$select public.bunny_preview_info('91000000-0000-0000-0000-000000000042')$$,
               'no preview for a video that is still encoding');
select t.act_as('organic_user');  -- holds a plan
select t.ok((public.bunny_preview_info('91000000-0000-0000-0000-000000000040')->>'auto')::boolean,
            'plan holders may open the automatic preview too');
select t.act_as('bunny_nonpremium_user');
select t.fails($$select public.bunny_preview_info('91000000-0000-0000-0000-000000000040')$$,
               'organic users with no plan and no ads access get no automatic preview');
select t.fails($$select public.bunny_video_path('91000000-0000-0000-0000-000000000040')$$,
               'the full premium video still needs a plan');
reset role;
update public.post_items
   set trailer_bunny_video_id = '91000000-0000-0000-0000-000000000044', trailer_status = 'pending'
 where id = '91000000-0000-0000-0000-000000000040';
select t.ok((select auto_preview from public.post_items where id = '91000000-0000-0000-0000-000000000040'),
            'the automatic preview stays while the uploaded preview is encoding');
update public.post_items set trailer_status = 'ready' where id = '91000000-0000-0000-0000-000000000040';
select t.ok((select has_trailer and not auto_preview from public.post_items where id = '91000000-0000-0000-0000-000000000040'),
            'an encoded uploaded preview replaces the automatic one');
set role authenticated;
select t.act_as('ads_user');
select t.ok(public.bunny_preview_info('91000000-0000-0000-0000-000000000040')
              = '{"video_id": "91000000-0000-0000-0000-000000000044", "auto": false}'::jsonb,
            'viewers then get the uploaded preview');
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
select t.ok(public.request_full_access() = 'none', 'organic users cannot queue an ads-access request');
select t.ok((select ads_access_status from public.profiles where id = t.id('organic_user')) = 'none',
            'nothing is queued for approval');
select t.act_as('organic_guest');
select t.ok(not public.is_premium_user(), 'guests have no full access');
select t.ok((public.my_status()->>'quota_bytes')::bigint = 0, 'guests have no cloud');
select t.fails($$select public.request_full_access()$$, 'guests must log in to ask');
select t.act_as('owner');
select t.fails($$select public.set_ads_access(t.id('organic_user'), 'approved')$$, 'no approval in free mode either');
select t.act_as('ads_user');
select t.ok(public.request_full_access() = 'approved', 'ads users see approved');
update public.app_mode set free_mode = false;  -- RLS: matches no rows for app users
reset role;
select t.ok((select free_mode from public.app_mode) , 'free mode unchanged by app users');

-- ---------------------------------------------------------------------------
-- New installs from Gujarat / Maharashtra never get ads content.
-- ---------------------------------------------------------------------------
insert into t.ids values
  ('gj_guest',    '00000000-0000-0000-0000-000000000091'),
  ('mh_guest',    '00000000-0000-0000-0000-000000000092'),
  ('other_guest', '00000000-0000-0000-0000-000000000093'),
  ('spoof_guest', '00000000-0000-0000-0000-000000000094'),
  ('gj_user',     '00000000-0000-0000-0000-000000000095');
insert into auth.users (id, email, is_anonymous) values
  (t.id('gj_guest'), null, true), (t.id('mh_guest'), null, true),
  (t.id('other_guest'), null, true), (t.id('spoof_guest'), null, true),
  (t.id('gj_user'), 'gj@example.com', false);
insert into public.geo_blocked_ranges values ('192.0.2.0', '192.0.2.127', 'GJ'), ('2001:db8::', '2001:db8::ffff', 'MH');
select t.ok((select count(*) from public.installs where geo_blocked) = 0, 'installs from before the rule are not flagged');
set role authenticated;

select set_config('request.headers', '{"cf-connecting-ip": "192.0.2.10"}', false);
select t.act_as('gj_guest');
select t.ok(public.record_install('30000000-0000-0000-0000-000000000091', 'ok',
            'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D') = 'meta', 'Gujarat ad install still recorded as meta');
select t.ok(public.user_source() = 'ads', 'attribution unchanged (reports and Meta stay correct)');
select t.ok(public.geo_blocked(), 'Gujarat install is flagged');
select t.ok(not public.has_ads_access(), 'Gujarat ad install: no ads access');
select t.ok(not public.can_see('ads'), 'Gujarat ad install: no ads content');
select t.ok(public.can_see('organic'), 'Gujarat ad install: sees organic content');
select t.ok(public.my_status()->>'source' = 'organic' and not (public.my_status()->>'has_ads_access')::boolean,
            'app sees a Gujarat ad install as organic');

select set_config('request.headers', '{"cf-connecting-ip": "2001:db8::42"}', false);
select t.act_as('mh_guest');
select public.record_install('30000000-0000-0000-0000-000000000092', 'apk',
       'utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download');
select t.ok(not public.has_ads_access() and public.can_see('organic'), 'Maharashtra (IPv6) ads APK install: organic only');

select set_config('request.headers', '{"cf-connecting-ip": "198.51.100.20"}', false);
select t.act_as('other_guest');
select public.record_install('30000000-0000-0000-0000-000000000093', 'ok', 'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D');
select t.ok(public.has_ads_access() and not public.geo_blocked(), 'other states: ads install keeps ads access');

select set_config('request.headers', '{"x-forwarded-for": "192.0.2.10", "cf-connecting-ip": "not-an-ip"}', false);
select t.act_as('spoof_guest');
select t.ok(public.record_install('30000000-0000-0000-0000-000000000094', 'ok', 'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D') = 'meta',
            'bad IP header does not break install');
select t.ok(public.has_ads_access(), 'only cf-connecting-ip counts, not x-forwarded-for');

-- An existing ads user re-reporting the same install from Gujarat is not flagged.
select set_config('request.headers', '{"cf-connecting-ip": "192.0.2.10"}', false);
select t.act_as('ads_guest');
select public.record_install('30000000-0000-0000-0000-000000000003', 'apk',
       'utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download');
select t.ok(public.has_ads_access(), 'existing ads install keeps access');

-- Admin approval does not override the rule.
select t.act_as('gj_user');
select public.record_install('30000000-0000-0000-0000-000000000095', 'not_available');
select t.ok(public.request_full_access() = 'none', 'flagged user cannot queue an access request');
reset role;
update public.profiles set ads_access_status = 'approved' where id = t.id('gj_user');
set role authenticated;
select t.act_as('gj_user');
select t.ok(not public.has_ads_access() and not public.can_see('ads'), 'approval does not unlock ads content for flagged users');
select set_config('request.headers', '', false);
reset role;
select t.ok(not exists (select 1 from public.installs
                         where install_id = '30000000-0000-0000-0000-000000000003' and geo_blocked),
            'old install row not flagged afterwards');

-- ---------------------------------------------------------------------------
-- Only verified Meta ad installs get ads content.
-- ---------------------------------------------------------------------------
select t.ok(public.is_meta_ad_referrer('ok', 'utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D'), 'Meta app-install referrer for our app is verified');
select t.ok(not public.is_meta_ad_referrer('ok', 'utm_source=apps.facebook.com&utm_campaign=fb4a'),
            'hand-made Facebook link without Meta data is not verified');
select t.ok(not public.is_meta_ad_referrer('ok', 'utm_source=meta&utm_medium=paid_social&utm_campaign=x'),
            'hand-made utm_source=meta Play link is not verified');
select t.ok(not public.is_meta_ad_referrer('ok', replace('utm_source=apps.facebook.com&utm_campaign=fb4a&utm_content=%7B%22app%22%3A1790101855436439%2C%22t%22%3A1795090000%2C%22source%22%3A%7B%22data%22%3A%22ab%22%2C%22nonce%22%3A%22cd%22%7D%7D', '1790101855436439', '1111111111111111')),
            'Meta referrer of another app is not verified');
select t.ok(public.is_meta_ad_referrer('apk', 'utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download'),
            'the ads APK is verified');
select t.ok(not public.is_meta_ad_referrer('not_available', null), 'organic APK is not verified');
insert into t.ids values ('fake_link_guest', '00000000-0000-0000-0000-000000000096');
insert into auth.users (id, email, is_anonymous) values (t.id('fake_link_guest'), null, true);
set role authenticated;
select set_config('request.headers', '{"cf-connecting-ip": "198.51.100.30"}', false);
select t.act_as('fake_link_guest');
select public.record_install('30000000-0000-0000-0000-000000000096', 'ok', 'utm_source=apps.facebook.com&utm_campaign=fb4a');
select t.ok(not public.has_ads_access() and not public.can_see('ads') and public.can_see('organic'),
            'a hand-made Facebook Play link gives organic content only');
select t.ok(public.my_status()->>'source' = 'organic', 'the app treats a hand-made link install as organic');
select set_config('request.headers', '', false);
reset role;

-- Dashboard analytics by date range.
set role authenticated;
select t.act_as('organic_user');
select t.fails($$select public.admin_analytics()$$, 'app users cannot read analytics');
select t.act_as('owner');
select t.ok((public.admin_analytics()->>'installs')::int = (select count(*) from public.installs),
            'analytics: all-time installs');
select t.ok((public.admin_analytics()->>'installs_ads')::int + (public.admin_analytics()->>'installs_organic')::int
              = (public.admin_analytics()->>'installs')::int, 'analytics: ads + organic = all installs');
select t.ok((public.admin_analytics(now() + interval '1 day', null)->>'installs')::int = 0, 'analytics: date range filters');
select t.ok(jsonb_array_length(public.admin_analytics()->'daily') between 30 and 32, 'analytics: daily series for all time = last 30 days');
select t.ok(public.admin_analytics()->>'revenue_paise' is not null, 'owner sees revenue');
select t.act_as('content_admin');
select t.ok(public.admin_analytics()->>'revenue_paise' is null, 'content admins do not see revenue');
reset role;
\echo
\echo 'All tests passed.'
