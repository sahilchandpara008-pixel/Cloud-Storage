-- Push notifications (Firebase Cloud Messaging).
--
-- * The app registers each phone's push token (register_push_token).
-- * The owner writes a message in admin -> Notifications (admin_push_create):
--   title, text, optional image, what a tap opens, who gets it, when.
-- * Every minute push_tick() turns due messages into one delivery row per
--   phone and calls the push-send function, which sends them through Firebase
--   and reports back (push_claim / push_finish). The function takes nothing
--   from its request: it only sends what is already queued here.
-- * Only phones whose user answered "Allow" (installs.notif_status) are sent
--   to, except "test" messages, which go to the owner's own phones.

create table if not exists public.push_tokens (
  install_id uuid primary key,
  token      text not null unique,
  user_id    uuid,
  updated_at timestamptz not null default now()
);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;
create index if not exists push_tokens_user on public.push_tokens (user_id);

create table if not exists public.push_settings (
  id           int primary key default 1 check (id = 1),
  function_url text
);
insert into public.push_settings (id) values (1) on conflict do nothing;
alter table public.push_settings enable row level security;
revoke all on public.push_settings from anon, authenticated;

create table if not exists public.push_messages (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null default 'manual',
  title        text not null check (char_length(title) between 1 and 65),
  body         text not null default '' check (char_length(body) <= 240),
  image_url    text check (image_url ~ '^https://'),
  action_type  text not null default 'home' check (action_type in ('home', 'post', 'channel', 'premium', 'url')),
  action_id    text,
  action_url   text check (action_url ~ '^https?://'),
  audience     text not null check (audience in ('all', 'members', 'channels', 'premium', 'not_premium',
                                                 'ads', 'organic', 'guests', 'logged_in', 'test')),
  channel_ids  uuid[] not null default '{}',
  scheduled_at timestamptz not null default now(),
  status       text not null default 'scheduled' check (status in ('scheduled', 'sending', 'sent', 'cancelled')),
  recipients   int not null default 0,
  created_by   uuid,
  created_at   timestamptz not null default now(),
  sent_at      timestamptz
);
alter table public.push_messages enable row level security;
revoke all on public.push_messages from anon, authenticated;
create index if not exists push_messages_due on public.push_messages (scheduled_at) where status = 'scheduled';

create table if not exists public.push_deliveries (
  id          bigint generated always as identity primary key,
  message_id  uuid not null references public.push_messages (id) on delete cascade,
  install_id  uuid not null,
  token       text not null,
  status      text not null default 'queued' check (status in ('queued', 'sending', 'sent', 'failed')),
  error       text,
  attempts    int not null default 0,
  claimed_at  timestamptz,
  sent_at     timestamptz,
  opened_at   timestamptz,
  unique (message_id, install_id)
);
alter table public.push_deliveries enable row level security;
revoke all on public.push_deliveries from anon, authenticated;
create index if not exists push_deliveries_queued on public.push_deliveries (id) where status = 'queued';

