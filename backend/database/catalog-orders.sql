-- Catalog and commercial order workflow, after production-costs.sql.
begin;
create table public.product_catalog(
 bakery_id uuid not null,recipe_id uuid not null,display_name text not null check(char_length(btrim(display_name)) between 1 and 120),
 category text not null check(char_length(btrim(category)) between 1 and 80),sku text check(sku is null or char_length(btrim(sku)) between 1 and 40),
 active boolean not null default true,updated_by uuid not null,updated_at timestamptz not null default statement_timestamp(),
 primary key(bakery_id,recipe_id),foreign key(bakery_id,recipe_id) references public.recipe_versions(bakery_id,id)
);
create unique index catalog_sku on public.product_catalog(bakery_id,lower(sku)) where sku is not null;
create table public.customers(
 id uuid primary key default gen_random_uuid(),bakery_id uuid not null references public.bakeries(id),request_id uuid not null,
 name text not null check(char_length(btrim(name)) between 1 and 120),phone text check(phone is null or char_length(phone)<=40),notes text check(notes is null or char_length(notes)<=300),
 active boolean not null default true,created_by uuid not null,created_at timestamptz not null default statement_timestamp(),
 unique(bakery_id,id),unique(bakery_id,request_id)
);
create table public.customer_orders(
 id uuid primary key default gen_random_uuid(),bakery_id uuid not null,branch_id uuid not null,customer_id uuid not null,request_id uuid not null,
 due_date date not null check(due_date between date '1900-01-01' and date '9999-12-31'),notes text check(notes is null or char_length(notes)<=400),
 status text not null default 'pending' check(status in ('pending','confirmed','ready','delivered','cancelled')),total numeric(30,2) not null default 0 check(total>=0),
 payload jsonb not null,created_by uuid not null,created_at timestamptz not null default statement_timestamp(),updated_at timestamptz not null default statement_timestamp(),updated_by uuid not null,
 sale_id uuid,delivery_request_id uuid,delivery_payment text,
 unique(bakery_id,id),unique(bakery_id,request_id),unique(bakery_id,sale_id),unique(bakery_id,delivery_request_id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id),foreign key(bakery_id,customer_id) references public.customers(bakery_id,id),foreign key(bakery_id,sale_id) references public.sales(bakery_id,id),
 check((status='delivered')=(sale_id is not null)),check((sale_id is null)=(delivery_request_id is null)),check((sale_id is null)=(delivery_payment is null)),check(delivery_payment is null or delivery_payment in ('cash','card','transfer','wallet'))
);
create table public.customer_order_items(
 bakery_id uuid not null,order_id uuid not null,recipe_id uuid not null,units integer not null check(units between 1 and 1000000),unit_price numeric(12,2) not null check(unit_price>0),
 primary key(bakery_id,order_id,recipe_id),foreign key(bakery_id,order_id) references public.customer_orders(bakery_id,id),foreign key(bakery_id,recipe_id) references public.recipe_versions(bakery_id,id)
);
create index customers_name on public.customers(bakery_id,lower(name));
create index customer_orders_branch_due on public.customer_orders(bakery_id,branch_id,due_date,status);
alter table public.product_catalog enable row level security;
revoke all on public.product_catalog from public,anon,authenticated;
grant select on public.product_catalog to authenticated;
create policy product_catalog_read on public.product_catalog for select to authenticated using(bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'prices'));
create trigger entitlement_guard before insert or update on public.product_catalog for each row execute function bakery_private.enforce_entitlement();
alter table public.customers enable row level security;
revoke all on public.customers from public,anon,authenticated;
grant select on public.customers to authenticated;
create policy customers_read on public.customers for select to authenticated using(bakery_private.has_permission(bakery_id,'sales'));
create trigger entitlement_guard before insert or update on public.customers for each row execute function bakery_private.enforce_entitlement();
alter table public.customer_orders enable row level security;
revoke all on public.customer_orders from public,anon,authenticated;
grant select on public.customer_orders to authenticated;
create policy customer_orders_read on public.customer_orders for select to authenticated using(bakery_private.has_permission(bakery_id,'sales'));
create trigger entitlement_guard before insert or update on public.customer_orders for each row execute function bakery_private.enforce_entitlement();
alter table public.customer_order_items enable row level security;
revoke all on public.customer_order_items from public,anon,authenticated;
grant select on public.customer_order_items to authenticated;
create policy customer_order_items_read on public.customer_order_items for select to authenticated using(bakery_private.has_permission(bakery_id,'sales'));
create trigger entitlement_guard before insert or update on public.customer_order_items for each row execute function bakery_private.enforce_entitlement();
create function bakery_private.set_catalog_product(p_bakery uuid,p_recipe uuid,p_name text,p_category text,p_sku text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 perform bakery_private.require_permission(p_bakery,'prices');
 if p_name is null or char_length(btrim(p_name)) not between 1 and 120 or p_category is null or char_length(btrim(p_category)) not between 1 and 80 or (p_sku is not null and char_length(btrim(p_sku))>40) or p_active is null then raise exception 'Invalid catalog product' using errcode='22023';end if;
 if not exists(select 1 from public.recipe_versions where bakery_id=p_bakery and id=p_recipe) then raise exception 'Invalid recipe' using errcode='22023';end if;
 insert into public.product_catalog(bakery_id,recipe_id,display_name,category,sku,active,updated_by) values(p_bakery,p_recipe,btrim(p_name),btrim(p_category),nullif(btrim(p_sku),''),p_active,auth.uid())
 on conflict(bakery_id,recipe_id) do update set display_name=excluded.display_name,category=excluded.category,sku=excluded.sku,active=excluded.active,updated_by=excluded.updated_by,updated_at=statement_timestamp();
end $$;
create view public.catalog_products with(security_invoker=true) as
 select r.bakery_id,r.id as recipe_id,r.name as recipe_name,r.version,coalesce(c.display_name,r.name||' · v'||r.version) as display_name,coalesce(c.category,'Sin categoría') as category,c.sku,coalesce(c.active,true) as active,p.unit_price
 from public.recipe_versions r left join public.product_catalog c on c.bakery_id=r.bakery_id and c.recipe_id=r.id
 left join public.recipe_prices p on p.bakery_id=r.bakery_id and p.recipe_id=r.id
 where bakery_private.has_permission(r.bakery_id,'sales') or bakery_private.has_permission(r.bakery_id,'prices');
revoke all on public.catalog_products from public,anon,authenticated;
grant select on public.catalog_products to authenticated;
-- Sale checks must also reject hidden products, even through a direct RPC.
create or replace function bakery_private.check_sale_price() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_price numeric;v_active boolean;
begin
 select p.unit_price,coalesce(c.active,true) into v_price,v_active from public.production_batches b join public.recipe_prices p on p.bakery_id=b.bakery_id and p.recipe_id=b.recipe_id left join public.product_catalog c on c.bakery_id=b.bakery_id and c.recipe_id=b.recipe_id where b.bakery_id=new.bakery_id and b.id=new.batch_id;
 if not found or new.unit_price<>v_price or not v_active then raise exception 'Active product with configured price required' using errcode='23514';end if;
 return new;
end $$;
create function bakery_private.create_customer(p_bakery uuid,p_request uuid,p_name text,p_phone text,p_notes text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.customers%rowtype;v_id uuid;v_phone text:=nullif(btrim(p_phone),'');v_notes text:=nullif(btrim(p_notes),'');
begin
 perform bakery_private.require_permission(p_bakery,'sales');
 if p_request is null or p_name is null or char_length(btrim(p_name)) not between 1 and 120 or char_length(v_phone)>40 or char_length(v_notes)>300 then raise exception 'Invalid customer' using errcode='22023';end if;
 select * into v_old from public.customers where bakery_id=p_bakery and request_id=p_request;
 if found then
  if v_old.name=btrim(p_name) and v_old.phone is not distinct from v_phone and v_old.notes is not distinct from v_notes and v_old.created_by=auth.uid() then return v_old.id;end if;
  raise exception 'Request already used' using errcode='23505';end if;
 insert into public.customers(bakery_id,request_id,name,phone,notes,created_by) values(p_bakery,p_request,btrim(p_name),v_phone,v_notes,auth.uid()) returning id into v_id;
 return v_id;
end $$;
create function bakery_private.create_customer_order(p_bakery uuid,p_branch uuid,p_customer uuid,p_request uuid,p_due date,p_notes text,p_items jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.customer_orders%rowtype;v_id uuid;l jsonb;v_recipe uuid;v_qty numeric;v_price numeric;v_total numeric:=0;v_notes text:=nullif(btrim(p_notes),'');
begin
 perform bakery_private.require_permission(p_bakery,'sales');
 perform bakery_private.assert_commerce(p_bakery,p_branch,false);
 if p_request is null or p_due is null or not(p_due between date '1900-01-01' and date '9999-12-31') or char_length(v_notes)>400 or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Invalid order' using errcode='22023';end if;
 if jsonb_array_length(p_items) not between 1 and 100 then raise exception 'Invalid order items' using errcode='22023';end if;
 select * into v_old from public.customer_orders where bakery_id=p_bakery and request_id=p_request;
 if found then
  if v_old.branch_id=p_branch and v_old.customer_id=p_customer and v_old.due_date=p_due and v_old.notes is not distinct from v_notes and v_old.payload=p_items and v_old.created_by=auth.uid() then return v_old.id;end if;
  raise exception 'Request already used' using errcode='23505';end if;
 if p_due<(statement_timestamp() at time zone 'America/Lima')::date then raise exception 'Past due date' using errcode='22023';end if;
 if not exists(select 1 from public.customers where bakery_id=p_bakery and id=p_customer and active) then raise exception 'Invalid customer' using errcode='22023';end if;
 insert into public.customer_orders(bakery_id,branch_id,customer_id,request_id,due_date,notes,payload,created_by,updated_by) values(p_bakery,p_branch,p_customer,p_request,p_due,v_notes,p_items,auth.uid(),auth.uid()) returning id into v_id;
 for l in select value from jsonb_array_elements(p_items) loop
  v_recipe:=(l->>'recipe_id')::uuid;v_qty:=(l->>'units')::numeric;
  if v_qty is null or not(v_qty between 1 and 1000000) or v_qty<>trunc(v_qty) then raise exception 'Invalid units' using errcode='22023';end if;
  select p.unit_price into v_price from public.recipe_prices p left join public.product_catalog c on c.bakery_id=p.bakery_id and c.recipe_id=p.recipe_id where p.bakery_id=p_bakery and p.recipe_id=v_recipe and coalesce(c.active,true);
  if not found then raise exception 'Active priced product required' using errcode='23514';end if;
  insert into public.customer_order_items values(p_bakery,v_id,v_recipe,v_qty::integer,v_price);
  v_total:=v_total+v_qty*v_price;
 end loop;
 update public.customer_orders set total=v_total where id=v_id;
 return v_id;
end $$;
create function bakery_private.set_order_status(p_bakery uuid,p_order uuid,p_status text) returns void language plpgsql security definer set search_path='' as $$
declare o public.customer_orders%rowtype;
begin
 perform bakery_private.require_permission(p_bakery,'sales');
 select * into o from public.customer_orders where bakery_id=p_bakery and id=p_order;
 if not found then raise exception 'Order unavailable' using errcode='42501';end if;
 if o.status=p_status then return;end if;
 if p_status is null or not((o.status='pending' and p_status in ('confirmed','cancelled')) or (o.status='confirmed' and p_status in ('ready','cancelled')) or (o.status='ready' and p_status='cancelled')) then raise exception 'Invalid status transition' using errcode='22023';end if;
 update public.customer_orders set status=p_status,updated_at=statement_timestamp(),updated_by=auth.uid() where id=p_order;
end $$;
create function bakery_private.deliver_customer_order(p_bakery uuid,p_order uuid,p_request uuid,p_payment text) returns uuid language plpgsql security definer set search_path='' as $$
declare o public.customer_orders%rowtype;l record;b record;v_remaining bigint;v_take bigint;v_items jsonb:='[]'::jsonb;v_sale uuid;v_price numeric;
begin
 perform bakery_private.require_permission(p_bakery,'sales');
 if p_request is null or p_payment is null or p_payment not in ('cash','card','transfer','wallet') then raise exception 'Invalid delivery' using errcode='22023';end if;
 select * into o from public.customer_orders where bakery_id=p_bakery and id=p_order;
 if not found then raise exception 'Order unavailable' using errcode='42501';end if;
 if o.status='delivered' then
  if o.delivery_request_id=p_request and o.delivery_payment=p_payment and o.updated_by=auth.uid() then return o.sale_id;end if;
  raise exception 'Order already delivered' using errcode='23505';end if;
 if o.status<>'ready' then raise exception 'Order is not ready' using errcode='22023';end if;
 perform bakery_private.assert_commerce(p_bakery,o.branch_id,false);
 for l in select * from public.customer_order_items where bakery_id=p_bakery and order_id=p_order order by recipe_id loop
  select p.unit_price into v_price from public.recipe_prices p left join public.product_catalog c on c.bakery_id=p.bakery_id and c.recipe_id=p.recipe_id where p.bakery_id=p_bakery and p.recipe_id=l.recipe_id and coalesce(c.active,true);
  if not found or v_price<>l.unit_price then raise exception 'Price changed or product inactive; review order' using errcode='23514';end if;
  v_remaining:=l.units;
  for b in select p.id,p.output_units-coalesce((select sum(si.units) from public.sale_items si where si.bakery_id=p.bakery_id and si.batch_id=p.id),0) as available
   from public.production_batches p where p.bakery_id=p_bakery and p.branch_id=o.branch_id and p.recipe_id=l.recipe_id order by p.created_at,p.id loop
   v_take:=least(v_remaining,b.available);
   if v_take>0 then v_items:=v_items||jsonb_build_array(jsonb_build_object('batch_id',b.id,'units',v_take,'unit_price',l.unit_price));v_remaining:=v_remaining-v_take;end if;
   exit when v_remaining=0;
  end loop;
  if v_remaining<>0 then raise exception 'Insufficient stock to deliver order' using errcode='23514';end if;
 end loop;
 if jsonb_array_length(v_items) not between 1 and 100 then raise exception 'Too many batches in delivery' using errcode='22023';end if;
 -- Separate idempotency from regular POS sales, to avoid linking an existing unrelated sale.
 v_sale:=bakery_private.record_sale(p_bakery,o.branch_id,gen_random_uuid(),p_payment,v_items);
 if (select total from public.sales where id=v_sale)<>o.total then raise exception 'Order total mismatch' using errcode='23514';end if;
 update public.customer_orders set status='delivered',sale_id=v_sale,delivery_request_id=p_request,delivery_payment=p_payment,updated_at=statement_timestamp(),updated_by=auth.uid() where id=p_order;
 return v_sale;
end $$;
create function public.set_catalog_product(p_bakery uuid,p_recipe uuid,p_name text,p_category text,p_sku text,p_active boolean) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_catalog_product(p_bakery,p_recipe,p_name,p_category,p_sku,p_active) $$;
revoke all on function public.set_catalog_product(uuid,uuid,text,text,text,boolean),bakery_private.set_catalog_product(uuid,uuid,text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.set_catalog_product(uuid,uuid,text,text,text,boolean),bakery_private.set_catalog_product(uuid,uuid,text,text,text,boolean) to authenticated;
create function public.create_customer(p_bakery uuid,p_request uuid,p_name text,p_phone text,p_notes text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.create_customer(p_bakery,p_request,p_name,p_phone,p_notes) $$;
revoke all on function public.create_customer(uuid,uuid,text,text,text),bakery_private.create_customer(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.create_customer(uuid,uuid,text,text,text),bakery_private.create_customer(uuid,uuid,text,text,text) to authenticated;
create function public.create_customer_order(p_bakery uuid,p_branch uuid,p_customer uuid,p_request uuid,p_due date,p_notes text,p_items jsonb) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.create_customer_order(p_bakery,p_branch,p_customer,p_request,p_due,p_notes,p_items) $$;
revoke all on function public.create_customer_order(uuid,uuid,uuid,uuid,date,text,jsonb),bakery_private.create_customer_order(uuid,uuid,uuid,uuid,date,text,jsonb) from public,anon,authenticated;
grant execute on function public.create_customer_order(uuid,uuid,uuid,uuid,date,text,jsonb),bakery_private.create_customer_order(uuid,uuid,uuid,uuid,date,text,jsonb) to authenticated;
create function public.set_order_status(p_bakery uuid,p_order uuid,p_status text) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_order_status(p_bakery,p_order,p_status) $$;
revoke all on function public.set_order_status(uuid,uuid,text),bakery_private.set_order_status(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.set_order_status(uuid,uuid,text),bakery_private.set_order_status(uuid,uuid,text) to authenticated;
create function public.deliver_customer_order(p_bakery uuid,p_order uuid,p_request uuid,p_payment text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.deliver_customer_order(p_bakery,p_order,p_request,p_payment) $$;
revoke all on function public.deliver_customer_order(uuid,uuid,uuid,text),bakery_private.deliver_customer_order(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.deliver_customer_order(uuid,uuid,uuid,text),bakery_private.deliver_customer_order(uuid,uuid,uuid,text) to authenticated;
commit;
