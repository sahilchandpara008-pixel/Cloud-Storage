-- Automatic push messages (admin -> Notifications -> Automatic).
--
-- Every minute push_tick() first calls push_auto_tick(), which only READS
-- payments, plans and posts and queues messages; it never changes them, and
-- each part swallows its own errors, so it can never block a payment or a
-- publish. Each message is created once (dedupe_key).
--
--   payment_reminder  1 h after an unfinished payment (once a day per user)
--   payment_approved  when a payment is approved
--   plan_ending       1 day before a plan ends
--   come_back         7 days without opening the app (once per absence)
--   new_videos        new videos per channel, to members or to all users,
--                     at most once every N hours per channel (combined)

alter table public.push_messages
  add column if not exists target_user uuid,
  add column if not exists target_install uuid,
  add column if not exists content_audience text check (content_audience in ('ads', 'organic')),
  add column if not exists ref_id uuid,
  add column if not exists dedupe_key text;
create unique index if not exists push_messages_dedupe on public.push_messages (dedupe_key) where dedupe_key is not null;
create index if not exists push_messages_kind_ref on public.push_messages (kind, ref_id, created_at);
create index if not exists analytics_events_install on public.analytics_events (install_id, created_at);

alter table public.push_settings add column if not exists storage_base text;
-- Set once per project: 'https://<ref>.supabase.co/storage/v1/object/public/public/'

create table if not exists public.push_auto (
  kind           text primary key check (kind in ('payment_reminder', 'payment_approved', 'plan_ending',
                                                  'come_back', 'new_videos')),
  enabled        boolean not null default false,
  title          text not null check (char_length(title) between 1 and 65),
  body           text not null default '' check (char_length(body) <= 240),
  nv_mode        text not null default 'all' check (nv_mode in ('members', 'all')),
  interval_hours int not null default 4 check (interval_hours between 1 and 48),
  enabled_at     timestamptz,
  updated_at     timestamptz not null default now()
);
alter table public.push_auto enable row level security;
revoke all on public.push_auto from anon, authenticated;
insert into public.push_auto (kind, enabled, title, body, enabled_at) values
  ('payment_reminder', true,  'Your {plan} is waiting',
   '₹{price} for {duration} of fast upload & 2 TB storage. Tap to finish.', now()),
  ('payment_approved', true,  'Your {plan} is active ✅',
   'Enjoy fast upload & download. Valid till {end_date}.', now()),
  ('plan_ending',      true,  'Your plan ends tomorrow',
   'Renew to keep fast speed & 2 TB storage.', now()),
  ('come_back',        false, 'New videos are waiting',
   'See what''s new on Flixvault.', null),
  ('new_videos',       false, 'New in {channel}',
   '{title}. Tap to watch.', null)
on conflict (kind) do nothing;

-- Per channel: off / members / all (no row = the default from new_videos).
create table if not exists public.push_channel_auto (
  channel_id uuid primary key references public.channels (id) on delete cascade,
  mode       text not null check (mode in ('off', 'members', 'all'))
);
alter table public.push_channel_auto enable row level security;
revoke all on public.push_channel_auto from anon, authenticated;

-- Videos already announced (so each is announced once).
create table if not exists public.push_notified_posts (
  post_id     uuid primary key,
  notified_at timestamptz not null default now()
);
alter table public.push_notified_posts enable row level security;
revoke all on public.push_notified_posts from anon, authenticated;

