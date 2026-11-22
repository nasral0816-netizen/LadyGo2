-- Notify the user when an administrator replies to a support ticket.
create or replace function public.ladygo_notify_support_reply()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.admin_reply is not null
     and new.admin_reply is distinct from old.admin_reply then
    insert into public.notifications(user_id, order_id, kind, title, body)
    values (
      new.user_id,
      new.order_id,
      'support_reply',
      'Ответ поддержки LadyGo',
      left(new.admin_reply, 1000)
    );
  end if;
  return new;
end;
$function$;

revoke all on function public.ladygo_notify_support_reply() from public, anon, authenticated;

drop trigger if exists ladygo_support_reply_notification_trigger on public.support_tickets;
create trigger ladygo_support_reply_notification_trigger
after update of admin_reply on public.support_tickets
for each row
execute function public.ladygo_notify_support_reply();
