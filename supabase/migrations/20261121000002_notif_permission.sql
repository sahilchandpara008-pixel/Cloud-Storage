-- Notification permission: the app reports each phone's answer (Allow /
-- Don't allow, or the current setting on Android 12 and older), so the admin
-- panel can show the allowed / not allowed percentage, split ads / organic.

alter table public.installs
  add column if not exists notif_status text check (notif_status in ('allowed', 'denied')),
  add column if not exists notif_updated_at timestamptz;

create or replace function public.record_notif_status(p_install_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or p_status not in ('allowed', 'denied') then return; end if;
  update public.installs
     set notif_status = p_status,
         notif_updated_at = now()
   where install_id = p_install_id
     and notif_status is distinct from p_status
     and (first_user_id is null or first_user_id = auth.uid()
          or exists (select 1 from public.user_attribution ua
                      where ua.user_id = auth.uid()
                        and p_install_id in (ua.first_touch_install_id, ua.last_touch_install_id)));
end $$;
revoke execute on function public.record_notif_status(uuid, text) from public, anon;
grant execute on function public.record_notif_status(uuid, text) to authenticated;

-- Owner report: installs in the date range, by ads / organic, with how many
-- allowed, did not allow, or have not answered yet (app older than 1.11.7).
create or replace function public.admin_notif_stats(
  p_from timestamptz default null,
  p_to   timestamptz default null)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v jsonb;
begin
  if not public.is_owner() then raise exception 'only the owner can see this report'; end if;
  with per as (
    select case when i.source = public.ad_source() then 'ads' else 'organic' end as grp, i.notif_status
      from public.installs i
     where (p_from is null or i.created_at >= p_from) and (p_to is null or i.created_at < p_to)
       and not exists (select 1 from public.admins a where a.user_id = i.first_user_id)
  ), g as (
    select x.grp,
           count(*) as installs,
           count(*) filter (where x.notif_status = 'allowed') as allowed,
           count(*) filter (where x.notif_status = 'denied') as denied,
           count(*) filter (where x.notif_status is null) as unknown
      from (select 'all' as grp, notif_status from per
            union all select grp, notif_status from per) x
     group by x.grp
  )
  select coalesce(jsonb_object_agg(grp, jsonb_build_object(
           'installs', installs, 'allowed', allowed, 'denied', denied, 'unknown', unknown)), '{}'::jsonb)
    into v from g;
  return v;
end $$;
revoke execute on function public.admin_notif_stats(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_notif_stats(timestamptz, timestamptz) to authenticated;
