-- These RPCs are intended for signed-in app users only. They validate auth.uid()
-- internally, but should not be exposed to anonymous callers through PUBLIC grants.
revoke execute on function public.ladygo_cancel_active_order(uuid, text) from public, anon;
grant execute on function public.ladygo_cancel_active_order(uuid, text) to authenticated;

revoke execute on function public.ladygo_get_assigned_driver_contact(uuid) from public, anon;
grant execute on function public.ladygo_get_assigned_driver_contact(uuid) to authenticated;
