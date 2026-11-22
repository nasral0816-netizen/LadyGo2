-- In-app support requests for passengers and drivers.
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  subject text not null check (char_length(trim(subject)) between 3 and 120),
  message text not null check (char_length(trim(message)) between 5 and 4000),
  status text not null default 'open' check (status in ('open', 'in_progress', 'resolved')),
  admin_reply text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists support_tickets_user_created_idx
  on public.support_tickets(user_id, created_at desc);
create index if not exists support_tickets_status_created_idx
  on public.support_tickets(status, created_at desc);

alter table public.support_tickets enable row level security;

drop policy if exists "users and admins read support tickets" on public.support_tickets;
create policy "users and admins read support tickets"
on public.support_tickets
for select
to authenticated
using (user_id = (select auth.uid()) or public.ladygo_is_admin());

drop policy if exists "users create own support tickets" on public.support_tickets;
create policy "users create own support tickets"
on public.support_tickets
for insert
to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists "admins update support tickets" on public.support_tickets;
create policy "admins update support tickets"
on public.support_tickets
for update
to authenticated
using (public.ladygo_is_admin())
with check (public.ladygo_is_admin());
