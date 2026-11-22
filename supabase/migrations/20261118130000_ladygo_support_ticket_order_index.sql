-- Speeds up support-ticket lookups and joins by related trip.
create index if not exists support_tickets_order_id_idx
  on public.support_tickets (order_id)
  where order_id is not null;
