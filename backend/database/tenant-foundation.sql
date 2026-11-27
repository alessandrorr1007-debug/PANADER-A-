-- Borrador de esquema inicial. Aplicar únicamente en una base nueva de pruebas.
-- Requiere auth.users, auth.uid(), roles anon y authenticated (Supabase).
begin;
create table public.bakeries (
 id uuid primary key default gen_random_uuid(),
 name text not null check (char_length(btrim(name)) between 1 and 120),
 created_at timestamptz not null default now()
);
create table public.bakery_members (
 bakery_id uuid not null references public.bakeries(id) on delete restrict,
 user_id uuid not null references auth.users(id) on delete cascade,
 role text not null check (role in ('owner','admin','operator','viewer')),
 created_at timestamptz not null default now(),
 primary key (bakery_id,user_id)
);
create index bakery_members_user_idx on public.bakery_members(user_id,bakery_id);
create table public.branches (
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null references public.bakeries(id) on delete restrict,
 name text not null check (char_length(btrim(name)) between 1 and 120),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique (bakery_id,id),
 unique (bakery_id,name)
);
alter table public.bakeries enable row level security;
alter table public.bakery_members enable row level security;
alter table public.branches enable row level security;
-- Do not rely on default API grants.
revoke all on public.bakeries, public.bakery_members, public.branches from public, anon, authenticated;
grant select on public.bakeries, public.bakery_members, public.branches to authenticated;
grant insert (bakery_id,name,active), update (name,active) on public.branches to authenticated;
-- Memberships are provisioned by trusted administrators only. No client may grant itself a role.
create policy members_read_self on public.bakery_members
 for select to authenticated using (user_id = (select auth.uid()));
create policy bakeries_read_members on public.bakeries
 for select to authenticated using (exists (
 select 1 from public.bakery_members m where m.bakery_id=bakeries.id and m.user_id=(select auth.uid())
 ));
create policy branches_read_members on public.branches
 for select to authenticated using (exists (
 select 1 from public.bakery_members m where m.bakery_id=branches.bakery_id and m.user_id=(select auth.uid())
 ));
create policy branches_create_managers on public.branches
 for insert to authenticated with check (exists (
 select 1 from public.bakery_members m where m.bakery_id=branches.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')
 ));
create policy branches_update_managers on public.branches
 for update to authenticated using (exists (
 select 1 from public.bakery_members m where m.bakery_id=branches.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')
 )) with check (exists (
 select 1 from public.bakery_members m where m.bakery_id=branches.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')
 ));
commit;
