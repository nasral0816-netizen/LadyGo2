alter table public.driver_applications
  add column if not exists vehicle_make text,
  add column if not exists vehicle_model text,
  add column if not exists vehicle_color text,
  add column if not exists vehicle_plate text,
  add column if not exists vehicle_year smallint,
  add column if not exists avatar_url text,
  add column if not exists vehicle_photo_url text;

create table if not exists public.driver_profiles (
  driver_id uuid primary key references public.profiles(id) on delete cascade,
  display_name text not null default '',
  phone text,
  experience text,
  vehicle_make text,
  vehicle_model text,
  vehicle_color text,
  vehicle_plate text,
  vehicle_year smallint check (vehicle_year is null or vehicle_year between 1950 and 2100),
  avatar_url text,
  vehicle_photo_url text,
  updated_at timestamptz not null default now(),
  constraint driver_profiles_display_name_length check (char_length(display_name) <= 120),
  constraint driver_profiles_phone_length check (phone is null or char_length(phone) <= 32),
  constraint driver_profiles_plate_length check (vehicle_plate is null or char_length(vehicle_plate) <= 24)
);
create index if not exists driver_profiles_name_idx on public.driver_profiles(display_name);
alter table public.driver_profiles enable row level security;

drop policy if exists "driver profiles read own admin or active passenger" on public.driver_profiles;
create policy "driver profiles read own admin or active passenger" on public.driver_profiles
for select to authenticated using (
  driver_id = (select auth.uid())
  or public.ladygo_is_admin()
  or exists (
    select 1 from public.orders o
    where o.driver_id = driver_profiles.driver_id
      and o.passenger_id = (select auth.uid())
      and o.status in ('accepted', 'arrived', 'in_progress')
  )
);
drop policy if exists "drivers update own profile" on public.driver_profiles;
create policy "drivers update own profile" on public.driver_profiles
for update to authenticated
using (driver_id = (select auth.uid()) and exists (
  select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'driver'
))
with check (driver_id = (select auth.uid()) and exists (
  select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'driver'
));
drop policy if exists "drivers create own profile" on public.driver_profiles;
create policy "drivers create own profile" on public.driver_profiles
for insert to authenticated with check (
  driver_id = (select auth.uid()) and exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'driver'
  )
);
grant select, insert, update on public.driver_profiles to authenticated;

create or replace function public.ladygo_review_driver_application()
returns trigger language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'admin') then
    raise exception 'Только администратор может проверять заявки';
  end if;
  if old.status = 'pending' and new.status in ('approved','rejected') then
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
    if new.status = 'approved' then
      update public.profiles set role = 'driver', phone = new.phone where id = new.user_id;
      insert into public.driver_profiles (
        driver_id, display_name, phone, experience, vehicle_make, vehicle_model,
        vehicle_color, vehicle_plate, vehicle_year, avatar_url, vehicle_photo_url, updated_at
      ) values (
        new.user_id, new.full_name, new.phone, new.experience, new.vehicle_make, new.vehicle_model,
        new.vehicle_color, new.vehicle_plate, new.vehicle_year, new.avatar_url, new.vehicle_photo_url, now()
      )
      on conflict (driver_id) do update set
        display_name = excluded.display_name, phone = excluded.phone, experience = excluded.experience,
        vehicle_make = excluded.vehicle_make, vehicle_model = excluded.vehicle_model,
        vehicle_color = excluded.vehicle_color, vehicle_plate = excluded.vehicle_plate,
        vehicle_year = excluded.vehicle_year, avatar_url = excluded.avatar_url,
        vehicle_photo_url = excluded.vehicle_photo_url, updated_at = now();
    end if;
  elsif new.user_id is distinct from old.user_id
     or new.full_name is distinct from old.full_name
     or new.phone is distinct from old.phone
     or new.experience is distinct from old.experience
     or new.vehicle_make is distinct from old.vehicle_make
     or new.vehicle_model is distinct from old.vehicle_model
     or new.vehicle_color is distinct from old.vehicle_color
     or new.vehicle_plate is distinct from old.vehicle_plate
     or new.vehicle_year is distinct from old.vehicle_year
     or new.avatar_url is distinct from old.avatar_url
     or new.vehicle_photo_url is distinct from old.vehicle_photo_url
     or new.status is distinct from old.status then
    raise exception 'Недопустимое изменение заявки';
  end if;
  return new;
