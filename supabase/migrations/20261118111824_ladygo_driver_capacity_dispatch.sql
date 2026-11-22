-- Prevent one driver from receiving multiple simultaneous offers or trips.

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
    select 1
    from public.orders
    where id = p_order_id
      and status = 'new'
      and driver_id is null
  ) then
    return null;
  end if;

  if exists (
    select 1
    from public.order_offers
    where order_id = p_order_id
      and status = 'pending'
  ) then
    return null;
  end if;

  select p.id
    into v_driver_id
  from public.orders o
  join public.profiles p
    on p.role = 'driver'
  join public.driver_presence dp
    on dp.driver_id = p.id
   and dp.is_online = true
   and dp.updated_at >= now() - interval '2 minutes'
  left join public.driver_locations dl
    on dl.driver_id = p.id
  where o.id = p_order_id
    and o.status = 'new'
    and o.driver_id is null
    -- A driver can have only one live offer at a time.
    and not exists (
      select 1
      from public.order_offers pending_offer
      where pending_offer.driver_id = p.id
        and pending_offer.status = 'pending'
    )
    -- A driver cannot receive a new offer while carrying an active trip.
    and not exists (
      select 1
      from public.orders active_trip
      where active_trip.driver_id = p.id
        and active_trip.status in ('accepted', 'arrived', 'in_progress')
    )
    -- Never send the same order to the same driver twice.
    and not exists (
      select 1
      from public.order_offers previous_offer
      where previous_offer.order_id = p_order_id
        and previous_offer.driver_id = p.id
    )
  order by
    case
      when o.pickup_lat is not null
       and o.pickup_lng is not null
       and dl.updated_at >= now() - interval '90 seconds'
      then 0 else 1
    end asc,
    case
      when o.pickup_lat is not null
       and o.pickup_lng is not null
       and dl.updated_at >= now() - interval '90 seconds'
      then
        6371.0 * acos(least(1.0, greatest(-1.0,
          sin(radians(o.pickup_lat)) * sin(radians(dl.latitude))
          + cos(radians(o.pickup_lat)) * cos(radians(dl.latitude))
          * cos(radians(dl.longitude - o.pickup_lng))
        )))
      else null
    end asc nulls last,
    dp.updated_at desc,
    p.created_at asc,
    p.id asc
  limit 1
  for update of p skip locked;

  if v_driver_id is null then
    return null;
  end if;

  insert into public.order_offers(order_id, driver_id, status)
  values (p_order_id, v_driver_id, 'pending')
  on conflict (order_id, driver_id) do nothing;

  return v_driver_id;
end;
$function$;

-- Return only the assigned driver's public trip contact fields. This avoids
-- granting passengers broad SELECT access to profiles or driver applications.
create or replace function public.ladygo_get_assigned_driver_contact(p_order_id uuid)
returns table(full_name text, phone text, experience text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select
    coalesce(application.full_name, 'Водитель LadyGo') as full_name,
    coalesce(application.phone, profile.phone) as phone,
    coalesce(application.experience, '') as experience
  from public.orders o
  join public.profiles profile on profile.id = o.driver_id
  left join lateral (
    select da.full_name, da.phone, da.experience
    from public.driver_applications da
    where da.user_id = o.driver_id and da.status = 'approved'
    order by da.reviewed_at desc nulls last, da.created_at desc
    limit 1
  ) application on true
  where o.id = p_order_id
    and o.passenger_id = (select auth.uid())
    and o.status in ('accepted', 'arrived', 'in_progress')
  limit 1;
$function$;

revoke all on function public.ladygo_get_assigned_driver_contact(uuid) from public, anon;
grant execute on function public.ladygo_get_assigned_driver_contact(uuid) to authenticated;

-- Keep intermediate stops as structured route data instead of burying them in notes.
alter table public.orders
  add column if not exists stops jsonb not null default '[]'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_stops_array_limit'
  ) then
    alter table public.orders
      add constraint orders_stops_array_limit
      check (
        case
          when jsonb_typeof(stops) = 'array' then jsonb_array_length(stops) <= 20
          else false
        end
      );
  end if;
end
$$;
