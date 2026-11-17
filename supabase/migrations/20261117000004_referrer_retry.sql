-- Install referrer retry.
--
-- On the Play build the app asks Google for the install referrer (the
-- utm_source=meta... string on the ad's Play link). That call can fail on the
-- first launch (Play services not ready yet). The app used to record the
-- install as 'not_available' -> source 'direct' and never ask again, so a
-- real ad install could become an organic user for good.
--
-- The app now retries on later launches. record_install already replaces a
-- failed read with the first successful one for the SAME install. This lets
-- that upgrade reach the user's first touch too -- but only in that one case:
--   * same install as the user's first touch,
--   * the first touch came from a failed read ('direct'),
--   * the install now holds a successful read ('ok' / 'apk').
-- Every other change to a first touch is still refused, so a later install
-- from a different link can never turn an organic user into an ads user.

create or replace function public.protect_first_touch()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (new.first_touch_source, new.first_touch_medium, new.first_touch_campaign,
      new.first_touch_content, new.first_touch_at)
     is distinct from
     (old.first_touch_source, old.first_touch_medium, old.first_touch_campaign,
      old.first_touch_content, old.first_touch_at) then
    if old.first_touch_source = 'direct'
       and new.first_touch_install_id is not distinct from old.first_touch_install_id
       and new.first_touch_at is not distinct from old.first_touch_at
       and exists (
         select 1 from public.installs i
          where i.install_id = old.first_touch_install_id
            and i.referrer_status in ('ok', 'apk')
            and i.source = new.first_touch_source
            and i.utm_medium is not distinct from new.first_touch_medium
            and i.utm_campaign is not distinct from new.first_touch_campaign
            and i.utm_content is not distinct from new.first_touch_content) then
      return new; -- a failed referrer read of the same install was retried successfully
    end if;
    raise exception 'first touch attribution is immutable';
  end if;
  return new;
end $$;

revoke execute on function public.protect_first_touch() from public, anon, authenticated;

create or replace function public.attribute_user(p_install_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_inst public.installs;
begin
  if v_uid is null then return null; end if;
  select * into v_inst from public.installs where install_id = p_install_id;
  if not found then return null; end if;

  update public.installs
     set first_user_id = v_uid, updated_at = now()
   where install_id = p_install_id and first_user_id is null;

  insert into public.user_attribution as ua (
    user_id,
    first_touch_source, first_touch_medium, first_touch_campaign, first_touch_content,
    first_touch_install_id,
    last_touch_source, last_touch_medium, last_touch_campaign, last_touch_content,
    last_touch_install_id)
  values (
    v_uid,
    v_inst.source, v_inst.utm_medium, v_inst.utm_campaign, v_inst.utm_content,
    v_inst.install_id,
    v_inst.source, v_inst.utm_medium, v_inst.utm_campaign, v_inst.utm_content,
    v_inst.install_id)
  on conflict (user_id) do update
     set last_touch_source     = excluded.last_touch_source,
         last_touch_medium     = excluded.last_touch_medium,
         last_touch_campaign   = excluded.last_touch_campaign,
         last_touch_content    = excluded.last_touch_content,
         last_touch_install_id = excluded.last_touch_install_id,
         last_touch_at         = now(),
         -- Retried referrer of the first-touch install (see the trigger).
         first_touch_source   = case when ua.first_touch_source = 'direct'
                                      and ua.first_touch_install_id = excluded.first_touch_install_id
                                      and v_inst.referrer_status in ('ok', 'apk')
                                     then excluded.first_touch_source else ua.first_touch_source end,
         first_touch_medium   = case when ua.first_touch_source = 'direct'
                                      and ua.first_touch_install_id = excluded.first_touch_install_id
                                      and v_inst.referrer_status in ('ok', 'apk')
                                     then excluded.first_touch_medium else ua.first_touch_medium end,
         first_touch_campaign = case when ua.first_touch_source = 'direct'
                                      and ua.first_touch_install_id = excluded.first_touch_install_id
                                      and v_inst.referrer_status in ('ok', 'apk')
                                     then excluded.first_touch_campaign else ua.first_touch_campaign end,
         first_touch_content  = case when ua.first_touch_source = 'direct'
                                      and ua.first_touch_install_id = excluded.first_touch_install_id
                                      and v_inst.referrer_status in ('ok', 'apk')
                                     then excluded.first_touch_content else ua.first_touch_content end;

  return (select first_touch_source from public.user_attribution where user_id = v_uid);
end $$;