-- App: save this phone's push token (moves to the logged-in account).
create or replace function public.register_push_token(p_install_id uuid, p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_token text := trim(coalesce(p_token, ''));
  v_linked boolean;
  v_unclaimed boolean;
begin
  if auth.uid() is null then return; end if;
  if char_length(v_token) not between 20 and 4096 or v_token !~ '^[A-Za-z0-9:_-]+$' then return; end if;
  select i.first_user_id = auth.uid()
         or exists (select 1 from public.user_attribution ua
                     where ua.user_id = auth.uid()
                       and p_install_id in (ua.first_touch_install_id, ua.last_touch_install_id)),
         i.first_user_id is null
    into v_linked, v_unclaimed
    from public.installs i where i.install_id = p_install_id;
  -- Linked to this account, or not linked to anyone and not already holding
  -- another account's token.
  if not coalesce(v_linked, false)
     and not (coalesce(v_unclaimed, false)
              and not exists (select 1 from public.push_tokens t
                               where t.install_id = p_install_id and t.user_id is distinct from auth.uid())) then
    return;
  end if;
  delete from public.push_tokens where token = v_token and install_id <> p_install_id;
  insert into public.push_tokens (install_id, token, user_id, updated_at)
  values (p_install_id, v_token, auth.uid(), now())
  on conflict (install_id) do update
     set token = excluded.token, user_id = excluded.user_id, updated_at = now();
end $$;
revoke execute on function public.register_push_token(uuid, text) from public, anon;
grant execute on function public.register_push_token(uuid, text) to authenticated;

-- Who a message goes to: phones with a token whose user allowed notifications.
create or replace function public.push_audience(p_audience text, p_channel_ids uuid[], p_owner uuid)
returns table (install_id uuid, token text)
language sql stable security definer set search_path = ''
as $$
  select t.install_id, t.token
    from public.push_tokens t
    join public.installs i on i.install_id = t.install_id
    left join public.profiles p on p.id = t.user_id
   where (p_audience = 'test' and t.user_id = p_owner)
      or (p_audience <> 'test' and i.notif_status = 'allowed' and case p_audience
            when 'all' then true
            when 'members' then exists (select 1 from public.channel_members cm where cm.user_id = t.user_id)
            when 'channels' then exists (select 1 from public.channel_members cm
                                          where cm.user_id = t.user_id and cm.channel_id = any (p_channel_ids))
            when 'premium' then exists (select 1 from public.subscriptions s
                                         where s.user_id = t.user_id and now() between s.starts_at and s.ends_at)
            when 'not_premium' then not exists (select 1 from public.subscriptions s
                                                 where s.user_id = t.user_id and now() between s.starts_at and s.ends_at)
            when 'ads' then i.source = public.ad_source()
            when 'organic' then i.source is distinct from public.ad_source()
            when 'guests' then coalesce(p.is_guest, true)
            when 'logged_in' then p.is_guest = false
            else false
          end)
$$;
revoke execute on function public.push_audience(text, uuid[], uuid) from public, anon, authenticated;

-- Admin: how many phones a message would reach right now.
create or replace function public.admin_push_reach(p_audience text, p_channel_ids uuid[] default '{}')
returns int
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can send notifications'; end if;
  return (select count(*) from public.push_audience(p_audience, coalesce(p_channel_ids, '{}'), auth.uid()));
end $$;
revoke execute on function public.admin_push_reach(text, uuid[]) from public, anon;
grant execute on function public.admin_push_reach(text, uuid[]) to authenticated;

-- Admin: queue a message (sent within a minute, or at p_scheduled_at).
create or replace function public.admin_push_create(
  p_title text, p_body text, p_image_url text, p_action_type text, p_action_id text, p_action_url text,
  p_audience text, p_channel_ids uuid[] default '{}', p_scheduled_at timestamptz default null)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  if not public.is_owner() then raise exception 'only the owner can send notifications'; end if;
  if p_action_type in ('post', 'channel') and coalesce(trim(p_action_id), '') = '' then
    raise exception 'pick what the message opens';
  end if;
  if p_action_type = 'url' and coalesce(p_action_url, '') !~ '^https?://' then
    raise exception 'enter a link starting with https://';
  end if;
  if p_audience = 'channels' and coalesce(array_length(p_channel_ids, 1), 0) = 0 then
    raise exception 'pick at least one channel';
  end if;
  insert into public.push_messages (title, body, image_url, action_type, action_id, action_url,
                                    audience, channel_ids, scheduled_at, created_by)
  values (trim(p_title), coalesce(trim(p_body), ''), nullif(trim(coalesce(p_image_url, '')), ''), p_action_type,
          case when p_action_type in ('post', 'channel') then trim(p_action_id) end,
          case when p_action_type = 'url' then trim(p_action_url) end,
          p_audience, coalesce(p_channel_ids, '{}'),
          greatest(coalesce(p_scheduled_at, now()), now()), auth.uid())
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.admin_push_create(text, text, text, text, text, text, text, uuid[], timestamptz) from public, anon;
grant execute on function public.admin_push_create(text, text, text, text, text, text, text, uuid[], timestamptz) to authenticated;

create or replace function public.admin_push_cancel(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can send notifications'; end if;
  update public.push_messages set status = 'cancelled' where id = p_id and status = 'scheduled';
end $$;
revoke execute on function public.admin_push_cancel(uuid) from public, anon;
grant execute on function public.admin_push_cancel(uuid) to authenticated;

-- Admin: overview numbers and the latest messages with sent / tapped counts.
create or replace function public.admin_push_overview(p_limit int default 50)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can see notifications'; end if;
  return jsonb_build_object(
    'reachable', (select count(*) from public.push_audience('all', '{}', auth.uid())),
    'tokens', (select count(*) from public.push_tokens),
    'my_phones', (select count(*) from public.push_tokens where user_id = auth.uid()),
    'sent_7d', (select count(*) from public.push_messages
                 where status = 'sent' and audience <> 'test' and sent_at > now() - interval '7 days'),
    'sent_today_all', (select count(*) from public.push_messages
                        where audience = 'all' and status in ('scheduled', 'sending', 'sent')
                          and coalesce(sent_at, scheduled_at) >= date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    'configured', (select function_url is not null from public.push_settings where id = 1),
    'last_error', (select d.error from public.push_deliveries d
                    where d.status = 'failed' and d.sent_at > now() - interval '1 day'
                    order by d.id desc limit 1),
    'messages', coalesce((
      select jsonb_agg(x order by x.created_at desc) from (
        select m.id, m.kind, m.title, m.body, m.image_url, m.action_type, m.audience, m.channel_ids,
               m.status, m.scheduled_at, m.sent_at, m.created_at, m.recipients,
               (select count(*) from public.push_deliveries d where d.message_id = m.id and d.status = 'sent') as sent,
               (select count(*) from public.push_deliveries d where d.message_id = m.id and d.status = 'failed') as failed,
               (select count(*) from public.push_deliveries d where d.message_id = m.id and d.opened_at is not null) as opened
          from public.push_messages m
         order by m.created_at desc
         limit greatest(1, least(coalesce(p_limit, 50), 200))) x), '[]'::jsonb));
end $$;
revoke execute on function public.admin_push_overview(int) from public, anon;
grant execute on function public.admin_push_overview(int) to authenticated;

-- App: a message was tapped (counted once per phone).
create or replace function public.push_opened(p_message_id uuid, p_install_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then return; end if;
  update public.push_deliveries d
     set opened_at = now()
   where d.message_id = p_message_id and d.install_id = p_install_id and d.opened_at is null
     and exists (select 1 from public.push_tokens t where t.install_id = p_install_id and t.user_id = auth.uid());
end $$;
revoke execute on function public.push_opened(uuid, uuid) from public, anon;
grant execute on function public.push_opened(uuid, uuid) to authenticated;

-- Sender (service role only): take up to p_limit queued deliveries.
create or replace function public.push_claim(p_limit int default 500)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v jsonb;
begin
  with c as (
    select d.id from public.push_deliveries d
     where d.status = 'queued'
     order by d.id
     limit greatest(1, least(coalesce(p_limit, 500), 1000))
     for update skip locked
  ), u as (
    update public.push_deliveries d
       set status = 'sending', claimed_at = now(), attempts = d.attempts + 1
      from c where d.id = c.id
    returning d.id, d.token, d.message_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id, 'token', u.token, 'mid', m.id, 'title', m.title, 'body', m.body,
           'image', m.image_url, 'type', m.action_type, 'target', m.action_id, 'url', m.action_url)), '[]'::jsonb)
    into v
    from u join public.push_messages m on m.id = u.message_id;
  return v;
end $$;
revoke execute on function public.push_claim(int) from public, anon, authenticated;
grant execute on function public.push_claim(int) to service_role;

-- Sender: results [{id, ok, error, unregistered}].
create or replace function public.push_finish(p_results jsonb)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.push_deliveries d
     set status = case when (r->>'ok')::boolean then 'sent'
                       when coalesce((r->>'retry')::boolean, false) and d.attempts < 3 then 'queued'
                       else 'failed' end,
         error = left(r->>'error', 300),
         sent_at = now()
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) r
   where d.id = (r->>'id')::bigint and d.status = 'sending';
  -- Phones that uninstalled the app or reset it: forget the token.
  delete from public.push_tokens t
   using public.push_deliveries d, jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) r
   where d.id = (r->>'id')::bigint and coalesce((r->>'unregistered')::boolean, false) and t.token = d.token;
  update public.push_messages m
     set status = 'sent', sent_at = now()
   where m.status = 'sending'
     and not exists (select 1 from public.push_deliveries d
                      where d.message_id = m.id and d.status in ('queued', 'sending'));
end $$;
revoke execute on function public.push_finish(jsonb) from public, anon, authenticated;
grant execute on function public.push_finish(jsonb) to service_role;

-- Every minute: queue due messages, retry stuck ones, wake the sender.
create or replace function public.push_tick()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  m public.push_messages;
  v_n int;
  v_url text;
begin
  for m in select * from public.push_messages
            where status = 'scheduled' and scheduled_at <= now()
            order by scheduled_at
            for update skip locked
  loop
    insert into public.push_deliveries (message_id, install_id, token)
    select m.id, a.install_id, a.token from public.push_audience(m.audience, m.channel_ids, m.created_by) a
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

do $$
begin
  perform cron.schedule('push-tick', '* * * * *', 'select public.push_tick()');
exception when others then
  raise notice 'push tick not scheduled: %', sqlerrm;
end $$;

-- Admin: queue and send what is due now (right after "Send"), instead of
-- waiting for the next minute.
create or replace function public.admin_push_kick()
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can send notifications'; end if;
  perform public.push_tick();
end $$;
revoke execute on function public.admin_push_kick() from public, anon;
grant execute on function public.admin_push_kick() to authenticated;
