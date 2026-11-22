-- Track the passenger's agreed offline payment preference.
alter table public.orders
  add column if not exists payment_method text not null default 'cash';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_payment_method_valid'
  ) then
    alter table public.orders
      add constraint orders_payment_method_valid
      check (payment_method in ('cash', 'transfer_to_driver'));
  end if;
end
$$;
