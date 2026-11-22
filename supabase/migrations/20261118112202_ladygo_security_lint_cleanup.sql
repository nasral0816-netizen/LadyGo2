-- Trigger-only webhook dispatcher must not be callable through PostgREST.
revoke all on function public.ladygo_dispatch_notification_push() from public, anon, authenticated;

-- One combined SELECT policy is equivalent and avoids duplicate permissive policy evaluation.
drop policy if exists "passengers read own order ratings" on public.order_ratings;
drop policy if exists "drivers read ratings for their trips" on public.order_ratings;
drop policy if exists "users read own or assigned trip ratings" on public.order_ratings;
create policy "users read own or assigned trip ratings"
on public.order_ratings
for select
to authenticated
using (
  passenger_id = (select auth.uid())
  or driver_id = (select auth.uid())
);
