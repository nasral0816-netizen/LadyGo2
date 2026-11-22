-- Enforce the app's one-active-order-per-passenger and one-active-trip-per-driver rules
-- at the database layer as well as in the mobile UI.
create unique index if not exists orders_one_active_per_passenger_idx
  on public.orders(passenger_id)
  where status in ('new', 'accepted', 'arrived', 'in_progress');

create unique index if not exists orders_one_active_per_driver_idx
  on public.orders(driver_id)
  where driver_id is not null
    and status in ('accepted', 'arrived', 'in_progress');
