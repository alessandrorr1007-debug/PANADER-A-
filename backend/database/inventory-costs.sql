-- Apply after auth-security.sql. Pooled bakery-wide weighted ingredient cost.
begin;
create table public.ingredient_cost_history(
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null, ingredient_id uuid not null, branch_id uuid not null, receipt_id uuid not null,
 purchased_quantity numeric(14,3) not null check(purchased_quantity>0),
 purchased_unit_cost numeric(14,4) not null check(purchased_unit_cost>=0),
 previous_quantity numeric(20,3) not null check(previous_quantity>=0),
 previous_cost numeric(14,4) not null check(previous_cost>=0),
 new_cost numeric(14,4) not null check(new_cost>=0),
 actor_id uuid not null, created_at timestamptz not null default statement_timestamp(),
 unique(bakery_id,receipt_id,ingredient_id),
 foreign key(bakery_id,ingredient_id) references public.ingredients(bakery_id,id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id),
 foreign key(bakery_id,receipt_id,ingredient_id) references public.purchase_items(bakery_id,receipt_id,ingredient_id)
);
create index ingredient_cost_history_scope on public.ingredient_cost_history(bakery_id,branch_id,created_at desc,id desc);
alter table public.ingredient_cost_history enable row level security;
revoke all on public.ingredient_cost_history from public,anon,authenticated;
grant select on public.ingredient_cost_history to authenticated;
create policy cost_history_read on public.ingredient_cost_history for select to authenticated
 using ((select bakery_private.session_allowed()) and exists(select 1 from public.bakery_members m where m.bakery_id=ingredient_cost_history.bakery_id and m.user_id=(select auth.uid())));
create trigger entitlement_guard before insert or update on public.ingredient_cost_history for each row execute function bakery_private.enforce_entitlement();
-- Purchase RPC already holds bakery lock, writes stock balance first and line second.
-- New weighted cost uses the prior quantity of all branches, including inactive branches.
create function bakery_private.update_purchase_average() returns trigger language plpgsql security definer set search_path='' as $$
declare v_cost numeric;v_prior numeric;v_next numeric;v_branch uuid;v_actor uuid;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.bakery_id::text,1));
 select r.branch_id,r.actor_id into v_branch,v_actor from public.purchase_receipts r where r.bakery_id=new.bakery_id and r.id=new.receipt_id;
 select i.reference_cost into v_cost from public.ingredients i where i.bakery_id=new.bakery_id and i.id=new.ingredient_id for update;
 select coalesce(sum(b.quantity),0)-new.quantity into v_prior from public.stock_balances b where b.bakery_id=new.bakery_id and b.ingredient_id=new.ingredient_id;
 if v_prior<0 or v_cost is null or v_branch is null or v_actor is null then raise exception 'Invalid purchase cost state' using errcode='23514';end if;
 v_next:=round((v_prior*v_cost+new.quantity*new.unit_cost)/(v_prior+new.quantity),4);
 update public.ingredients set reference_cost=v_next where bakery_id=new.bakery_id and id=new.ingredient_id;
 insert into public.ingredient_cost_history(bakery_id,ingredient_id,branch_id,receipt_id,purchased_quantity,purchased_unit_cost,previous_quantity,previous_cost,new_cost,actor_id)
 values(new.bakery_id,new.ingredient_id,v_branch,new.receipt_id,new.quantity,new.unit_cost,v_prior,v_cost,v_next,v_actor);
 return new;
end $$;
revoke all on function bakery_private.update_purchase_average() from public,anon,authenticated;
create trigger purchase_weighted_average after insert on public.purchase_items for each row execute function bakery_private.update_purchase_average();
-- Base units are unchanged. Direct RPCs still validate exact base quantities and roles.
commit;
