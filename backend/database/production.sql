-- Design draft: apply after inventory.sql, only in an isolated test database.
begin;
create table public.recipe_versions (
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null references public.bakeries(id),
 name text not null check(char_length(btrim(name)) between 1 and 120),
 version integer not null check(version>0),
 yield_units integer not null check(yield_units between 1 and 1000000),
 created_by uuid not null,
 created_at timestamptz not null default now(),
 unique(bakery_id,id)
);
create unique index recipe_version_name_unique on public.recipe_versions(bakery_id,lower(name),version);
create table public.recipe_items (
 bakery_id uuid not null,
 recipe_id uuid not null,
 ingredient_id uuid not null,
 quantity numeric(14,3) not null check(quantity>0 and quantity<=99999999999),
 primary key(bakery_id,recipe_id,ingredient_id),
 foreign key(bakery_id,recipe_id) references public.recipe_versions(bakery_id,id),
 foreign key(bakery_id,ingredient_id) references public.ingredients(bakery_id,id)
);
create table public.production_batches (
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null,
 branch_id uuid not null,
 recipe_id uuid not null,
 request_id uuid not null,
 output_units integer not null check(output_units between 1 and 1000000),
 reference_cost numeric(30,7) not null default 0 check(reference_cost>=0),
 actor_id uuid not null,
 created_at timestamptz not null default now(),
 unique(bakery_id,id),
 unique(bakery_id,request_id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id),
 foreign key(bakery_id,recipe_id) references public.recipe_versions(bakery_id,id)
);
alter table public.stock_movements add constraint stock_movements_bakery_id_unique unique(bakery_id,id);
create table public.production_consumption (
 bakery_id uuid not null,
 batch_id uuid not null,
 ingredient_id uuid not null,
 movement_id uuid not null,
 quantity numeric(14,3) not null check(quantity>0),
 unit_cost numeric(14,4) not null check(unit_cost>=0),
 primary key(bakery_id,batch_id,ingredient_id),
 unique(bakery_id,movement_id),
 foreign key(bakery_id,batch_id) references public.production_batches(bakery_id,id),
 foreign key(bakery_id,ingredient_id) references public.ingredients(bakery_id,id),
 foreign key(bakery_id,movement_id) references public.stock_movements(bakery_id,id)
);
alter table public.recipe_versions enable row level security;
revoke all on public.recipe_versions from public,anon,authenticated;
grant select on public.recipe_versions to authenticated;
create policy recipe_versions_read on public.recipe_versions for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=recipe_versions.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.recipe_items enable row level security;
revoke all on public.recipe_items from public,anon,authenticated;
grant select on public.recipe_items to authenticated;
create policy recipe_items_read on public.recipe_items for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=recipe_items.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.production_batches enable row level security;
revoke all on public.production_batches from public,anon,authenticated;
grant select on public.production_batches to authenticated;
create policy production_batches_read on public.production_batches for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=production_batches.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.production_consumption enable row level security;
revoke all on public.production_consumption from public,anon,authenticated;
grant select on public.production_consumption to authenticated;
create policy production_consumption_read on public.production_consumption for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=production_consumption.bakery_id and m.user_id=(select auth.uid()))
);
create function bakery_private.create_recipe_version(p_bakery uuid,p_name text,p_yield integer,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_recipe uuid; v_version integer; v_item jsonb; v_ingredient uuid; v_quantity numeric;
begin
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid() and m.role in ('owner','admin'))
 then raise exception 'Recipe access denied' using errcode='42501'; end if;
 if p_name is null or char_length(btrim(p_name)) not between 1 and 120 or p_yield is null or p_yield not between 1 and 1000000
 or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Invalid recipe' using errcode='22023'; end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid ingredient count' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 select coalesce(max(r.version),0)+1 into v_version from public.recipe_versions r where r.bakery_id=p_bakery and lower(r.name)=lower(btrim(p_name));
 insert into public.recipe_versions(bakery_id,name,version,yield_units,created_by)
 values(p_bakery,btrim(p_name),v_version,p_yield,auth.uid()) returning id into v_recipe;
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_ingredient:=(v_item->>'ingredient_id')::uuid; v_quantity:=(v_item->>'quantity')::numeric;
  if v_quantity is null or not (v_quantity>0 and v_quantity<=99999999999) or v_quantity<>round(v_quantity,3)
  or not exists(select 1 from public.ingredients i where i.bakery_id=p_bakery and i.id=v_ingredient and i.active)
  then raise exception 'Invalid ingredient or quantity' using errcode='22023'; end if;
  insert into public.recipe_items(bakery_id,recipe_id,ingredient_id,quantity) values(p_bakery,v_recipe,v_ingredient,v_quantity);
 end loop;
 return v_recipe;
