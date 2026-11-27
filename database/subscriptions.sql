-- Design draft: apply after finance.sql in a disposable database.
begin;
create table public.saas_plans(
 code text primary key, name text not null, branch_limit integer not null check(branch_limit>0),
 member_limit integer not null check(member_limit>0)
);
insert into public.saas_plans values ('starter','Inicial',1,3),('growth','Crecimiento',3,10),('business','Empresa',10,30);
create table public.saas_subscriptions(
 bakery_id uuid primary key references public.bakeries(id),
 plan_code text not null references public.saas_plans(code),
 status text not null check(status in ('trial','active','suspended','cancelled')),
 valid_until timestamptz not null,
 updated_at timestamptz not null default now()
);
create table bakery_private.platform_admins(
 user_id uuid primary key references auth.users(id) on delete cascade
);
create table bakery_private.subscription_events(
 id uuid primary key default gen_random_uuid(), bakery_id uuid not null references public.bakeries(id),
 actor_id uuid not null, previous jsonb not null, current_state jsonb not null, created_at timestamptz not null default now()
);
alter table bakery_private.platform_admins enable row level security;
alter table bakery_private.subscription_events enable row level security;
revoke all on bakery_private.platform_admins,bakery_private.subscription_events from public,anon,authenticated;
alter table public.saas_plans enable row level security;
alter table public.saas_subscriptions enable row level security;
revoke all on public.saas_plans,public.saas_subscriptions from public,anon,authenticated;
grant select on public.saas_plans,public.saas_subscriptions to authenticated;
create policy plan_read on public.saas_plans for select to authenticated using(auth.uid() is not null);
create policy subscription_read on public.saas_subscriptions for select to authenticated using(
 exists(select 1 from public.bakery_members m where m.bakery_id=saas_subscriptions.bakery_id and m.user_id=(select auth.uid())));
-- No client can self-upgrade. Provision trial atomically before the initial membership/branch.
create function bakery_private.provision_trial() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.saas_subscriptions(bakery_id,plan_code,status,valid_until)
 values(new.id,'starter','trial',statement_timestamp()+interval '14 days');
 return new;
end $$;
revoke all on function bakery_private.provision_trial() from public,anon,authenticated;
create trigger provision_trial after insert on public.bakeries for each row execute function bakery_private.provision_trial();
-- Existing businesses in this development schema receive a trial at installation.
insert into public.saas_subscriptions(bakery_id,plan_code,status,valid_until)
 select id,'starter','trial',statement_timestamp()+interval '14 days' from public.bakeries;

create function bakery_private.enforce_entitlement() returns trigger language plpgsql security definer set search_path='' as $$
declare v_sub public.saas_subscriptions%rowtype; v_limit integer; v_count bigint;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.bakery_id::text,1));
 -- Safe exception: finish an already-open cash shift even on expiration.
 if tg_table_name='cash_shifts' and tg_op='UPDATE' then
  if (to_jsonb(old)->>'closed_at') is null and (to_jsonb(new)->>'closed_at') is not null then return new; end if;
 end if;
 -- Allow deactivating a branch to reduce usage even when expired.
 if tg_table_name='branches' and tg_op='UPDATE' then
  if old.active and not new.active and old.name=new.name then return new; end if;
 end if;
 select * into v_sub from public.saas_subscriptions s where s.bakery_id=new.bakery_id;
 if not found or v_sub.status not in ('trial','active') or v_sub.valid_until<=statement_timestamp()
 then raise exception 'Subscription inactive or expired' using errcode='42501'; end if;
 if tg_table_name='branches' then
  if new.active and (tg_op='INSERT' or not old.active) then
   select branch_limit into v_limit from public.saas_plans where code=v_sub.plan_code;
   select count(*) into v_count from public.branches b where b.bakery_id=new.bakery_id and b.active;
   if v_count>=v_limit then raise exception 'Branch limit reached' using errcode='23514'; end if;
  end if;
 elsif tg_table_name='bakery_members' and tg_op='INSERT' then
  select member_limit into v_limit from public.saas_plans where code=v_sub.plan_code;
  select count(*) into v_count from public.bakery_members m where m.bakery_id=new.bakery_id;
  if v_count>=v_limit then raise exception 'Member limit reached' using errcode='23514'; end if;
 end if;
 return new;
