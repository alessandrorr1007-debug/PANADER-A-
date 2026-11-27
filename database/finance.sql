-- Design draft: apply after commerce.sql in disposable PostgreSQL.
begin;
create table public.cash_shifts(
 id uuid primary key default gen_random_uuid(),
 bakery_id uuid not null, branch_id uuid not null, request_id uuid not null,
 opening_amount numeric(20,2) not null check(opening_amount between 0 and 999999999999999999),
 opened_by uuid not null, opened_at timestamptz not null default now(),
 closed_by uuid, closed_at timestamptz, counted_cash numeric(20,2), expected_cash numeric(30,2),
 check ((closed_at is null and closed_by is null and counted_cash is null and expected_cash is null)
 or (closed_at is not null and closed_by is not null and counted_cash is not null and expected_cash is not null and counted_cash>=0)),
 unique(bakery_id,id),unique(bakery_id,branch_id,id),unique(bakery_id,request_id),
 foreign key(bakery_id,branch_id) references public.branches(bakery_id,id)
);
create unique index one_open_shift_per_branch on public.cash_shifts(bakery_id,branch_id) where closed_at is null;
alter table public.sales add column cash_shift_id uuid;
alter table public.sales add constraint sales_cash_shift_fk foreign key(bakery_id,branch_id,cash_shift_id) references public.cash_shifts(bakery_id,branch_id,id);
create index sales_cash_shift_idx on public.sales(bakery_id,cash_shift_id);
create table public.cash_entries(
 id uuid primary key default gen_random_uuid(), bakery_id uuid not null, shift_id uuid not null, request_id uuid not null,
 direction text not null check(direction in ('in','out')), amount numeric(20,2) not null check(amount>0 and amount<=999999999999999999),
 reason text not null check(char_length(btrim(reason)) between 1 and 200), actor_id uuid not null, created_at timestamptz not null default now(),
 unique(bakery_id,request_id), foreign key(bakery_id,shift_id) references public.cash_shifts(bakery_id,id)
);
create index cash_entries_shift_idx on public.cash_entries(bakery_id,shift_id);
create table public.recipe_prices(
 bakery_id uuid not null, recipe_id uuid not null, unit_price numeric(12,2) not null check(unit_price>0 and unit_price<=9999999999.99),
 updated_by uuid not null, updated_at timestamptz not null default now(),
 primary key(bakery_id,recipe_id), foreign key(bakery_id,recipe_id) references public.recipe_versions(bakery_id,id)
);
alter table public.cash_shifts enable row level security;
revoke all on public.cash_shifts from public,anon,authenticated;
grant select on public.cash_shifts to authenticated;
create policy cash_shifts_read on public.cash_shifts for select to authenticated using(exists(select 1 from public.bakery_members m where m.bakery_id=cash_shifts.bakery_id and m.user_id=(select auth.uid())));
alter table public.cash_entries enable row level security;
revoke all on public.cash_entries from public,anon,authenticated;
grant select on public.cash_entries to authenticated;
create policy cash_entries_read on public.cash_entries for select to authenticated using(exists(select 1 from public.bakery_members m where m.bakery_id=cash_entries.bakery_id and m.user_id=(select auth.uid())));
alter table public.recipe_prices enable row level security;
revoke all on public.recipe_prices from public,anon,authenticated;
grant select on public.recipe_prices to authenticated;
create policy recipe_prices_read on public.recipe_prices for select to authenticated using(exists(select 1 from public.bakery_members m where m.bakery_id=recipe_prices.bakery_id and m.user_id=(select auth.uid())));
create view public.cash_summary with (security_invoker=true) as
 select c.bakery_id,c.branch_id,c.id as shift_id,c.opened_at,c.closed_at,c.opening_amount,
 s.cash_sales,s.digital_sales,e.cash_in,e.cash_out,
 coalesce(c.expected_cash,c.opening_amount+s.cash_sales+e.cash_in-e.cash_out) as expected_cash,
 c.counted_cash,c.counted_cash-c.expected_cash as difference
 from public.cash_shifts c
 cross join lateral (select coalesce(sum(total) filter(where payment_method='cash'),0) cash_sales,
 coalesce(sum(total) filter(where payment_method<>'cash'),0) digital_sales
 from public.sales s where s.bakery_id=c.bakery_id and s.cash_shift_id=c.id) s
 cross join lateral (select coalesce(sum(amount) filter(where direction='in'),0) cash_in,
 coalesce(sum(amount) filter(where direction='out'),0) cash_out
 from public.cash_entries e where e.bakery_id=c.bakery_id and e.shift_id=c.id) e;