end $$;
create function bakery_private.complete_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_existing public.production_batches%rowtype; v_batch uuid; v_yield integer; v_line record; v_qty numeric; v_move uuid; v_total numeric:=0;
begin
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid() and m.role in ('owner','admin','operator'))
 then raise exception 'Production access denied' using errcode='42501'; end if;
 if p_request is null or p_units is null or p_units not between 1 and 1000000 then raise exception 'Invalid production' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 select * into v_existing from public.production_batches b where b.bakery_id=p_bakery and b.request_id=p_request;
 if found then
  if v_existing.branch_id=p_branch and v_existing.recipe_id=p_recipe and v_existing.output_units=p_units and v_existing.actor_id=auth.uid() then return v_existing.id; end if;
  raise exception 'Request ID already used' using errcode='23505';
 end if;
 select r.yield_units into v_yield from public.recipe_versions r where r.bakery_id=p_bakery and r.id=p_recipe;
 if not found or not exists(select 1 from public.branches b where b.bakery_id=p_bakery and b.id=p_branch and b.active)
 or not exists(select 1 from public.recipe_items i where i.bakery_id=p_bakery and i.recipe_id=p_recipe)
 then raise exception 'Invalid recipe or branch' using errcode='22023'; end if;
 insert into public.production_batches(bakery_id,branch_id,recipe_id,request_id,output_units,actor_id)
 values(p_bakery,p_branch,p_recipe,p_request,p_units,auth.uid()) returning id into v_batch;
 for v_line in select ri.ingredient_id,ri.quantity,i.reference_cost from public.recipe_items ri join public.ingredients i
  on i.bakery_id=ri.bakery_id and i.id=ri.ingredient_id
  where ri.bakery_id=p_bakery and ri.recipe_id=p_recipe order by ri.ingredient_id
 loop
  -- Round upward to the inventory precision (one thousandth of the base unit).
  v_qty:=ceil(v_line.quantity*p_units/v_yield*1000)/1000;
  v_move:=bakery_private.record_stock_movement(p_bakery,p_branch,v_line.ingredient_id,gen_random_uuid(),'out',v_qty,'Producción '||v_batch::text);
  insert into public.production_consumption(bakery_id,batch_id,ingredient_id,movement_id,quantity,unit_cost)
  values(p_bakery,v_batch,v_line.ingredient_id,v_move,v_qty,v_line.reference_cost);
  v_total:=v_total+v_qty*v_line.reference_cost;
 end loop;
 update public.production_batches set reference_cost=v_total where bakery_id=p_bakery and id=v_batch;
 return v_batch;
end $$;
create function public.create_recipe_version(p_bakery uuid,p_name text,p_yield integer,p_items jsonb)
returns uuid language sql security invoker set search_path='' as $$ select bakery_private.create_recipe_version(p_bakery,p_name,p_yield,p_items) $$;
create function public.complete_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer)
returns uuid language sql security invoker set search_path='' as $$ select bakery_private.complete_production(p_bakery,p_branch,p_recipe,p_request,p_units) $$;
revoke all on function public.create_recipe_version(uuid,text,integer,jsonb) from public,anon,authenticated;
grant execute on function public.create_recipe_version(uuid,text,integer,jsonb) to authenticated;
revoke all on function public.complete_production(uuid,uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function public.complete_production(uuid,uuid,uuid,uuid,integer) to authenticated;
revoke all on function bakery_private.create_recipe_version(uuid,text,integer,jsonb) from public,anon,authenticated;
grant execute on function bakery_private.create_recipe_version(uuid,text,integer,jsonb) to authenticated;
revoke all on function bakery_private.complete_production(uuid,uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function bakery_private.complete_production(uuid,uuid,uuid,uuid,integer) to authenticated;
commit;
