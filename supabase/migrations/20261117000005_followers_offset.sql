-- Follower count the admin can set.
--
-- channels.members_count is the number every app version shows. It used to
-- be exactly the number of joins (recounted on each join/leave). The admin
-- can now type the number to show; the difference from the real joins is
-- kept as followers_offset, so a join still adds one and a leave removes
-- one on top of the admin's number.

alter table public.channels
  add column if not exists followers_offset integer not null default 0;

create or replace function public.sync_members_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.channels c
     set members_count = greatest(0,
           (select count(*) from public.channel_members
             where channel_id = coalesce(new.channel_id, old.channel_id))
           + c.followers_offset)
   where c.id = coalesce(new.channel_id, old.channel_id);
  return null;
end $$;

-- Set the followers shown for a channel (admins only). Returns the number now
-- shown.
create or replace function public.admin_set_followers(p_channel_id uuid, p_shown integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_real integer;
begin
  if not public.is_admin() then
    raise exception 'admins only';
  end if;
  if p_shown is null or p_shown < 0 or p_shown > 1000000000 then
    raise exception 'followers must be between 0 and 1,000,000,000';
  end if;
  select count(*) into v_real from public.channel_members where channel_id = p_channel_id;
  update public.channels
     set followers_offset = p_shown - v_real,
         members_count    = p_shown
   where id = p_channel_id;
  if not found then
    raise exception 'channel not found';
  end if;
  return p_shown;
end $$;

revoke execute on function public.admin_set_followers(uuid, integer) from public, anon;
grant execute on function public.admin_set_followers(uuid, integer) to authenticated;

-- Creators must not be able to raise their own channel's followers: the
-- write guard now also pins followers_offset (same as members_count).
create or replace function public.guard_channel_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Admin creating from the app: record them as creator and queue for review.
  if tg_op = 'INSERT' and new.created_by is null
     and current_user in ('authenticated', 'anon') and public.is_admin() then
    new.created_by    := auth.uid();
    new.review_status := 'pending';
    new.status        := 'draft';
    new.audience      := 'all';
    return new;
  end if;

  -- Only direct writes from app users are restricted; internal updates made by
  -- the database's own functions (counters, reviews) and admins pass through.
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if not public.is_premium_user() then
      raise exception 'an active plan is required to create a channel';
    end if;
    if (select count(*) from public.channels
         where created_by = auth.uid() and review_status = 'pending') >= 3 then
      raise exception 'you already have 3 channels waiting for approval';
    end if;
    new.created_by       := auth.uid();
    new.review_status    := 'pending';
    new.status           := 'draft';
    new.audience         := 'all';
    new.members_count    := 0;
    new.followers_offset := 0;
    new.rating           := 0;
    new.reviewed_by      := null;
    new.reviewed_at      := null;
  else
    -- Creators can edit name, handle, description, category and icon only.
    new.created_by       := old.created_by;
    new.review_status    := old.review_status;
    new.status           := old.status;
    new.audience         := old.audience;
    new.members_count    := old.members_count;
    new.followers_offset := old.followers_offset;
    new.rating           := old.rating;
    new.reviewed_by      := old.reviewed_by;
    new.reviewed_at      := old.reviewed_at;
  end if;
  return new;
end $$;
