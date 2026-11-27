-- Design draft, apply after production.sql on a disposable database.
begin;
create table public.suppliers(
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null references public.bakeries(id),
 name text not null check(char_length(btrim(name)) between 1 and 120),
 active boolean not null default true,
 unique(bakery_id,id)
);
create unique index suppliers_name_unique on public.suppliers(bakery_id,lower(btrim(name)));
create table public.purchase_receipts(
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null,
 branch_id uuid not null,
 supplier_id uuid not null,
 request_id uuid not null,
 payload jsonb not null,
 total numeric(30,2) not null default 0 check(total>=0),
 actor_id uuid not null,
 created_at timestamptz not null default now(),
 unique(bakery_id,id),unique(bakery_id,request_id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id),
 foreign key(bakery_id,supplier_id) references public.suppliers(bakery_id,id)
);
create table public.purchase_items(
 bakery_id uuid not null,
 receipt_id uuid not null,
 ingredient_id uuid not null,
 movement_id uuid not null,
 quantity numeric(14,3) not null check(quantity>0),
 unit_cost numeric(14,4) not null check(unit_cost>=0),
 primary key(bakery_id,receipt_id,ingredient_id),
 unique(bakery_id,movement_id),
 foreign key(bakery_id,receipt_id) references public.purchase_receipts(bakery_id,id),
 foreign key(bakery_id,ingredient_id) references public.ingredients(bakery_id,id),
 foreign key(bakery_id,movement_id) references public.stock_movements(bakery_id,id)
);
create table public.sales(
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null,
 branch_id uuid not null,
 request_id uuid not null,
 payment_method text not null check(payment_method in ('cash','card','transfer','wallet')),
 payload jsonb not null,
 total numeric(30,2) not null default 0 check(total>=0),
 actor_id uuid not null,
 created_at timestamptz not null default now(),
 unique(bakery_id,id),unique(bakery_id,request_id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id)
);
create table public.sale_items(
 bakery_id uuid not null,
 sale_id uuid not null,
 batch_id uuid not null,
 units integer not null check(units between 1 and 1000000),
 unit_price numeric(12,2) not null check(unit_price>0),
 primary key(bakery_id,sale_id,batch_id),
 foreign key(bakery_id,sale_id) references public.sales(bakery_id,id),
 foreign key(bakery_id,batch_id) references public.production_batches(bakery_id,id)
);
create index sale_items_batch_idx on public.sale_items(bakery_id,batch_id);
alter table public.suppliers enable row level security;
revoke all on public.suppliers from public,anon,authenticated;
grant select on public.suppliers to authenticated;
create policy suppliers_read on public.suppliers for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=suppliers.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.purchase_receipts enable row level security;
revoke all on public.purchase_receipts from public,anon,authenticated;
grant select on public.purchase_receipts to authenticated;
create policy purchase_receipts_read on public.purchase_receipts for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=purchase_receipts.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.purchase_items enable row level security;
revoke all on public.purchase_items from public,anon,authenticated;
grant select on public.purchase_items to authenticated;
create policy purchase_items_read on public.purchase_items for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=purchase_items.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.sales enable row level security;
revoke all on public.sales from public,anon,authenticated;
grant select on public.sales to authenticated;
create policy sales_read on public.sales for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=sales.bakery_id and m.user_id=(select auth.uid()))
);
alter table public.sale_items enable row level security;
revoke all on public.sale_items from public,anon,authenticated;
grant select on public.sale_items to authenticated;
create policy sale_items_read on public.sale_items for select to authenticated using (
 exists(select 1 from public.bakery_members m where m.bakery_id=sale_items.bakery_id and m.user_id=(select auth.uid()))
);
grant insert(bakery_id,name),update(name,active) on public.suppliers to authenticated;
create policy suppliers_insert on public.suppliers for insert to authenticated with check(exists(select 1 from public.bakery_members m where m.bakery_id=suppliers.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')));
create policy suppliers_update on public.suppliers for update to authenticated using(exists(select 1 from public.bakery_members m where m.bakery_id=suppliers.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin'))) with check(exists(select 1 from public.bakery_members m where m.bakery_id=suppliers.bakery_id and m.user_id=(select auth.uid()) and m.role in ('owner','admin')));
-- Stock of finished goods is derived from immutable production and sales, never edited directly.
create view public.finished_stock with (security_invoker=true) as
 select b.bakery_id,b.branch_id,b.id as batch_id,b.recipe_id,b.output_units,
 b.output_units-coalesce((select sum(s.units) from public.sale_items s where s.bakery_id=b.bakery_id and s.batch_id=b.id),0) as available_units
 from public.production_batches b;
revoke all on public.finished_stock from public,anon,authenticated;
grant select on public.finished_stock to authenticated;

create function bakery_private.assert_commerce(p_bakery uuid,p_branch uuid,p_manager boolean)
returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid()
 and (m.role in ('owner','admin') or (not p_manager and m.role='operator')))
 then raise exception 'Commerce access denied' using errcode='42501'; end if;
 if not exists(select 1 from public.branches b where b.bakery_id=p_bakery and b.id=p_branch and b.active)
 then raise exception 'Invalid branch' using errcode='22023'; end if;
end $$;
revoke all on function bakery_private.assert_commerce(uuid,uuid,boolean) from public,anon,authenticated;
create function bakery_private.receive_purchase(p_bakery uuid,p_branch uuid,p_supplier uuid,p_request uuid,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.purchase_receipts%rowtype; v_receipt uuid; v_line jsonb; v_ingredient uuid; v_qty numeric; v_cost numeric; v_move uuid; v_total numeric:=0;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_commerce(p_bakery,p_branch,true);
 if p_request is null or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Invalid receipt' using errcode='22023'; end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid receipt size' using errcode='22023'; end if;
 select * into v_old from public.purchase_receipts r where r.bakery_id=p_bakery and r.request_id=p_request;
 if found then
  if v_old.branch_id=p_branch and v_old.supplier_id=p_supplier and v_old.payload=p_items and v_old.actor_id=auth.uid() then return v_old.id; end if;
  raise exception 'Request ID already used' using errcode='23505';
 end if;
 if not exists(select 1 from public.suppliers s where s.bakery_id=p_bakery and s.id=p_supplier and s.active)
 then raise exception 'Invalid supplier' using errcode='22023'; end if;
 insert into public.purchase_receipts(bakery_id,branch_id,supplier_id,request_id,payload,actor_id)
 values(p_bakery,p_branch,p_supplier,p_request,p_items,auth.uid()) returning id into v_receipt;
 for v_line in select value from jsonb_array_elements(p_items) loop
  v_ingredient:=(v_line->>'ingredient_id')::uuid; v_qty:=(v_line->>'quantity')::numeric; v_cost:=(v_line->>'unit_cost')::numeric;
  if v_qty is null or not (v_qty>0 and v_qty<=99999999999) or v_qty<>round(v_qty,3)
   or v_cost is null or not (v_cost between 0 and 9999999999) or v_cost<>round(v_cost,4)
  then raise exception 'Invalid purchase line' using errcode='22023'; end if;
  v_move:=bakery_private.record_stock_movement(p_bakery,p_branch,v_ingredient,gen_random_uuid(),'in',v_qty,'Compra '||v_receipt::text);
  insert into public.purchase_items(bakery_id,receipt_id,ingredient_id,movement_id,quantity,unit_cost)
  values(p_bakery,v_receipt,v_ingredient,v_move,v_qty,v_cost);
  v_total:=v_total+round(v_qty*v_cost,2);
 end loop;
 update public.purchase_receipts set total=v_total where bakery_id=p_bakery and id=v_receipt;
 return v_receipt;
end $$;
create function bakery_private.record_sale(p_bakery uuid,p_branch uuid,p_request uuid,p_payment text,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.sales%rowtype; v_sale uuid; v_line jsonb; v_batch uuid; v_units numeric; v_price numeric; v_available bigint; v_total numeric:=0;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_commerce(p_bakery,p_branch,false);
 if p_request is null or p_payment is null or p_payment not in ('cash','card','transfer','wallet')
 or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Invalid sale' using errcode='22023'; end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid sale size' using errcode='22023'; end if;
 select * into v_old from public.sales s where s.bakery_id=p_bakery and s.request_id=p_request;
 if found then
  if v_old.branch_id=p_branch and v_old.payment_method=p_payment and v_old.payload=p_items and v_old.actor_id=auth.uid() then return v_old.id; end if;
  raise exception 'Request ID already used' using errcode='23505';
 end if;
 insert into public.sales(bakery_id,branch_id,request_id,payment_method,payload,actor_id)
 values(p_bakery,p_branch,p_request,p_payment,p_items,auth.uid()) returning id into v_sale;
 for v_line in select value from jsonb_array_elements(p_items) loop
  v_batch:=(v_line->>'batch_id')::uuid; v_units:=(v_line->>'units')::numeric; v_price:=(v_line->>'unit_price')::numeric;
  if v_units is null or not(v_units between 1 and 1000000) or v_units<>trunc(v_units)
   or v_price is null or not(v_price>0 and v_price<=9999999999.99) or v_price<>round(v_price,2)
  then raise exception 'Invalid sale line' using errcode='22023'; end if;
  select b.output_units-coalesce((select sum(s.units) from public.sale_items s where s.bakery_id=b.bakery_id and s.batch_id=b.id),0)
  into v_available from public.production_batches b where b.bakery_id=p_bakery and b.branch_id=p_branch and b.id=v_batch;
  if not found then raise exception 'Invalid production batch' using errcode='22023'; end if;
  if v_available<v_units then raise exception 'Insufficient finished stock' using errcode='23514'; end if;
  insert into public.sale_items(bakery_id,sale_id,batch_id,units,unit_price) values(p_bakery,v_sale,v_batch,v_units::integer,v_price);
  v_total:=v_total+v_units*v_price;
 end loop;
 update public.sales set total=v_total where bakery_id=p_bakery and id=v_sale;
 return v_sale;
end $$;
create function public.receive_purchase(p_bakery uuid,p_branch uuid,p_supplier uuid,p_request uuid,p_items jsonb)
returns uuid language sql security invoker set search_path='' as $$ select bakery_private.receive_purchase(p_bakery,p_branch,p_supplier,p_request,p_items) $$;
create function public.record_sale(p_bakery uuid,p_branch uuid,p_request uuid,p_payment text,p_items jsonb)
returns uuid language sql security invoker set search_path='' as $$ select bakery_private.record_sale(p_bakery,p_branch,p_request,p_payment,p_items) $$;
revoke all on function public.receive_purchase(uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.receive_purchase(uuid,uuid,uuid,uuid,jsonb) to authenticated;
revoke all on function public.record_sale(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.record_sale(uuid,uuid,uuid,text,jsonb) to authenticated;
revoke all on function bakery_private.receive_purchase(uuid,uuid,uuid,uuid,jsonb) from public,anon,authenticated;
grant execute on function bakery_private.receive_purchase(uuid,uuid,uuid,uuid,jsonb) to authenticated;
revoke all on function bakery_private.record_sale(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function bakery_private.record_sale(uuid,uuid,uuid,text,jsonb) to authenticated;
commit;
