create or replace function public.ladygo_dispatch_next_driver(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_driver_id uuid;
begin
  if not exists (
    select 1 from public.orders
    where id = p_order_id and status = 'new' and driver_id is null
      and (scheduled_at is null or scheduled_at <= now())
  ) then return null; end if;

  if exists (select 1 from public.order_offers where order_id = p_order_id and status = 'pending') then
    return null;
  end if;

  select p.id into v_driver_id
  from public.orders o
  join public.profiles p on p.role = 'driver'
  join public.driver_presence dp on dp.driver_id = p.id
    and dp.is_online = true and dp.updated_at >= now() - interval '2 minutes'
  join public.driver_locations dl on dl.driver_id = p.id
    and dl.updated_at >= now() - interval '90 seconds'
  where o.id = p_order_id and o.status = 'new' and o.driver_id is null
    and (o.scheduled_at is null or o.scheduled_at <= now())
    and o.pickup_lat is not null and o.pickup_lng is not null
    -- Live GPS matching: 80 km covers KMW and nearby towns, excluding remote cities.
    and 6371.0 * acos(least(1.0, greatest(-1.0,
      sin(radians(o.pickup_lat)) * sin(radians(dl.latitude))
      + cos(radians(o.pickup_lat)) * cos(radians(dl.latitude))
      * cos(radians(dl.longitude - o.pickup_lng))
    ))) <= 80
    and not exists (select 1 from public.order_offers pending_offer
      where pending_offer.driver_id = p.id and pending_offer.status = 'pending')
    and not exists (select 1 from public.orders active_trip
      where active_trip.driver_id = p.id and active_trip.status in ('accepted', 'arrived', 'in_progress'))
    and not exists (select 1 from public.order_offers previous_offer
      where previous_offer.order_id = p_order_id and previous_offer.driver_id = p.id)
  order by
    6371.0 * acos(least(1.0, greatest(-1.0,
      sin(radians(o.pickup_lat)) * sin(radians(dl.latitude))
      + cos(radians(o.pickup_lat)) * cos(radians(dl.latitude))
      * cos(radians(dl.longitude - o.pickup_lng))
    ))),
    dp.updated_at desc, p.created_at asc, p.id asc
  limit 1 for update of p skip locked;

  if v_driver_id is null then return null; end if;
  insert into public.order_offers(order_id, driver_id, status)
  values (p_order_id, v_driver_id, 'pending')
  on conflict (order_id, driver_id) do nothing;
  return v_driver_id;
end;
$function$;
