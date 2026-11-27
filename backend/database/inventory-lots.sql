-- Apply after inventory-costs.sql. Preserve base balances and immutable movements.
begin;
create table public.stock_lots(
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null,branch_id uuid not null,ingredient_id uuid not null,
 source_movement_id uuid,lot_code text,expires_on date,
 received_quantity numeric(14,3) not null check(received_quantity>0),
 quantity numeric(14,3) not null check(quantity>=0 and quantity<=received_quantity),
 received_at timestamptz not null default statement_timestamp(),
 unique(bakery_id,branch_id,ingredient_id,id),unique(bakery_id,source_movement_id),
 foreign key(bakery_id,branch_id,ingredient_id) references public.stock_balances(bakery_id,branch_id,ingredient_id),
 foreign key(bakery_id,source_movement_id) references public.stock_movements(bakery_id,id),
 check(lot_code is null or char_length(btrim(lot_code)) between 1 and 80),
 check(expires_on is null or expires_on between date '1900-01-01' and date '9999-12-31')
);
create index stock_lots_fefo on public.stock_lots(bakery_id,branch_id,ingredient_id,expires_on,received_at,id) where quantity>0;
-- Backfill existing balances without inventing historic expiry or lot identifiers.
insert into public.stock_lots(bakery_id,branch_id,ingredient_id,received_quantity,quantity)
 select bakery_id,branch_id,ingredient_id,quantity,quantity from public.stock_balances where quantity>0;
alter table public.stock_movements add column movement_category text not null default 'normal' check(movement_category in ('normal','waste'));
alter table public.stock_movements add column lot_code text;
alter table public.stock_movements add column expires_on date;
alter table public.stock_movements add column target_lot_id uuid;
alter table public.stock_movements add constraint movement_target_lot_fk foreign key(bakery_id,branch_id,ingredient_id,target_lot_id) references public.stock_lots(bakery_id,branch_id,ingredient_id,id);
create table public.stock_lot_allocations(
 bakery_id uuid not null,branch_id uuid not null,ingredient_id uuid not null,
 movement_id uuid not null,lot_id uuid not null,quantity numeric(14,3) not null check(quantity>0),
 primary key(bakery_id,movement_id,lot_id),
 foreign key(bakery_id,movement_id) references public.stock_movements(bakery_id,id),
 foreign key(bakery_id,branch_id,ingredient_id,lot_id) references public.stock_lots(bakery_id,branch_id,ingredient_id,id)
);
create index stock_lot_allocations_lot on public.stock_lot_allocations(bakery_id,lot_id);
alter table public.stock_lots enable row level security;
alter table public.stock_lot_allocations enable row level security;
revoke all on public.stock_lots,public.stock_lot_allocations from public,anon,authenticated;
grant select on public.stock_lots,public.stock_lot_allocations to authenticated;
create policy stock_lots_read on public.stock_lots for select to authenticated using ((select bakery_private.session_allowed()) and exists(select 1 from public.bakery_members m where m.bakery_id=stock_lots.bakery_id and m.user_id=(select auth.uid())));
create policy stock_lot_allocations_read on public.stock_lot_allocations for select to authenticated using ((select bakery_private.session_allowed()) and exists(select 1 from public.bakery_members m where m.bakery_id=stock_lot_allocations.bakery_id and m.user_id=(select auth.uid())));
create trigger entitlement_guard before insert or update on public.stock_lots for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.stock_lot_allocations for each row execute function bakery_private.enforce_entitlement();

