-- PostgreSQL design draft. Apply after onboarding.sql in an isolated test DB.
begin;
create table public.ingredients (
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null references public.bakeries(id) on delete restrict,
 name text not null check (char_length(btrim(name)) between 1 and 120),
 unit text not null check (unit in ('kg','L','unit')),
 reference_cost numeric(14,4) not null default 0 check (reference_cost between 0 and 9999999999),
 active boolean not null default true,
 unique(bakery_id,id)
);
create unique index ingredients_name_unique on public.ingredients(bakery_id,lower(btrim(name)));
create table public.stock_balances (
 bakery_id uuid not null,
 branch_id uuid not null,
 ingredient_id uuid not null,
 quantity numeric(14,3) not null default 0 check (quantity between 0 and 99999999999),
 minimum numeric(14,3) not null default 0 check (minimum between 0 and 99999999999),
 primary key(bakery_id,branch_id,ingredient_id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id),
 foreign key(bakery_id,ingredient_id) references public.ingredients(bakery_id,id)
);
create table public.stock_movements (
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null,
 branch_id uuid not null,
 ingredient_id uuid not null,
 request_id uuid not null,
 direction text not null check (direction in ('in','out')),
 quantity numeric(14,3) not null check (quantity > 0 and quantity <= 99999999999),
 reason text not null check (char_length(btrim(reason)) between 1 and 200),
 actor_id uuid not null,
 created_at timestamptz not null default now(),
 unique(bakery_id,request_id),
 foreign key(bakery_id,branch_id,ingredient_id) references public.stock_balances(bakery_id,branch_id,ingredient_id)
);
create index stock_movements_branch_time on public.stock_movements(bakery_id,branch_id,created_at desc);
alter table public.ingredients enable row level security;
alter table public.stock_balances enable row level security;
alter table public.stock_movements enable row level security;
revoke all on public.ingredients,public.stock_balances,public.stock_movements from public,anon,authenticated;
grant select on public.ingredients,public.stock_balances,public.stock_movements to authenticated;
grant insert(bakery_id,name,unit,reference_cost),update(name,reference_cost,active) on public.ingredients to authenticated;
create policy ingredients_read on public.ingredients for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=ingredients.bakery_id and m.user_id=(select auth.uid()))
);
create policy ingredients_insert on public.ingredients for insert to authenticated with check (
 exists(select 1 from public.bakery_members m where m.bakery_id=ingredients.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin'))
);
create policy ingredients_update on public.ingredients for update to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=ingredients.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin'))
) with check (
 exists(select 1 from public.bakery_members m where m.bakery_id=ingredients.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin'))
);
create policy balances_read on public.stock_balances for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=stock_balances.bakery_id and m.user_id=(select auth.uid()))
);
create policy movements_read on public.stock_movements for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=stock_movements.bakery_id and m.user_id=(select auth.uid()))
);
-- Private authorization function; no external grants.
create function bakery_private.assert_inventory_access(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_manager boolean)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not exists (
  select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid()
   and (m.role in ('owner','admin') or (not p_manager and m.role='operator'))
 ) then raise exception 'Inventory access denied' using errcode='42501'; end if;
 if not exists(select 1 from public.branches b where b.bakery_id=p_bakery and b.id=p_branch and b.active)
 or not exists(select 1 from public.ingredients i where i.bakery_id=p_bakery and i.id=p_ingredient and i.active)
 then raise exception 'Invalid or inactive branch or ingredient' using errcode='22023'; end if;
end $$;
revoke all on function bakery_private.assert_inventory_access(uuid,uuid,uuid,boolean) from public,anon,authenticated;
-- Serialize per bakery to make retries and balance changes atomic.
create function bakery_private.record_stock_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.stock_movements%rowtype; v_id uuid; v_balance numeric;
begin
 if p_request is null or p_direction is null or p_direction not in ('in','out')
 or p_quantity is null or not (p_quantity > 0 and p_quantity <= 99999999999) or p_quantity<>round(p_quantity,3)
 or p_reason is null or char_length(btrim(p_reason)) not between 1 and 200
 then raise exception 'Invalid movement' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_inventory_access(p_bakery,p_branch,p_ingredient,false);
 select * into v_old from public.stock_movements where bakery_id=p_bakery and request_id=p_request;
 if found then
  if v_old.branch_id=p_branch and v_old.ingredient_id=p_ingredient and v_old.direction=p_direction and v_old.quantity=p_quantity and v_old.reason=btrim(p_reason) and v_old.actor_id=auth.uid() then return v_old.id; end if;
  raise exception 'Request ID already used' using errcode='23505';
 end if;
 insert into public.stock_balances(bakery_id,branch_id,ingredient_id) values(p_bakery,p_branch,p_ingredient) on conflict do nothing;
 select quantity into v_balance from public.stock_balances where bakery_id=p_bakery and branch_id=p_branch and ingredient_id=p_ingredient for update;
 v_balance:=v_balance+case when p_direction='in' then p_quantity else -p_quantity end;
 if v_balance<0 or v_balance>99999999999 then raise exception 'Stock outside permitted range' using errcode='23514'; end if;
 update public.stock_balances set quantity=v_balance where bakery_id=p_bakery and branch_id=p_branch and ingredient_id=p_ingredient;
 insert into public.stock_movements(bakery_id,branch_id,ingredient_id,request_id,direction,quantity,reason,actor_id)
 values(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,btrim(p_reason),auth.uid()) returning id into v_id;
 return v_id;
end $$;
create function bakery_private.set_stock_minimum(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_minimum numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
 if p_minimum is null or not (p_minimum between 0 and 99999999999) or p_minimum<>round(p_minimum,3) then raise exception 'Invalid minimum' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_inventory_access(p_bakery,p_branch,p_ingredient,true);
 insert into public.stock_balances(bakery_id,branch_id,ingredient_id,minimum) values(p_bakery,p_branch,p_ingredient,p_minimum)
 on conflict(bakery_id,branch_id,ingredient_id) do update set minimum=excluded.minimum;
end $$;
create function public.record_stock_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text)
returns uuid language sql security invoker set search_path='' as $$ select bakery_private.record_stock_movement(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,p_reason) $$;
create function public.set_stock_minimum(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_minimum numeric)
returns void language sql security invoker set search_path='' as $$ select bakery_private.set_stock_minimum(p_bakery,p_branch,p_ingredient,p_minimum) $$;
revoke all on function bakery_private.record_stock_movement(uuid,uuid,uuid,uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function bakery_private.record_stock_movement(uuid,uuid,uuid,uuid,text,numeric,text) to authenticated;
revoke all on function bakery_private.set_stock_minimum(uuid,uuid,uuid,numeric) from public,anon,authenticated;
grant execute on function bakery_private.set_stock_minimum(uuid,uuid,uuid,numeric) to authenticated;
revoke all on function public.record_stock_movement(uuid,uuid,uuid,uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function public.record_stock_movement(uuid,uuid,uuid,uuid,text,numeric,text) to authenticated;
revoke all on function public.set_stock_minimum(uuid,uuid,uuid,numeric) from public,anon,authenticated;
grant execute on function public.set_stock_minimum(uuid,uuid,uuid,numeric) to authenticated;
commit;
