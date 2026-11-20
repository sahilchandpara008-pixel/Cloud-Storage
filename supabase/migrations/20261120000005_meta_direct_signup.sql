-- Meta: report a sign-up for accounts that never were guests (2026-11-20).
--
-- CompleteRegistration is sent when a guest becomes an account. A person who
-- signs in with Google when the guest account cannot be linked gets a
-- brand-new account instead, so there is no "guest became an account" moment
-- and no sign-up reached Meta (1 of 37 sign-ups in the first four days).
--
-- The app calls attribute_user right after every login. A new, non-guest,
-- non-admin account (made in the last day) now reports its sign-up there.
-- The event id is the same as on the normal path, so a sign-up is never
-- sent twice, and older accounts logging in again send nothing.
-- Everything else in the function is unchanged.

create or replace function public.attribute_user(p_install_id uuid)
returns text
language plpgsql security definer set search_path = ''
as $function$
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

  -- Sign-up of an account that never was a guest. Tracking must never break
  -- a login, so any problem here is ignored.
  begin
    if exists (select 1 from auth.users u join public.profiles p on p.id = u.id
                where u.id = v_uid and not p.is_guest
                  and u.created_at > now() - interval '1 day')
       and not public.is_admin_user(v_uid) then
      perform public.meta_enqueue('CompleteRegistration', 'register-' || v_uid, v_uid, null,
                                  jsonb_build_object('status', 'registered'));
    end if;
  exception when others then
    null;
  end;

  return (select first_touch_source from public.user_attribution where user_id = v_uid);
end $function$;
