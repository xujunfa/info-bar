create extension if not exists pgcrypto;

create table if not exists public.connector_events (
  id uuid primary key default gen_random_uuid(),
  connector text not null,
  provider text not null,
  event text not null,
  dedupe_key text not null unique,
  captured_at timestamptz not null,
  received_at timestamptz not null default timezone('utc', now()),
  page_url text,
  request_url text not null,
  request_method text not null,
  request_status integer,
  request_rule_id text,
  payload jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  source text not null default 'chrome_extension',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_connector_events_provider_event_captured_at
  on public.connector_events(provider, event, captured_at desc);

create index if not exists idx_connector_events_connector_created_at
  on public.connector_events(connector, created_at desc);

create index if not exists idx_connector_events_received_at
  on public.connector_events(received_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_connector_events_set_updated_at on public.connector_events;
create trigger trg_connector_events_set_updated_at
before update on public.connector_events
for each row
execute function public.set_updated_at();

alter table public.connector_events enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert on public.connector_events to anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'connector_events'
      and policyname = 'connector_events_insert_anon'
  ) then
    create policy connector_events_insert_anon
      on public.connector_events
      for insert
      to anon, authenticated
      with check (
        connector = 'info-bar-web-connector'
        and length(provider) > 0
        and length(event) > 0
      );
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'connector_events'
      and policyname = 'connector_events_select_anon'
  ) then
    create policy connector_events_select_anon
      on public.connector_events
      for select
      to anon, authenticated
      using (connector = 'info-bar-web-connector');
  end if;
end;
$$;
