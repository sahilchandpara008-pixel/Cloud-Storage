-- Google Play version: free cloud storage (15 GB) for logged-in users.
-- The Play build calls enable_play_free_cloud() after login; the shared APKs
-- never call it, so their flow (cloud = Premium only) is unchanged.
-- Premium stays 2 TB. Downloads stay Premium only.

alter table public.profiles add column if not exists free_cloud_bytes bigint not null default 0
  check (free_cloud_bytes >= 0);

create or replace function public.enable_play_free_cloud()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'please log in'; end if;
  update public.profiles
     set free_cloud_bytes = greatest(free_cloud_bytes, 16106127360)   -- 15 GB
   where id = auth.uid() and not is_guest;
end $$;

revoke execute on function public.enable_play_free_cloud() from public, anon;
grant execute on function public.enable_play_free_cloud() to authenticated;

create or replace function public.quota_bytes(p_user_id uuid)
returns bigint language sql stable security definer set search_path = '' as $$
  select case when exists (select 1 from public.subscriptions
                            where user_id = p_user_id and now() between starts_at and ends_at)
              then 2199023255552::bigint   -- 2 TB for premium
              else coalesce((select free_cloud_bytes from public.profiles where id = p_user_id), 0)
         end
$$;

-- Uploading needs storage space (Premium, or the Play free allowance).
drop policy if exists cloud_insert_own on storage.objects;
create policy cloud_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'cloud'
              and (storage.foldername(name))[1] = (select auth.uid())::text
              and public.quota_bytes((select auth.uid())) > 0);

drop policy if exists cloud_files_insert on public.cloud_files;
create policy cloud_files_insert on public.cloud_files for insert
  with check (user_id = (select auth.uid()) and public.quota_bytes((select auth.uid())) > 0);
