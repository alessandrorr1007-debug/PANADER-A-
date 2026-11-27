begin;
alter table public.production_batches add column planned_units integer;
update public.production_batches set planned_units=output_units;
alter table public.production_batches alter column planned_units set not null;
alter table public.production_batches add constraint production_planned_units_check check(planned_units between 1 and 1000000);
alter table public.production_batches add column labor_cost numeric(14,2) not null default 0 check(labor_cost>=0);
alter table public.production_batches add column energy_cost numeric(14,2) not null default 0 check(energy_cost>=0);
alter table public.production_batches add column other_cost numeric(14,2) not null default 0 check(other_cost>=0);
create function bakery_private.complete_costed_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer,p_actual integer,p_labor numeric,p_energy numeric,p_other numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_existing public.production_batches%rowtype; v_batch uuid; v_yield integer; v_line record; v_qty numeric; v_move uuid; v_total numeric:=0;
begin
 perform bakery_private.require_permission(p_bakery,'production');
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid() and m.role in ('owner','admin','operator'))
 then raise exception 'Production access denied' using errcode='42501'; end if;
 if p_request is null or p_units is null or p_units not between 1 and 1000000 or p_actual is null or p_actual not between 1 and 1000000 or p_labor is null or p_energy is null or p_other is null or not(p_labor between 0 and 999999999.99 and p_energy between 0 and 999999999.99 and p_other between 0 and 999999999.99) or p_labor<>round(p_labor,2) or p_energy<>round(p_energy,2) or p_other<>round(p_other,2) then raise exception 'Invalid production' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 select * into v_existing from public.production_batches b where b.bakery_id=p_bakery and b.request_id=p_request;
 if found then
  if v_existing.branch_id=p_branch and v_existing.recipe_id=p_recipe and v_existing.output_units=p_actual and v_existing.planned_units=p_units and v_existing.labor_cost=p_labor and v_existing.energy_cost=p_energy and v_existing.other_cost=p_other and v_existing.actor_id=auth.uid() then return v_existing.id; end if;
  raise exception 'Request ID already used' using errcode='23505';
 end if;
 select r.yield_units into v_yield from public.recipe_versions r where r.bakery_id=p_bakery and r.id=p_recipe;
 if not found or not exists(select 1 from public.branches b where b.bakery_id=p_bakery and b.id=p_branch and b.active)
 or not exists(select 1 from public.recipe_items i where i.bakery_id=p_bakery and i.recipe_id=p_recipe)
 then raise exception 'Invalid recipe or branch' using errcode='22023'; end if;
 insert into public.production_batches(bakery_id,branch_id,recipe_id,request_id,output_units,actor_id,planned_units,labor_cost,energy_cost,other_cost)
 values(p_bakery,p_branch,p_recipe,p_request,p_actual,auth.uid(),p_units,p_labor,p_energy,p_other) returning id into v_batch;
 for v_line in select ri.ingredient_id,ri.quantity,i.reference_cost from public.recipe_items ri join public.ingredients i
  on i.bakery_id=ri.bakery_id and i.id=ri.ingredient_id
  where ri.bakery_id=p_bakery and ri.recipe_id=p_recipe order by ri.ingredient_id
 loop
  -- Round upward to the inventory precision (one thousandth of the base unit).
  v_qty:=ceil(v_line.quantity*p_units/v_yield*1000)/1000;
  v_move:=bakery_private.apply_lot_movement(p_bakery,p_branch,v_line.ingredient_id,gen_random_uuid(),'out',v_qty,'Producción '||v_batch::text,null,null,null);
  insert into public.production_consumption(bakery_id,batch_id,ingredient_id,movement_id,quantity,unit_cost)
  values(p_bakery,v_batch,v_line.ingredient_id,v_move,v_qty,v_line.reference_cost);
  v_total:=v_total+v_qty*v_line.reference_cost;
 end loop;
 update public.production_batches set reference_cost=v_total where bakery_id=p_bakery and id=v_batch;
 return v_batch;
end $$;

revoke all on function bakery_private.complete_costed_production(uuid,uuid,uuid,uuid,integer,integer,numeric,numeric,numeric) from public,anon,authenticated;
grant execute on function bakery_private.complete_costed_production(uuid,uuid,uuid,uuid,integer,integer,numeric,numeric,numeric) to authenticated;
create function public.complete_costed_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer,p_actual integer,p_labor numeric,p_energy numeric,p_other numeric) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.complete_costed_production(p_bakery,p_branch,p_recipe,p_request,p_units,p_actual,p_labor,p_energy,p_other) $$;
revoke all on function public.complete_costed_production(uuid,uuid,uuid,uuid,integer,integer,numeric,numeric,numeric) from public,anon,authenticated;
grant execute on function public.complete_costed_production(uuid,uuid,uuid,uuid,integer,integer,numeric,numeric,numeric) to authenticated;
create or replace function bakery_private.complete_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer) returns uuid language sql security definer set search_path='' as $$ select bakery_private.complete_costed_production(p_bakery,p_branch,p_recipe,p_request,p_units,p_units,0,0,0) $$;
create view public.daily_production_margin with(security_invoker=true) as
 select s.bakery_id,s.branch_id,(s.created_at at time zone 'America/Lima')::date as business_date,
 sum(s.total) as revenue,
 round(sum(coalesce(l.production_cost,0)),2) as production_cost,
 sum(s.total)-round(sum(coalesce(l.production_cost,0)),2) as production_margin
 from public.sales s
 left join lateral(select sum(i.units*(b.reference_cost+b.labor_cost+b.energy_cost+b.other_cost)/b.output_units) as production_cost from public.sale_items i join public.production_batches b on b.bakery_id=i.bakery_id and b.id=i.batch_id where i.bakery_id=s.bakery_id and i.sale_id=s.id) l on true
 where bakery_private.has_permission(s.bakery_id,'reports')
 group by s.bakery_id,s.branch_id,(s.created_at at time zone 'America/Lima')::date;
revoke all on public.daily_production_margin from public,anon,authenticated;
grant select on public.daily_production_margin to authenticated;
commit;