end;
$function$;

insert into public.driver_profiles (
  driver_id, display_name, phone, experience, vehicle_make, vehicle_model,
  vehicle_color, vehicle_plate, vehicle_year, avatar_url, vehicle_photo_url
)
select distinct on (da.user_id)
  da.user_id, da.full_name, da.phone, da.experience, da.vehicle_make, da.vehicle_model,
  da.vehicle_color, da.vehicle_plate, da.vehicle_year, da.avatar_url, da.vehicle_photo_url
from public.driver_applications da
join public.profiles p on p.id = da.user_id and p.role = 'driver'
where da.status = 'approved'
order by da.user_id, da.reviewed_at desc nulls last, da.created_at desc
on conflict (driver_id) do nothing;

drop policy if exists "passengers rate own completed trips" on public.order_ratings;
create policy "passengers rate own completed trips" on public.order_ratings
for insert to authenticated with check (
  passenger_id = (select auth.uid())
  and exists (
    select 1 from public.orders o
    where o.id = order_ratings.order_id
      and o.passenger_id = (select auth.uid())
      and o.driver_id = order_ratings.driver_id
      and o.status = 'completed'
  )
);

drop function if exists public.ladygo_get_assigned_driver_contact(uuid);
create function public.ladygo_get_assigned_driver_contact(p_order_id uuid)
returns table (
  full_name text, phone text, experience text, avatar_url text,
  vehicle_make text, vehicle_model text, vehicle_color text, vehicle_plate text,
  vehicle_year smallint, vehicle_photo_url text, average_rating numeric, rating_count bigint
)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
  select
    coalesce(dp.display_name, 'Водитель LadyGo'), dp.phone, coalesce(dp.experience, ''),
    dp.avatar_url, dp.vehicle_make, dp.vehicle_model, dp.vehicle_color, dp.vehicle_plate,
    dp.vehicle_year, dp.vehicle_photo_url,
    (select round(avg(r.rating)::numeric, 1) from public.order_ratings r where r.driver_id = o.driver_id),
    (select count(*) from public.order_ratings r where r.driver_id = o.driver_id)
  from public.orders o
  join public.driver_profiles dp on dp.driver_id = o.driver_id
  where o.id = p_order_id and o.passenger_id = (select auth.uid())
    and o.status in ('accepted', 'arrived', 'in_progress')
  limit 1;
$function$;
revoke all on function public.ladygo_get_assigned_driver_contact(uuid) from public, anon;
grant execute on function public.ladygo_get_assigned_driver_contact(uuid) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ladygo-driver-media', 'ladygo-driver-media', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "ladygo driver media upload own" on storage.objects;
create policy "ladygo driver media upload own" on storage.objects
for insert to authenticated with check (
  bucket_id = 'ladygo-driver-media' and (storage.foldername(name))[1] = (select auth.uid()::text)
);
drop policy if exists "ladygo driver media read own for replacement" on storage.objects;
create policy "ladygo driver media read own for replacement" on storage.objects
for select to authenticated using (
  bucket_id = 'ladygo-driver-media' and (storage.foldername(name))[1] = (select auth.uid()::text)
);
drop policy if exists "ladygo driver media update own" on storage.objects;
create policy "ladygo driver media update own" on storage.objects
for update to authenticated using (
  bucket_id = 'ladygo-driver-media' and (storage.foldername(name))[1] = (select auth.uid()::text)
) with check (
  bucket_id = 'ladygo-driver-media' and (storage.foldername(name))[1] = (select auth.uid()::text)
);
drop policy if exists "ladygo driver media delete own" on storage.objects;
create policy "ladygo driver media delete own" on storage.objects
for delete to authenticated using (
  bucket_id = 'ladygo-driver-media' and (storage.foldername(name))[1] = (select auth.uid()::text)
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'driver_profiles'
  ) then
    alter publication supabase_realtime add table public.driver_profiles;
  end if;
end
$$;
