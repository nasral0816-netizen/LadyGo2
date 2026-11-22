-- Keep auth.uid() as a statement-level initplan in chat policies and index sender lookups.
drop policy if exists "Trip participants can read messages" on public.trip_messages;
create policy "Trip participants can read messages"
on public.trip_messages for select to authenticated
using (
  exists (
    select 1
    from public.orders o
    where o.id = trip_messages.order_id
      and (select auth.uid()) in (o.passenger_id, o.driver_id)
  )
);

drop policy if exists "Trip participants can send messages" on public.trip_messages;
create policy "Trip participants can send messages"
on public.trip_messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and exists (
    select 1
    from public.orders o
    where o.id = trip_messages.order_id
      and (select auth.uid()) in (o.passenger_id, o.driver_id)
      and o.status in ('accepted', 'arrived', 'in_progress')
  )
);

create index if not exists trip_messages_sender_id_idx
  on public.trip_messages(sender_id);