create view public.daily_sales_summary with (security_invoker=true) as
 select s.bakery_id,s.branch_id,(s.created_at at time zone 'America/Lima')::date as business_date,
 count(*) as sale_count,sum(s.total) as revenue,
 sum(coalesce(l.units,0)) as units_sold,
 round(sum(coalesce(l.ingredient_cost,0)),2) as estimated_ingredient_cost,
 sum(s.total)-round(sum(coalesce(l.ingredient_cost,0)),2) as estimated_ingredient_margin
 from public.sales s
 left join lateral (select sum(i.units) as units,sum(i.units*b.reference_cost/b.output_units) as ingredient_cost
 from public.sale_items i join public.production_batches b on b.bakery_id=i.bakery_id and b.id=i.batch_id
 where i.bakery_id=s.bakery_id and i.sale_id=s.id) l on true
 group by s.bakery_id,s.branch_id,(s.created_at at time zone 'America/Lima')::date;
create view public.daily_purchase_summary with (security_invoker=true) as
 select bakery_id,branch_id,(created_at at time zone 'America/Lima')::date as business_date,count(*) as receipt_count,sum(total) as received_cost
 from public.purchase_receipts group by bakery_id,branch_id,(created_at at time zone 'America/Lima')::date;
revoke all on public.cash_summary,public.daily_sales_summary,public.daily_purchase_summary from public,anon,authenticated;
grant select on public.cash_summary,public.daily_sales_summary,public.daily_purchase_summary to authenticated;

create function bakery_private.open_cash_shift(p_bakery uuid,p_branch uuid,p_request uuid,p_opening numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.cash_shifts%rowtype; v_id uuid;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_commerce(p_bakery,p_branch,true);
 if p_request is null or p_opening is null or not(p_opening between 0 and 999999999999999999) or p_opening<>round(p_opening,2) then raise exception 'Invalid opening' using errcode='22023'; end if;
 select * into v_old from public.cash_shifts where bakery_id=p_bakery and request_id=p_request;
 if found then
 if v_old.branch_id=p_branch and v_old.opening_amount=p_opening and v_old.opened_by=auth.uid() then return v_old.id; end if;
 raise exception 'Request ID already used' using errcode='23505'; end if;
 insert into public.cash_shifts(bakery_id,branch_id,request_id,opening_amount,opened_by)
 values(p_bakery,p_branch,p_request,p_opening,auth.uid()) returning id into v_id;
 return v_id;
end $$;
create function bakery_private.add_cash_entry(p_bakery uuid,p_branch uuid,p_shift uuid,p_request uuid,p_direction text,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.cash_entries%rowtype; v_id uuid; v_expected numeric;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_commerce(p_bakery,p_branch,true);
 if p_request is null or p_direction is null or p_direction not in ('in','out') or p_amount is null or not(p_amount>0 and p_amount<=999999999999999999) or p_amount<>round(p_amount,2) or p_reason is null or char_length(btrim(p_reason)) not between 1 and 200 then raise exception 'Invalid cash entry' using errcode='22023'; end if;
 select * into v_old from public.cash_entries where bakery_id=p_bakery and request_id=p_request;
 if found then
 if v_old.shift_id=p_shift and v_old.direction=p_direction and v_old.amount=p_amount and v_old.reason=btrim(p_reason) and v_old.actor_id=auth.uid()
 and exists(select 1 from public.cash_shifts c where c.bakery_id=p_bakery and c.branch_id=p_branch and c.id=p_shift) then return v_old.id; end if;
 raise exception 'Request ID already used' using errcode='23505'; end if;
 select expected_cash into v_expected from public.cash_summary where bakery_id=p_bakery and branch_id=p_branch and shift_id=p_shift and closed_at is null;
 if not found then raise exception 'No open shift' using errcode='22023'; end if;
 if p_direction='out' and p_amount>v_expected then raise exception 'Insufficient cash' using errcode='23514'; end if;
 insert into public.cash_entries(bakery_id,shift_id,request_id,direction,amount,reason,actor_id)
 values(p_bakery,p_shift,p_request,p_direction,p_amount,btrim(p_reason),auth.uid()) returning id into v_id;
 return v_id;
end $$;
create function bakery_private.close_cash_shift(p_bakery uuid,p_branch uuid,p_shift uuid,p_counted numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_shift public.cash_shifts%rowtype; v_expected numeric;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 -- Permit closing an existing shift even if the branch was deactivated.
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid() and m.role in ('owner','admin')) then raise exception 'Cash access denied' using errcode='42501'; end if;
 if p_counted is null or not(p_counted between 0 and 999999999999999999) or p_counted<>round(p_counted,2) then raise exception 'Invalid cash count' using errcode='22023'; end if;
 select * into v_shift from public.cash_shifts where bakery_id=p_bakery and branch_id=p_branch and id=p_shift;
 if not found then raise exception 'Unknown shift' using errcode='22023'; end if;
 if v_shift.closed_at is not null then
 if v_shift.closed_by=auth.uid() and v_shift.counted_cash=p_counted then return p_shift; end if;
 raise exception 'Shift already closed' using errcode='23505'; end if;
 select expected_cash into v_expected from public.cash_summary where bakery_id=p_bakery and shift_id=p_shift;
 update public.cash_shifts set closed_by=auth.uid(),closed_at=now(),counted_cash=p_counted,expected_cash=v_expected where bakery_id=p_bakery and id=p_shift;
 return p_shift;
end $$;
create function bakery_private.set_recipe_price(p_bakery uuid,p_recipe uuid,p_price numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid() and m.role in ('owner','admin')) then raise exception 'Price access denied' using errcode='42501'; end if;
 if p_price is null or not(p_price>0 and p_price<=9999999999.99) or p_price<>round(p_price,2)
 or not exists(select 1 from public.recipe_versions r where r.bakery_id=p_bakery and r.id=p_recipe) then raise exception 'Invalid price or recipe' using errcode='22023'; end if;
 insert into public.recipe_prices(bakery_id,recipe_id,unit_price,updated_by) values(p_bakery,p_recipe,p_price,auth.uid())
 on conflict(bakery_id,recipe_id) do update set unit_price=excluded.unit_price,updated_by=excluded.updated_by,updated_at=now();
end $$;
-- These triggers also protect the existing record_sale RPC. It already holds the same lock.
create function bakery_private.attach_cash_shift() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.bakery_id::text,1));
 select c.id into new.cash_shift_id from public.cash_shifts c where c.bakery_id=new.bakery_id and c.branch_id=new.branch_id and c.closed_at is null;
 if new.cash_shift_id is null then raise exception 'Open cash shift required' using errcode='23514'; end if;
 return new;
