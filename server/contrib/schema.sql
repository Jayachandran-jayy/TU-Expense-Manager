-- Anonymous bank SMS format samples sent from the app.
-- Apply once in the Supabase SQL editor for the project that CONTRIB_URL points to.
--
-- The app authenticates with the public anon key. The policy below lets it insert
-- rows and nothing else. It cannot read, update or delete them, so the key shipped
-- in the app cannot expose the collected samples. Read them from the Supabase
-- dashboard (service role), then run tool/train/import_supabase_export.py.

create table if not exists public.sms_contributions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  bank text not null check (char_length(bank) <= 80),
  txn_type text not null check (txn_type in ('debit', 'credit')),
  amount numeric check (amount is null or amount >= 0),
  merchant text not null check (char_length(merchant) <= 80),
  sanitized_sms text not null check (char_length(sanitized_sms) between 1 and 1000),
  reviewed boolean not null default false
);

alter table public.sms_contributions enable row level security;

revoke all on public.sms_contributions from anon, authenticated;
grant insert on public.sms_contributions to anon;

create policy "anon can insert samples"
  on public.sms_contributions
  for insert
  to anon
  with check (true);
