-- Only a premium user may submit a new channel request from the app. Admin
-- panel channels are unaffected (they go through the admin-creating-from-app
-- branch below, or the admin panel's own insert, neither of which is this
-- ordinary-app-user path).
create or replace function public.guard_channel_write()
returns trigger language plpgsql set search_path = '' as $$
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
    new.created_by    := auth.uid();
    new.review_status := 'pending';
    new.status        := 'draft';
    new.audience      := 'all';
    new.members_count := 0;
    new.rating        := 0;
    new.reviewed_by   := null;
    new.reviewed_at   := null;
  else
    -- Creators can edit name, handle, description, category and icon only.
    new.created_by    := old.created_by;
    new.review_status := old.review_status;
    new.status        := old.status;
    new.audience      := old.audience;
    new.members_count := old.members_count;
    new.rating        := old.rating;
    new.reviewed_by   := old.reviewed_by;
    new.reviewed_at   := old.reviewed_at;
  end if;
  return new;
end $$;