create or replace function public.push_render(p_text text, p_vars jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare
  k text;
  v_out text := coalesce(p_text, '');
begin
  for k in select jsonb_object_keys(coalesce(p_vars, '{}'::jsonb)) loop
    v_out := replace(v_out, '{' || k || '}', coalesce(p_vars->>k, ''));
  end loop;
  return v_out;
end $$;

create or replace function public.push_duration(p_days int)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_days % 365 = 0 then case when p_days = 365 then '1 year' else (p_days / 365) || ' years' end
    when p_days % 30 = 0 then case when p_days = 30 then '1 month' else (p_days / 30) || ' months' end
    when p_days = 1 then '1 day'
    else p_days || ' days' end
$$;

-- Phones a queued message goes to: its audience, narrowed to one user /
-- one phone / ads or organic installs when set.
create or replace function public.push_targets(m public.push_messages)
returns table (install_id uuid, token text)
language sql stable security definer set search_path = ''
as $$
  select a.install_id, a.token
    from public.push_audience(m.audience, m.channel_ids, m.created_by) a
    join public.installs i on i.install_id = a.install_id
    join public.push_tokens t on t.install_id = a.install_id
   where (m.target_user is null or t.user_id = m.target_user)
     and (m.target_install is null or a.install_id = m.target_install)
     and (m.content_audience is null
          or (m.content_audience = 'ads' and i.source = public.ad_source())
          or (m.content_audience = 'organic' and i.source is distinct from public.ad_source()))
$$;
revoke execute on function public.push_targets(public.push_messages) from public, anon, authenticated;

create or replace function public.push_auto_tick()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  a public.push_auto;
  v_base text;
  c record;
  g record;
  v_mode text;
begin
  select storage_base into v_base from public.push_settings where id = 1;

  -- 1. Payment reminder: an unfinished payment 1-6 hours ago, nothing paid
  --    or waiting since, no active plan; once a day per user.
  begin
    select * into a from public.push_auto where kind = 'payment_reminder';
    if a.enabled then
      insert into public.push_messages (kind, title, body, action_type, audience, target_user, dedupe_key)
      select 'payment_reminder',
             left(public.push_render(a.title, v), 65), left(public.push_render(a.body, v), 240),
             'premium', 'all', o.user_id,
             'reminder:' || o.user_id || ':' || to_char(now() at time zone 'Asia/Kolkata', 'YYYY-MM-DD')
        from (select distinct on (o.user_id) o.user_id, o.created_at, pl.name, pl.price_inr, pl.duration_days
                from public.payment_orders o join public.plans pl on pl.id = o.plan_id
               where o.status in ('initiated', 'failed', 'cancelled')
                 and o.created_at between now() - interval '6 hours' and now() - interval '1 hour'
                 and o.created_at >= coalesce(a.enabled_at, now())
               order by o.user_id, o.created_at desc) o,
             lateral (select jsonb_build_object('plan', o.name, 'price', o.price_inr,
                                                'duration', public.push_duration(o.duration_days)) v) x
       where not exists (select 1 from public.payment_orders y
                          where y.user_id = o.user_id and y.created_at > o.created_at - interval '1 minute'
                            and y.status in ('pending', 'approved'))
         and not exists (select 1 from public.subscriptions s
                          where s.user_id = o.user_id and now() between s.starts_at and s.ends_at)
         and not public.is_admin_user(o.user_id)
         and exists (select 1 from public.push_tokens t where t.user_id = o.user_id)
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    end if;
  exception when others then
    raise warning 'push payment_reminder: %', sqlerrm;
  end;

  -- 2. Payment approved (last 30 minutes).
  begin
    select * into a from public.push_auto where kind = 'payment_approved';
    if a.enabled then
      insert into public.push_messages (kind, title, body, action_type, audience, target_user, dedupe_key)
      select 'payment_approved',
             left(public.push_render(a.title, v), 65), left(public.push_render(a.body, v), 240),
             'home', 'all', o.user_id, 'approved:' || o.id
        from public.payment_orders o
        join public.plans pl on pl.id = o.plan_id
        left join public.subscriptions s on s.id = o.subscription_id,
             lateral (select jsonb_build_object(
                        'plan', pl.name, 'price', pl.price_inr, 'duration', public.push_duration(pl.duration_days),
                        'end_date', coalesce(to_char(s.ends_at at time zone 'Asia/Kolkata', 'FMDD Mon YYYY'), '')) v) x
       where o.status = 'approved'
         and o.verified_at > now() - interval '30 minutes'
         and o.verified_at >= coalesce(a.enabled_at, now())
         and exists (select 1 from public.push_tokens t where t.user_id = o.user_id)
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    end if;
  exception when others then
    raise warning 'push payment_approved: %', sqlerrm;
  end;

  -- 3. Plan ending tomorrow (and no other plan continues after it).
  begin
    select * into a from public.push_auto where kind = 'plan_ending';
    if a.enabled then
      insert into public.push_messages (kind, title, body, action_type, audience, target_user, dedupe_key)
      select 'plan_ending',
             left(public.push_render(a.title, v), 65), left(public.push_render(a.body, v), 240),
             'premium', 'all', s.user_id, 'ending:' || s.id
        from public.subscriptions s
        join public.plans pl on pl.id = s.plan_id,
             lateral (select jsonb_build_object(
                        'plan', pl.name,
                        'end_date', to_char(s.ends_at at time zone 'Asia/Kolkata', 'FMDD Mon YYYY')) v) x
       where s.ends_at between now() + interval '20 hours' and now() + interval '28 hours'
         and not exists (select 1 from public.subscriptions s2
                          where s2.user_id = s.user_id and s2.id <> s.id and s2.ends_at > s.ends_at)
         and not public.is_admin_user(s.user_id)
         and exists (select 1 from public.push_tokens t where t.user_id = s.user_id)
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    end if;
  exception when others then
    raise warning 'push plan_ending: %', sqlerrm;
  end;

  -- 4. Come back: 7+ days since the app was last opened (once per absence).
  begin
    select * into a from public.push_auto where kind = 'come_back';
    if a.enabled then
      insert into public.push_messages (kind, title, body, action_type, audience, target_install, dedupe_key)
      select 'come_back', left(a.title, 65), left(a.body, 240), 'home', 'all', t.install_id,
             'comeback:' || t.install_id || ':' || to_char(l.last_open, 'YYYY-MM-DD')
        from public.push_tokens t
        join lateral (select max(e.created_at) as last_open from public.analytics_events e
                       where e.install_id = t.install_id and e.event = 'app_open') l on true
       where l.last_open < now() - interval '7 days'
         and l.last_open > now() - interval '60 days'
      on conflict (dedupe_key) where dedupe_key is not null do nothing;
    end if;
  exception when others then
    raise warning 'push come_back: %', sqlerrm;
  end;

  -- 5. New videos, per channel: members or all users, combined, at most
  --    once every interval_hours. Only videos that went live after the
  --    feature was turned on; ads-only / organic-only content only to those.
  begin
    select * into a from public.push_auto where kind = 'new_videos';
    if a.enabled then
      for c in
        select ch.id, ch.name, ch.audience::text as audience, coalesce(o.mode, a.nv_mode) as mode
          from public.channels ch
          left join public.push_channel_auto o on o.channel_id = ch.id
         where ch.status = 'published' and coalesce(o.mode, a.nv_mode) <> 'off'
      loop
        continue when exists (select 1 from public.push_messages m
                               where m.kind = 'new_videos' and m.ref_id = c.id
                                 and m.created_at > now() - make_interval(hours => a.interval_hours));
        for g in
          select case when c.audience = 'all' then p.audience::text
                      when p.audience::text in ('all', c.audience) then c.audience
                      else 'none' end as aud,
                 count(*) as n,
                 array_agg(p.id) as ids,
                 (array_agg(p.id order by p.published_at desc))[1] as latest_id,
                 (array_agg(p.title order by p.published_at desc))[1] as latest_title
            from public.posts p
           where p.channel_id = c.id
             and p.status = 'published' and p.published_at <= now()
             and greatest(p.published_at, p.created_at) >= a.enabled_at
             and not exists (select 1 from public.post_items i
                              where i.post_id = p.id and i.processing_status <> 'ready')
             and exists (select 1 from public.post_items i where i.post_id = p.id)
             and not exists (select 1 from public.push_notified_posts np where np.post_id = p.id)
           group by 1
        loop
          insert into public.push_notified_posts (post_id) select unnest(g.ids) on conflict do nothing;
          continue when g.aud = 'none';
          insert into public.push_messages (kind, title, body, image_url, action_type, action_id, audience,
                                            channel_ids, content_audience, ref_id)
          values ('new_videos',
                  left(case when g.n = 1
                            then public.push_render(a.title, jsonb_build_object('channel', c.name, 'title', g.latest_title))
                            else g.n || ' new videos in ' || c.name end, 65),
                  left(case when g.n = 1
                            then public.push_render(a.body, jsonb_build_object('channel', c.name, 'title', g.latest_title))
                            else 'Including “' || g.latest_title || '”. Tap to watch.' end, 240),
                  (select v_base || i.thumb_key from public.post_items i
                    where i.post_id = g.latest_id and i.thumb_key is not null and v_base like 'https://%'
                    order by i.position limit 1),
                  case when g.n = 1 then 'post' else 'channel' end,
                  case when g.n = 1 then g.latest_id::text else c.id::text end,
                  case when c.mode = 'members' then 'channels' else 'all' end,
                  case when c.mode = 'members' then array[c.id] else '{}'::uuid[] end,
                  case when g.aud in ('ads', 'organic') then g.aud end,
                  c.id);
        end loop;
      end loop;
    end if;
  exception when others then
    raise warning 'push new_videos: %', sqlerrm;
  end;
end $$;
revoke execute on function public.push_auto_tick() from public, anon, authenticated;

-- push_tick: automatic messages first, then queue per phone via push_targets.
create or replace function public.push_tick()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.push_messages;
  v_n int;
  v_url text;
begin
  begin
    perform public.push_auto_tick();
  exception when others then
    raise warning 'push auto: %', sqlerrm;
  end;

  for m in select * from public.push_messages
            where status = 'scheduled' and scheduled_at <= now()
            order by scheduled_at
            for update skip locked
  loop
    insert into public.push_deliveries (message_id, install_id, token)
    select m.id, a.install_id, a.token from public.push_targets(m) a
    on conflict do nothing;
    get diagnostics v_n = row_count;
    update public.push_messages
       set status = case when v_n = 0 then 'sent' else 'sending' end,
           recipients = v_n,
           sent_at = case when v_n = 0 then now() end
     where id = m.id;
  end loop;

  update public.push_deliveries
     set status = case when attempts < 3 then 'queued' else 'failed' end,
         error = case when attempts < 3 then error else 'no answer from the sender' end
   where status = 'sending' and claimed_at < now() - interval '5 minutes';
  update public.push_messages pm
     set status = 'sent', sent_at = now()
   where pm.status = 'sending'
     and not exists (select 1 from public.push_deliveries d
                      where d.message_id = pm.id and d.status in ('queued', 'sending'));

  if not exists (select 1 from public.push_deliveries where status = 'queued') then return; end if;
  select function_url into v_url from public.push_settings where id = 1;
  if v_url is null or to_regclass('net.http_request_queue') is null then return; end if;
  execute 'select net.http_post(url := $1, body := ''{}''::jsonb, headers := ''{"Content-Type": "application/json"}''::jsonb)'
    using v_url;
end $$;
revoke execute on function public.push_tick() from public, anon, authenticated;

-- Admin: read / save the automatic messages.
create or replace function public.admin_push_auto_get()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can change notifications'; end if;
  return jsonb_build_object(
    'kinds', (select jsonb_object_agg(kind, jsonb_build_object(
                'enabled', enabled, 'title', title, 'body', body, 'nv_mode', nv_mode,
                'interval_hours', interval_hours)) from public.push_auto),
    'channels', coalesce((select jsonb_agg(jsonb_build_object(
                  'id', ch.id, 'name', ch.name, 'members', (select count(*) from public.channel_members cm
                                                             where cm.channel_id = ch.id),
                  'mode', o.mode) order by ch.name)
                from public.channels ch left join public.push_channel_auto o on o.channel_id = ch.id
               where ch.status = 'published'), '[]'::jsonb),
    'sent_7d', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb) from (
                  select kind, count(*) as n from public.push_messages
                   where kind <> 'manual' and created_at > now() - interval '7 days' group by kind) x));
