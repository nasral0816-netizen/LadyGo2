-- Admin-configurable tariff rates. Rates start disabled until the operator
-- enters the real local prices; no fictional fare is shown to passengers.
create table if not exists public.tariff_rates (
  tariff_id text primary key check (tariff_id in ('economy', 'comfort', 'child')),
  base_fare_rub numeric(10,2) not null default 0 check (base_fare_rub >= 0),
  per_km_rub numeric(10,2) not null default 0 check (per_km_rub >= 0),
  minimum_fare_rub numeric(10,2) not null default 0 check (minimum_fare_rub >= 0),
  is_active boolean not null default false,
  updated_at timestamptz not null default now()
);

insert into public.tariff_rates (tariff_id)
values ('economy'), ('comfort'), ('child')
on conflict (tariff_id) do nothing;

alter table public.tariff_rates enable row level security;

drop policy if exists "authenticated read tariff rates" on public.tariff_rates;
create policy "authenticated read tariff rates"
on public.tariff_rates
for select
to authenticated
using (true);

drop policy if exists "admins insert tariff rates" on public.tariff_rates;
create policy "admins insert tariff rates"
on public.tariff_rates
for insert
to authenticated
with check (public.ladygo_is_admin());

drop policy if exists "admins update tariff rates" on public.tariff_rates;
create policy "admins update tariff rates"
on public.tariff_rates
for update
to authenticated
using (public.ladygo_is_admin())
with check (public.ladygo_is_admin());

drop policy if exists "admins delete tariff rates" on public.tariff_rates;
create policy "admins delete tariff rates"
on public.tariff_rates
for delete
to authenticated
using (public.ladygo_is_admin());

alter table public.orders
  add column if not exists tariff_id text,
  add column if not exists estimated_price_rub numeric(10,2);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_tariff_id_valid'
  ) then
    alter table public.orders
      add constraint orders_tariff_id_valid
      check (tariff_id is null or tariff_id in ('economy', 'comfort', 'child'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_estimated_price_nonnegative'
  ) then
    alter table public.orders
      add constraint orders_estimated_price_nonnegative
      check (estimated_price_rub is null or estimated_price_rub >= 0);
  end if;
end
$$;
