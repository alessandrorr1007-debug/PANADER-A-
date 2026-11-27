begin;
alter table public.stock_movements drop constraint stock_movements_movement_category_check;
alter table public.stock_movements add constraint stock_movements_movement_category_check check(movement_category in ('normal','waste','transfer','count'));
create table public.inventory_transfers(
 id uuid primary key default gen_random_uuid(),bakery_id uuid not null,from_branch uuid not null,to_branch uuid not null,ingredient_id uuid not null,request_id uuid not null,quantity numeric(14,3) not null check(quantity>0),reason text not null,actor_id uuid not null,created_at timestamptz not null default statement_timestamp(),out_movement_id uuid,
 unique(bakery_id,request_id),unique(bakery_id,id),check(from_branch<>to_branch),
 foreign key(bakery_id,from_branch) references public.branches(bakery_id,id),
 foreign key(bakery_id,to_branch) references public.branches(bakery_id,id),
 foreign key(bakery_id,ingredient_id) references public.ingredients(bakery_id,id),
 foreign key(bakery_id,out_movement_id) references public.stock_movements(bakery_id,id)
);
create table public.inventory_transfer_lines(
 bakery_id uuid not null,transfer_id uuid not null,source_lot_id uuid not null,destination_movement_id uuid not null,quantity numeric(14,3) not null check(quantity>0),
 primary key(bakery_id,transfer_id,source_lot_id),
 foreign key(bakery_id,transfer_id) references public.inventory_transfers(bakery_id,id),
 foreign key(bakery_id,destination_movement_id) references public.stock_movements(bakery_id,id)
);
create table public.inventory_counts(
 id uuid primary key default gen_random_uuid(),bakery_id uuid not null,branch_id uuid not null,ingredient_id uuid not null,lot_id uuid not null,request_id uuid not null,expected_quantity numeric(14,3) not null check(expected_quantity>=0),counted_quantity numeric(14,3) not null check(counted_quantity>=0),reason text not null,actor_id uuid not null,created_at timestamptz not null default statement_timestamp(),movement_id uuid,
 unique(bakery_id,request_id),
 foreign key(bakery_id,branch_id,ingredient_id,lot_id) references public.stock_lots(bakery_id,branch_id,ingredient_id,id),
 foreign key(bakery_id,movement_id) references public.stock_movements(bakery_id,id)
);
create index inventory_transfers_bakery_time on public.inventory_transfers(bakery_id,created_at desc);
create index inventory_counts_scope_time on public.inventory_counts(bakery_id,branch_id,created_at desc);
alter table public.inventory_transfers enable row level security;
revoke all on public.inventory_transfers from public,anon,authenticated;
grant select on public.inventory_transfers to authenticated;
create policy inventory_read on public.inventory_transfers for select to authenticated using(bakery_private.has_permission(bakery_id,'inventory'));
create trigger entitlement_guard before insert or update on public.inventory_transfers for each row execute function bakery_private.enforce_entitlement();
alter table public.inventory_transfer_lines enable row level security;
revoke all on public.inventory_transfer_lines from public,anon,authenticated;
grant select on public.inventory_transfer_lines to authenticated;
create policy inventory_read on public.inventory_transfer_lines for select to authenticated using(bakery_private.has_permission(bakery_id,'inventory'));
create trigger entitlement_guard before insert or update on public.inventory_transfer_lines for each row execute function bakery_private.enforce_entitlement();
alter table public.inventory_counts enable row level security;
revoke all on public.inventory_counts from public,anon,authenticated;
grant select on public.inventory_counts to authenticated;
create policy inventory_read on public.inventory_counts for select to authenticated using(bakery_private.has_permission(bakery_id,'inventory'));
create trigger entitlement_guard before insert or update on public.inventory_counts for each row execute function bakery_private.enforce_entitlement();
create function bakery_private.transfer_inventory(p_bakery uuid,p_from uuid,p_to uuid,p_ingredient uuid,p_request uuid,p_quantity numeric,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.inventory_transfers%rowtype;v_id uuid;v_out uuid;v_in uuid;l record;
begin
 perform bakery_private.require_permission(p_bakery,'inventory');
 if p_from is null or p_to is null or p_from=p_to or p_request is null or p_quantity is null or not(p_quantity>0 and p_quantity<=99999999999) or p_quantity<>round(p_quantity,3) or p_reason is null or char_length(btrim(p_reason)) not between 1 and 150 then raise exception 'Invalid transfer' using errcode='22023';end if;
 perform bakery_private.assert_inventory_access(p_bakery,p_from,p_ingredient,false);
 perform bakery_private.assert_inventory_access(p_bakery,p_to,p_ingredient,false);
 select * into v_old from public.inventory_transfers where bakery_id=p_bakery and request_id=p_request;
 if found then
  if v_old.from_branch=p_from and v_old.to_branch=p_to and v_old.ingredient_id=p_ingredient and v_old.quantity=p_quantity and v_old.reason=btrim(p_reason) and v_old.actor_id=auth.uid() then return v_old.id;end if;
  raise exception 'Request already used' using errcode='23505';end if;
 insert into public.inventory_transfers(bakery_id,from_branch,to_branch,ingredient_id,request_id,quantity,reason,actor_id) values(p_bakery,p_from,p_to,p_ingredient,p_request,p_quantity,btrim(p_reason),auth.uid()) returning id into v_id;
 v_out:=bakery_private.apply_lot_movement(p_bakery,p_from,p_ingredient,gen_random_uuid(),'out',p_quantity,'Traslado '||v_id::text,null,null,null);
 update public.stock_movements set movement_category='transfer' where id=v_out;
 update public.inventory_transfers set out_movement_id=v_out where id=v_id;
 for l in select a.lot_id,a.quantity,s.lot_code,s.expires_on from public.stock_lot_allocations a join public.stock_lots s on s.id=a.lot_id and s.bakery_id=a.bakery_id where a.bakery_id=p_bakery and a.movement_id=v_out loop
  v_in:=bakery_private.apply_lot_movement(p_bakery,p_to,p_ingredient,gen_random_uuid(),'in',l.quantity,'Traslado '||v_id::text,l.lot_code,l.expires_on,null);
  update public.stock_movements set movement_category='transfer' where id=v_in;
  insert into public.inventory_transfer_lines values(p_bakery,v_id,l.lot_id,v_in,l.quantity);
 end loop;
 return v_id;
end $$;
create function bakery_private.reconcile_inventory(p_bakery uuid,p_branch uuid,p_lot uuid,p_request uuid,p_expected numeric,p_counted numeric,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.inventory_counts%rowtype;l public.stock_lots%rowtype;v_id uuid;v_move uuid;delta numeric;
begin
 perform bakery_private.require_permission(p_bakery,'inventory');
 if p_request is null or p_expected is null or p_counted is null or not(p_expected between 0 and 99999999999) or not(p_counted between 0 and 99999999999) or p_expected<>round(p_expected,3) or p_counted<>round(p_counted,3) or p_reason is null or char_length(btrim(p_reason)) not between 1 and 150 then raise exception 'Invalid count' using errcode='22023';end if;
 select * into l from public.stock_lots where bakery_id=p_bakery and branch_id=p_branch and id=p_lot;
 if not found then raise exception 'Invalid lot' using errcode='22023';end if;
 perform bakery_private.assert_inventory_access(p_bakery,p_branch,l.ingredient_id,false);
 select * into v_old from public.inventory_counts where bakery_id=p_bakery and request_id=p_request;
 if found then
  if v_old.branch_id=p_branch and v_old.lot_id=p_lot and v_old.expected_quantity=p_expected and v_old.counted_quantity=p_counted and v_old.reason=btrim(p_reason) and v_old.actor_id=auth.uid() then return v_old.id;end if;
  raise exception 'Request already used' using errcode='23505';end if;
 if l.quantity<>p_expected then raise exception 'Stock changed since count; refresh' using errcode='40001';end if;
 insert into public.inventory_counts(bakery_id,branch_id,ingredient_id,lot_id,request_id,expected_quantity,counted_quantity,reason,actor_id) values(p_bakery,p_branch,l.ingredient_id,p_lot,p_request,p_expected,p_counted,btrim(p_reason),auth.uid()) returning id into v_id;
 delta:=p_counted-p_expected;
 if delta<0 then v_move:=bakery_private.apply_lot_movement(p_bakery,p_branch,l.ingredient_id,gen_random_uuid(),'out',-delta,'Conteo '||v_id::text,null,null,p_lot);
 elsif delta>0 then v_move:=bakery_private.apply_lot_movement(p_bakery,p_branch,l.ingredient_id,gen_random_uuid(),'in',delta,'Conteo '||v_id::text,l.lot_code,l.expires_on,null);
 end if;
 if v_move is not null then update public.stock_movements set movement_category='count' where id=v_move;update public.inventory_counts set movement_id=v_move where id=v_id;end if;
 return v_id;
end $$;
create function public.transfer_inventory(p_bakery uuid,p_from uuid,p_to uuid,p_ingredient uuid,p_request uuid,p_quantity numeric,p_reason text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.transfer_inventory(p_bakery,p_from,p_to,p_ingredient,p_request,p_quantity,p_reason) $$;
create function public.reconcile_inventory(p_bakery uuid,p_branch uuid,p_lot uuid,p_request uuid,p_expected numeric,p_counted numeric,p_reason text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.reconcile_inventory(p_bakery,p_branch,p_lot,p_request,p_expected,p_counted,p_reason) $$;
revoke all on function public.transfer_inventory(uuid,uuid,uuid,uuid,uuid,numeric,text),bakery_private.transfer_inventory(uuid,uuid,uuid,uuid,uuid,numeric,text),public.reconcile_inventory(uuid,uuid,uuid,uuid,numeric,numeric,text),bakery_private.reconcile_inventory(uuid,uuid,uuid,uuid,numeric,numeric,text) from public,anon,authenticated;
grant execute on function public.transfer_inventory(uuid,uuid,uuid,uuid,uuid,numeric,text),bakery_private.transfer_inventory(uuid,uuid,uuid,uuid,uuid,numeric,text),public.reconcile_inventory(uuid,uuid,uuid,uuid,numeric,numeric,text),bakery_private.reconcile_inventory(uuid,uuid,uuid,uuid,numeric,numeric,text) to authenticated;
commit;
