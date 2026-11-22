-- Passenger ratings for completed trips, with driver-only read access.
create table if not exists public.order_ratings (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  passenger_id uuid not null references public.profiles(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  constraint order_ratings_one_per_order unique (order_id)
);

create index if not exists order_ratings_driver_created_idx
  on public.order_ratings(driver_id, created_at desc);
create index if not exists order_ratings_passenger_created_idx
  on public.order_ratings(passenger_id, created_at desc);

alter table public.order_ratings enable row level security;

drop policy if exists "passengers read own order ratings" on public.order_ratings;
create policy "passengers read own order ratings"
on public.order_ratings
for select
to authenticated
using (passenger_id = (select auth.uid()));

drop policy if exists "drivers read ratings for their trips" on public.order_ratings;
create policy "drivers read ratings for their trips"
on public.order_ratings
for select
to authenticated
using (driver_id = (select auth.uid()));

drop policy if exists "passengers rate own completed trips" on public.order_ratings;
create policy "passengers rate own completed trips"
on public.order_ratings
for insert
to authenticated
with check (
  passenger_id = (select auth.uid())
  and exists (
    select 1
    from public.orders o
    where o.id = order_id
      and o.passenger_id = (select auth.uid())
      and o.driver_id = driver_id
      and o.status = 'completed'
  )
);