end $$;
revoke all on function bakery_private.enforce_entitlement() from public,anon,authenticated;
create trigger entitlement_guard before insert or update on public.ingredients for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.stock_balances for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.stock_movements for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.recipe_versions for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.recipe_items for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.production_batches for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.production_consumption for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.suppliers for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.purchase_receipts for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.purchase_items for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.sales for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.sale_items for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.cash_shifts for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.cash_entries for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.recipe_prices for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.branches for each row execute function bakery_private.enforce_entitlement();
create trigger entitlement_guard before insert or update on public.bakery_members for each row execute function bakery_private.enforce_entitlement();
create function bakery_private.assert_platform_admin() returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from bakery_private.platform_admins a where a.user_id=auth.uid()) then
  raise exception 'Platform administration denied' using errcode='42501'; end if;
end $$;
revoke all on function bakery_private.assert_platform_admin() from public,anon,authenticated;
create function bakery_private.list_customers()
returns table(bakery_id uuid,name text,plan_code text,status text,valid_until timestamptz,active_branches bigint,members bigint)
language plpgsql security definer set search_path='' as $$
begin
 perform bakery_private.assert_platform_admin();
 return query select b.id,b.name,s.plan_code,s.status,s.valid_until,
 (select count(*) from public.branches br where br.bakery_id=b.id and br.active),
 (select count(*) from public.bakery_members m where m.bakery_id=b.id)
 from public.bakeries b join public.saas_subscriptions s on s.bakery_id=b.id order by b.name,b.id;
end $$;
create function bakery_private.set_subscription(p_bakery uuid,p_plan text,p_status text,p_valid_until timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare v_old public.saas_subscriptions%rowtype; v_new public.saas_subscriptions%rowtype;
begin
 perform bakery_private.assert_platform_admin();
 if p_status is null or p_status not in ('trial','active','suspended','cancelled') or p_valid_until is null or not isfinite(p_valid_until)
 or not exists(select 1 from public.saas_plans p where p.code=p_plan)
 or (p_status in ('trial','active') and p_valid_until<=statement_timestamp()) then raise exception 'Invalid subscription' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 select * into v_old from public.saas_subscriptions where bakery_id=p_bakery;
 if not found then raise exception 'Unknown business' using errcode='22023'; end if;
 if v_old.plan_code=p_plan and v_old.status=p_status and v_old.valid_until=p_valid_until then return; end if;
 update public.saas_subscriptions set plan_code=p_plan,status=p_status,valid_until=p_valid_until,updated_at=statement_timestamp()
 where bakery_id=p_bakery returning * into v_new;
 insert into bakery_private.subscription_events(bakery_id,actor_id,previous,current_state)
 values(p_bakery,auth.uid(),to_jsonb(v_old),to_jsonb(v_new));
end $$;
create function public.list_customers()
returns table(bakery_id uuid,name text,plan_code text,status text,valid_until timestamptz,active_branches bigint,members bigint)
language sql security invoker set search_path='' as $$ select * from bakery_private.list_customers() $$;
create function public.set_subscription(p_bakery uuid,p_plan text,p_status text,p_valid_until timestamptz)
returns void language sql security invoker set search_path='' as $$ select bakery_private.set_subscription(p_bakery,p_plan,p_status,p_valid_until) $$;
revoke all on function public.list_customers() from public,anon,authenticated;
grant execute on function public.list_customers() to authenticated;
revoke all on function public.set_subscription(uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.set_subscription(uuid,text,text,timestamptz) to authenticated;
revoke all on function bakery_private.list_customers() from public,anon,authenticated;
grant execute on function bakery_private.list_customers() to authenticated;
revoke all on function bakery_private.set_subscription(uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function bakery_private.set_subscription(uuid,text,text,timestamptz) to authenticated;
commit;
