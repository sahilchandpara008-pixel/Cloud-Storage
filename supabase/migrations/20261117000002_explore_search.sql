-- Search in Explore: match a post's title, caption or its channel's name.
-- Still a plain (security invoker) query, so row-level security decides what
-- each user may see -- search can never surface a post the user couldn't
-- already open (audience, approval, scheduled/encoding posts all stay hidden).
--
-- p_search has a default, so app versions that call explore() with only
-- p_tab/p_limit/p_offset keep working unchanged.
drop function if exists public.explore(text, integer, integer);

create or replace function public.explore(
  p_tab    text    default 'all',
  p_limit  integer default 30,
  p_offset integer default 0,
  p_search text    default null)
returns setof public.posts
language sql stable set search_path = '' as $$
  select p.*
    from public.posts p
    cross join lateral (
      select '%' || replace(replace(replace(btrim(coalesce(p_search, '')), '\', '\\'), '%', '\%'), '_', '\_') || '%' as pat
    ) s
   where btrim(coalesce(p_search, '')) = ''
      or p.title   ilike s.pat
      or p.caption ilike s.pat
      or exists (select 1 from public.channels c
                  where c.id = p.channel_id and c.name ilike s.pat)
   order by
     case when p_tab = 'popular'      then p.like_count end desc nulls last,
     case when p_tab = 'most_watched' then p.view_count end desc nulls last,
     p.published_at desc
   limit least(p_limit, 100) offset p_offset
$$;
