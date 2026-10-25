-- Familie Geschiedenis: database, rechten en foto-opslag
create table if not exists public.members (
  email text primary key,
  role text not null default 'viewer' check (role in ('admin','editor','viewer')),
  added_at timestamptz not null default now()
);
create table if not exists public.people   (id text primary key, data jsonb not null default '{}', created_at timestamptz not null default now());
create table if not exists public.memories (id text primary key, data jsonb not null default '{}', created_at timestamptz not null default now());
create table if not exists public.site     (id text primary key, data jsonb not null default '{}');

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.members where lower(email) = lower(auth.jwt() ->> 'email')
$$;
grant execute on function public.my_role() to authenticated;

alter table public.members  enable row level security;
alter table public.people   enable row level security;
alter table public.memories enable row level security;
alter table public.site     enable row level security;

-- leden: iedereen ziet zijn eigen regel, beheerders beheren de lijst
create policy members_read  on public.members for select to authenticated using (lower(email) = lower(auth.jwt() ->> 'email') or public.my_role() = 'admin');
create policy members_admin on public.members for all    to authenticated using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

-- inhoud: leden lezen, bewerkers en beheerders schrijven
do $$ declare t text; begin
  foreach t in array array['people','memories','site'] loop
    execute format('create policy %1$s_read  on public.%1$s for select to authenticated using (public.my_role() is not null)', t);
    execute format('create policy %1$s_write on public.%1$s for all    to authenticated using (public.my_role() in (''admin'',''editor'')) with check (public.my_role() in (''admin'',''editor''))', t);
  end loop;
end $$;

-- foto's: privé bucket, alleen leden kunnen ze zien
insert into storage.buckets (id, name, public, file_size_limit)
values ('photos', 'photos', false, 52428800) on conflict (id) do nothing;
create policy photos_read  on storage.objects for select to authenticated using (bucket_id = 'photos' and public.my_role() is not null);
create policy photos_write on storage.objects for insert to authenticated with check (bucket_id = 'photos' and public.my_role() in ('admin','editor'));
create policy photos_edit  on storage.objects for update to authenticated using (bucket_id = 'photos' and public.my_role() in ('admin','editor'));
create policy photos_del   on storage.objects for delete to authenticated using (bucket_id = 'photos' and public.my_role() in ('admin','editor'));

-- eerste beheerder
insert into public.members (email, role) values ('boazp.vanderiet@gmail.com', 'admin') on conflict (email) do update set role = 'admin';
