-- Run this in Supabase SQL Editor as project owner.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'passenger' check (role in ('passenger','driver','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  passenger_id uuid not null references public.profiles(id),
  driver_id uuid references public.profiles(id),
  pickup_address text not null,
  destination_address text not null,
  requested_for text not null default 'Как можно скорее',
  notes text,
  price_rub numeric(10,2) check (price_rub is null or price_rub > 0),
  status text not null default 'new' check (status in ('new','accepted','declined','cancelled','completed')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.orders enable row level security;

-- Profiles: each user can read/update only their own profile.
drop policy if exists "profile read own" on public.profiles;
create policy "profile read own" on public.profiles for select to authenticated using (id = auth.uid());
-- Profile role changes are intentionally not available to app users.
-- Change a trusted driver's role manually as project owner in the Supabase dashboard.

-- Create own passenger order; passengers can read their own orders.
drop policy if exists "passenger create own order" on public.orders;
create policy "passenger create own order" on public.orders for insert to authenticated with check (passenger_id = auth.uid() and driver_id is null and status = 'new' and price_rub is null);
drop policy if exists "passenger read own orders" on public.orders;
create policy "passenger read own orders" on public.orders for select to authenticated using (passenger_id = auth.uid());

-- Driver reads unassigned new orders and orders assigned to them.
drop policy if exists "driver read orders" on public.orders;
create policy "driver read orders" on public.orders for select to authenticated using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('driver','admin'))
  and (status = 'new' or driver_id = auth.uid())
);
-- Driver can accept/reject new unassigned orders or update their own accepted orders.
drop policy if exists "driver update orders" on public.orders;
create policy "driver update orders" on public.orders for update to authenticated using (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('driver','admin'))
  and (status = 'new' or driver_id = auth.uid())
) with check (
  exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('driver','admin'))
  and (driver_id = auth.uid() or (driver_id is null and status in ('declined','cancelled')))
);

-- Create a profile automatically after signup.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id,email,role) values (new.id,new.email,'passenger');
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Realtime: enable orders table in Supabase Dashboard > Database > Publications if desired.

-- Enforce immutable order details and a narrow driver state machine.
create or replace function public.guard_order_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  select p.role into actor_role from public.profiles p where p.id = auth.uid();
  if actor_role not in ('driver','admin') then
    raise exception 'Only an assigned driver can update an order';
  end if;
  if new.passenger_id is distinct from old.passenger_id
     or new.pickup_address is distinct from old.pickup_address
     or new.destination_address is distinct from old.destination_address
     or new.requested_for is distinct from old.requested_for
     or new.notes is distinct from old.notes
     or new.created_at is distinct from old.created_at then
    raise exception 'Order details are immutable';
  end if;
  if old.status = 'new' and new.status = 'accepted'
     and new.driver_id = auth.uid() and new.price_rub > 0 then
    return new;
  elsif old.status = 'new' and new.status = 'declined'
     and new.driver_id is null and new.price_rub is null then
    return new;
  elsif old.status = 'accepted' and old.driver_id = auth.uid()
     and new.driver_id = old.driver_id and new.price_rub = old.price_rub
     and new.status = 'completed' then
    return new;
  end if;
  raise exception 'Invalid order status transition';
end;
$$;
drop trigger if exists guard_order_update on public.orders;
create trigger guard_order_update before update on public.orders
for each row execute procedure public.guard_order_update();

-- LadyGo 1.1 additions: passenger contact and safe cancellation of unaccepted orders.
alter table public.profiles add column if not exists phone text;
alter table public.orders add column if not exists passenger_phone text;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id,email,role,phone)
  values (new.id,new.email,'passenger',nullif(new.raw_user_meta_data->>'phone',''))
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function public.guard_order_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor_role text;
begin
  select p.role into actor_role from public.profiles p where p.id = auth.uid();
  if new.passenger_id is distinct from old.passenger_id
     or new.passenger_phone is distinct from old.passenger_phone
     or new.pickup_lat is distinct from old.pickup_lat
     or new.pickup_lng is distinct from old.pickup_lng
     or new.pickup_address is distinct from old.pickup_address
     or new.destination_address is distinct from old.destination_address
     or new.requested_for is distinct from old.requested_for
     or new.notes is distinct from old.notes
     or new.created_at is distinct from old.created_at then
    raise exception 'Order details are immutable';
  end if;
  if actor_role in ('driver','admin') then
    if old.status = 'new' and new.status = 'accepted'
       and new.driver_id = auth.uid() and new.price_rub > 0 then return new;
    elsif old.status = 'new' and new.status = 'declined'
       and new.driver_id is null and new.price_rub is null then return new;
    elsif old.status = 'accepted' and old.driver_id = auth.uid()
       and new.driver_id = old.driver_id and new.price_rub = old.price_rub
       and new.status = 'completed' then return new;
    end if;
  elsif actor_role = 'passenger' and old.passenger_id = auth.uid()
        and old.status = 'new' and new.status = 'cancelled'
        and new.driver_id is null and new.price_rub is null then
    return new;
  end if;
  raise exception 'Invalid order status transition';
end;
$$;

create or replace function public.cancel_my_order(order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.orders set status = 'cancelled'
  where id = order_id and passenger_id = auth.uid() and status = 'new';
  if not found then raise exception 'Only your new, not-yet-accepted order can be cancelled'; end if;
end;
$$;
revoke all on function public.cancel_my_order(uuid) from public;
grant execute on function public.cancel_my_order(uuid) to authenticated;

-- Enable Realtime delivery for order changes (safe to run repeatedly).
do $$ begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null;
when undefined_object then null;
end $$;


-- LadyGo 1.2: pickup GPS coordinates. Coordinates are optional; manual addresses remain supported.
alter table public.orders add column if not exists pickup_lat double precision;
alter table public.orders add column if not exists pickup_lng double precision;
alter table public.orders drop constraint if exists pickup_coordinates_pair;
alter table public.orders add constraint pickup_coordinates_pair check (
  (pickup_lat is null and pickup_lng is null) or
  (pickup_lat between -90 and 90 and pickup_lng between -180 and 180)
);