end $$;
revoke execute on function public.admin_push_auto_get() from public, anon;
grant execute on function public.admin_push_auto_get() to authenticated;

create or replace function public.admin_push_auto_save(
  p_kind text, p_enabled boolean, p_title text, p_body text,
  p_nv_mode text default null, p_interval_hours int default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can change notifications'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'enter a title'; end if;
  update public.push_auto
     set enabled = coalesce(p_enabled, false),
         title = left(trim(p_title), 65),
         body = left(coalesce(trim(p_body), ''), 240),
         nv_mode = coalesce(p_nv_mode, nv_mode),
         interval_hours = coalesce(p_interval_hours, interval_hours),
         -- Turning on starts from now: nothing from before is sent.
         enabled_at = case when coalesce(p_enabled, false) and not enabled then now() else enabled_at end,
         updated_at = now()
   where kind = p_kind;
  if not found then raise exception 'unknown message type'; end if;
end $$;
revoke execute on function public.admin_push_auto_save(text, boolean, text, text, text, int) from public, anon;
grant execute on function public.admin_push_auto_save(text, boolean, text, text, text, int) to authenticated;

create or replace function public.admin_push_channel_mode(p_channel_id uuid, p_mode text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can change notifications'; end if;
  if p_mode is null or p_mode = 'default' then
    delete from public.push_channel_auto where channel_id = p_channel_id;
  elsif p_mode in ('off', 'members', 'all') then
    insert into public.push_channel_auto (channel_id, mode) values (p_channel_id, p_mode)
    on conflict (channel_id) do update set mode = excluded.mode;
  else
    raise exception 'unknown setting';
  end if;
end $$;
revoke execute on function public.admin_push_channel_mode(uuid, text) from public, anon;
grant execute on function public.admin_push_channel_mode(uuid, text) to authenticated;
