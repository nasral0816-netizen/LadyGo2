-- In-trip passenger/driver chat with participant-only access.
create table if not exists public.trip_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(btrim(message)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists trip_messages_order_created_idx
  on public.trip_messages(order_id, created_at);

alter table public.trip_messages enable row level security;

drop policy if exists "Trip participants can read messages" on public.trip_messages;
create policy "Trip participants can read messages"
on public.trip_messages for select to authenticated
using (
  exists (
    select 1 from public.orders o
    where o.id = trip_messages.order_id
      and auth.uid() in (o.passenger_id, o.driver_id)
  )
);

drop policy if exists "Trip participants can send messages" on public.trip_messages;
create policy "Trip participants can send messages"
on public.trip_messages for insert to authenticated
with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.orders o
    where o.id = trip_messages.order_id
      and auth.uid() in (o.passenger_id, o.driver_id)
      and o.status in ('accepted', 'arrived', 'in_progress')
  )
);


do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'trip_messages'
  ) then
    alter publication supabase_realtime add table public.trip_messages;
  end if;
end $$;