end $$;
create trigger attach_cash_shift before insert on public.sales for each row execute function bakery_private.attach_cash_shift();
create function bakery_private.check_sale_price() returns trigger language plpgsql security invoker set search_path='' as $$
declare v_price numeric;
begin
 select p.unit_price into v_price from public.production_batches b join public.recipe_prices p on p.bakery_id=b.bakery_id and p.recipe_id=b.recipe_id where b.bakery_id=new.bakery_id and b.id=new.batch_id;
 if not found or new.unit_price<>v_price then raise exception 'Configured sale price required' using errcode='23514'; end if;
 return new;
end $$;
create trigger check_sale_price before insert on public.sale_items for each row execute function bakery_private.check_sale_price();
revoke all on function bakery_private.attach_cash_shift(),bakery_private.check_sale_price() from public,anon,authenticated;
create function public.open_cash_shift(p_bakery uuid,p_branch uuid,p_request uuid,p_opening numeric) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.open_cash_shift(p_bakery,p_branch,p_request,p_opening) $$;
revoke all on function public.open_cash_shift(uuid,uuid,uuid,numeric),bakery_private.open_cash_shift(uuid,uuid,uuid,numeric) from public,anon,authenticated;
grant execute on function public.open_cash_shift(uuid,uuid,uuid,numeric),bakery_private.open_cash_shift(uuid,uuid,uuid,numeric) to authenticated;
create function public.add_cash_entry(p_bakery uuid,p_branch uuid,p_shift uuid,p_request uuid,p_direction text,p_amount numeric,p_reason text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.add_cash_entry(p_bakery,p_branch,p_shift,p_request,p_direction,p_amount,p_reason) $$;
revoke all on function public.add_cash_entry(uuid,uuid,uuid,uuid,text,numeric,text),bakery_private.add_cash_entry(uuid,uuid,uuid,uuid,text,numeric,text) from public,anon,authenticated;
grant execute on function public.add_cash_entry(uuid,uuid,uuid,uuid,text,numeric,text),bakery_private.add_cash_entry(uuid,uuid,uuid,uuid,text,numeric,text) to authenticated;
create function public.close_cash_shift(p_bakery uuid,p_branch uuid,p_shift uuid,p_counted numeric) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.close_cash_shift(p_bakery,p_branch,p_shift,p_counted) $$;
revoke all on function public.close_cash_shift(uuid,uuid,uuid,numeric),bakery_private.close_cash_shift(uuid,uuid,uuid,numeric) from public,anon,authenticated;
grant execute on function public.close_cash_shift(uuid,uuid,uuid,numeric),bakery_private.close_cash_shift(uuid,uuid,uuid,numeric) to authenticated;
create function public.set_recipe_price(p_bakery uuid,p_recipe uuid,p_price numeric) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_recipe_price(p_bakery,p_recipe,p_price) $$;
revoke all on function public.set_recipe_price(uuid,uuid,numeric),bakery_private.set_recipe_price(uuid,uuid,numeric) from public,anon,authenticated;
grant execute on function public.set_recipe_price(uuid,uuid,numeric),bakery_private.set_recipe_price(uuid,uuid,numeric) to authenticated;
commit;
