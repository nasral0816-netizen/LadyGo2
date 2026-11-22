-- Register push tokens for passengers and drivers, and dispatch each in-app
-- notification as a device push through the authenticated Edge Function.
create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  expo_push_token text not null,
  device_platform text not null check (device_platform in ('android', 'ios')),
  updated_at timestamptz not null default now(),
  constraint user_push_tokens_user_token_key unique (user_id, expo_push_token)
);

create index if not exists user_push_tokens_user_id_idx
  on public.user_push_tokens(user_id);

alter table public.user_push_tokens enable row level security;

drop policy if exists "users manage own push tokens" on public.user_push_tokens;
create policy "users manage own push tokens"
on public.user_push_tokens
for all
to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

alter table public.notifications
  add column if not exists push_sent_at timestamptz;

create or replace function public.ladygo_dispatch_notification_push()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'vault', 'net', 'pg_temp'
as $function$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'ladygo_push_webhook_secret';

  if v_secret is null then
    raise warning 'LadyGo push webhook secret is missing; notification push was not dispatched';
    return new;
  end if;

  perform net.http_post(
    url := 'https://itlzvcklnxznrtaqjttc.supabase.co/functions/v1/send-driver-offer-push',
    body := jsonb_build_object('notification', to_jsonb(new)),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-ladygo-webhook-secret', v_secret
    ),
    timeout_milliseconds := 5000
  );

  return new;
end;
$function$;

drop trigger if exists ladygo_notification_push_trigger on public.notifications;
create trigger ladygo_notification_push_trigger
after insert on public.notifications
for each row
execute function public.ladygo_dispatch_notification_push();
