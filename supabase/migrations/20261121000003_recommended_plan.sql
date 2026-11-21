-- One plan can be marked "Recommended" in admin → Plans: the app pre-selects
-- it and shows a "Most popular" badge. None = the first plan is selected.

alter table public.plans add column if not exists recommended boolean not null default false;
create unique index if not exists plans_one_recommended on public.plans (recommended) where recommended;

create or replace function public.admin_set_recommended_plan(p_plan_id uuid default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'only the owner can change plans'; end if;
  if p_plan_id is not null and not exists (select 1 from public.plans where id = p_plan_id) then
    raise exception 'plan not found';
  end if;
  update public.plans set recommended = false where recommended and id is distinct from p_plan_id;
  if p_plan_id is not null then
    update public.plans set recommended = true where id = p_plan_id;
  end if;
end $$;
revoke execute on function public.admin_set_recommended_plan(uuid) from public, anon;
grant execute on function public.admin_set_recommended_plan(uuid) to authenticated;