create function bakery_private.record_lot_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text,p_lot_code text,p_expires_on date,p_waste_lot uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.stock_movements%rowtype;v_id uuid;v_balance numeric;v_lot uuid;v_row record;v_remaining numeric;v_take numeric;v_code text:=nullif(btrim(p_lot_code),'');v_today date:=(statement_timestamp() at time zone 'America/Lima')::date;v_category text:=case when p_waste_lot is null then 'normal' else 'waste' end;
begin
 perform bakery_private.require_session();
 if p_request is null or p_direction is null or p_direction not in ('in','out') or p_quantity is null or not (p_quantity>0 and p_quantity<=99999999999) or p_quantity<>round(p_quantity,3)
 or p_reason is null or char_length(btrim(p_reason)) not between 1 and 200
 or (v_code is not null and char_length(v_code)>80)
 or (p_expires_on is not null and not(p_expires_on between date '1900-01-01' and date '9999-12-31'))
 or (p_direction='out' and (v_code is not null or p_expires_on is not null))
 or (p_waste_lot is not null and p_direction<>'out')
 then raise exception 'Invalid lot movement' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_inventory_access(p_bakery,p_branch,p_ingredient,p_waste_lot is not null);
 select * into v_old from public.stock_movements where bakery_id=p_bakery and request_id=p_request;
 if found then
  if v_old.branch_id=p_branch and v_old.ingredient_id=p_ingredient and v_old.direction=p_direction and v_old.quantity=p_quantity and v_old.reason=btrim(p_reason) and v_old.actor_id=auth.uid()
   and v_old.movement_category=v_category and v_old.lot_code is not distinct from v_code and v_old.expires_on is not distinct from p_expires_on and v_old.target_lot_id is not distinct from p_waste_lot then return v_old.id;end if;
  raise exception 'Request ID already used' using errcode='23505';
 end if;
 insert into public.stock_balances(bakery_id,branch_id,ingredient_id) values(p_bakery,p_branch,p_ingredient) on conflict do nothing;
 select quantity into v_balance from public.stock_balances where bakery_id=p_bakery and branch_id=p_branch and ingredient_id=p_ingredient for update;
 if v_balance<>coalesce((select sum(quantity) from public.stock_lots where bakery_id=p_bakery and branch_id=p_branch and ingredient_id=p_ingredient),0) then raise exception 'Lot balance mismatch' using errcode='23514';end if;
 v_balance:=v_balance+case when p_direction='in' then p_quantity else -p_quantity end;
 if v_balance<0 or v_balance>99999999999 then raise exception 'Stock outside permitted range' using errcode='23514';end if;
 insert into public.stock_movements(bakery_id,branch_id,ingredient_id,request_id,direction,quantity,reason,actor_id,movement_category,lot_code,expires_on,target_lot_id)
 values(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,btrim(p_reason),auth.uid(),v_category,v_code,p_expires_on,p_waste_lot) returning id into v_id;
 if p_direction='in' then
  insert into public.stock_lots(bakery_id,branch_id,ingredient_id,source_movement_id,lot_code,expires_on,received_quantity,quantity)
  values(p_bakery,p_branch,p_ingredient,v_id,v_code,p_expires_on,p_quantity,p_quantity) returning id into v_lot;
 else
  v_remaining:=p_quantity;
  for v_row in select l.id,l.quantity from public.stock_lots l where l.bakery_id=p_bakery and l.branch_id=p_branch and l.ingredient_id=p_ingredient and l.quantity>0
   and ((p_waste_lot is not null and l.id=p_waste_lot) or (p_waste_lot is null and (l.expires_on is null or l.expires_on>=v_today)))
   order by l.expires_on asc nulls last,l.received_at,l.id for update loop
   v_take:=least(v_remaining,v_row.quantity);
   update public.stock_lots set quantity=quantity-v_take where id=v_row.id;
   insert into public.stock_lot_allocations(bakery_id,branch_id,ingredient_id,movement_id,lot_id,quantity) values(p_bakery,p_branch,p_ingredient,v_id,v_row.id,v_take);
   v_remaining:=v_remaining-v_take;
   exit when v_remaining=0;
  end loop;
  if v_remaining<>0 then raise exception 'Insufficient usable lot stock' using errcode='23514';end if;
 end if;
 update public.stock_balances set quantity=v_balance where bakery_id=p_bakery and branch_id=p_branch and ingredient_id=p_ingredient;
 if v_balance<>coalesce((select sum(quantity) from public.stock_lots where bakery_id=p_bakery and branch_id=p_branch and ingredient_id=p_ingredient),0) then raise exception 'Lot balance mismatch' using errcode='23514';end if;
 return v_id;
end $$;
revoke all on function bakery_private.record_lot_movement(uuid,uuid,uuid,uuid,text,numeric,text,text,date,uuid) from public,anon,authenticated;
grant execute on function bakery_private.record_lot_movement(uuid,uuid,uuid,uuid,text,numeric,text,text,date,uuid) to authenticated;
-- Old RPC remains compatible. All production paths now use FEFO.
create or replace function bakery_private.record_stock_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text)
returns uuid language sql security definer set search_path='' as $$
 select bakery_private.record_lot_movement(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,p_reason,null,null,null)
$$;
create function public.record_lot_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text,p_lot_code text,p_expires_on date,p_waste_lot uuid)
returns uuid language sql security invoker set search_path='' as $$
 select bakery_private.record_lot_movement(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,p_reason,p_lot_code,p_expires_on,p_waste_lot)
$$;
revoke all on function public.record_lot_movement(uuid,uuid,uuid,uuid,text,numeric,text,text,date,uuid) from public,anon,authenticated;
grant execute on function public.record_lot_movement(uuid,uuid,uuid,uuid,text,numeric,text,text,date,uuid) to authenticated;
create view public.usable_stock with(security_invoker=true) as
 select b.bakery_id,b.branch_id,b.ingredient_id,b.minimum,b.quantity as total_quantity,
 coalesce((select sum(l.quantity) from public.stock_lots l where l.bakery_id=b.bakery_id and l.branch_id=b.branch_id and l.ingredient_id=b.ingredient_id and (l.expires_on is null or l.expires_on>=(statement_timestamp() at time zone 'America/Lima')::date)),0)::numeric(14,3) as quantity
 from public.stock_balances b;
revoke all on public.usable_stock from public,anon,authenticated;
grant select on public.usable_stock to authenticated;
create or replace function bakery_private.receive_purchase(p_bakery uuid,p_branch uuid,p_supplier uuid,p_request uuid,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.purchase_receipts%rowtype; v_receipt uuid; v_line jsonb; v_ingredient uuid; v_qty numeric; v_cost numeric; v_move uuid; v_total numeric:=0;
begin
 perform bakery_private.require_session();
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
  v_move:=bakery_private.record_lot_movement(p_bakery,p_branch,v_ingredient,gen_random_uuid(),'in',v_qty,'Compra '||v_receipt::text,v_line->>'lot_code',nullif(v_line->>'expires_on','')::date,null);
  insert into public.purchase_items(bakery_id,receipt_id,ingredient_id,movement_id,quantity,unit_cost)
  values(p_bakery,v_receipt,v_ingredient,v_move,v_qty,v_cost);
  v_total:=v_total+round(v_qty*v_cost,2);
 end loop;
 update public.purchase_receipts set total=v_total where bakery_id=p_bakery and id=v_receipt;
 return v_receipt;
end $$;
commit;
