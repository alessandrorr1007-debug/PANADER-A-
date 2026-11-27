-- Apply after inventory-lots.sql. Three product-level identities; legacy internal roles stay compatible.
begin;
create table bakery_private.employee_permissions(
 bakery_id uuid not null,user_id uuid not null,permissions text[] not null default '{}',
 updated_by uuid not null,updated_at timestamptz not null default statement_timestamp(),
 primary key(bakery_id,user_id),
 foreign key(bakery_id,user_id) references public.bakery_members(bakery_id,user_id) on delete cascade,
 check(array_position(permissions,null) is null and permissions <@ array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[] and cardinality(permissions)<=8)
);
alter table bakery_private.employee_permissions enable row level security;
revoke all on bakery_private.employee_permissions from public,anon,authenticated;
-- Preserve pre-existing operational privileges, not team or subscription administration.
insert into bakery_private.employee_permissions(bakery_id,user_id,permissions,updated_by)
 select bakery_id,user_id,case role when 'admin' then array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[] when 'operator' then array['inventory','production','sales']::text[] else '{}'::text[] end,user_id
 from public.bakery_members where role<>'owner';
-- Internal admin is a compatibility carrier for worker RPCs. It confers no rights without grants.
-- No live memberships existed when this migration was prepared.
update public.bakery_members set role='admin' where role<>'owner';
alter table bakery_private.worker_invitations add column permissions text[] not null default '{}'
 check(array_position(permissions,null) is null and permissions <@ array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[] and cardinality(permissions)<=8);
update bakery_private.worker_invitations set permissions=case role when 'admin' then array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[] when 'operator' then array['inventory','production','sales']::text[] else '{}'::text[] end,role='admin' where status='pending';

create function bakery_private.has_permission(p_bakery uuid,p_permission text) returns boolean language sql stable security definer set search_path='' as $$
 select bakery_private.session_allowed() and p_permission=any(array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[]) and exists(
 select 1 from public.bakery_members m left join bakery_private.employee_permissions e on e.bakery_id=m.bakery_id and e.user_id=m.user_id
 where m.bakery_id=p_bakery and m.user_id=auth.uid() and (m.role='owner' or p_permission=any(coalesce(e.permissions,'{}'::text[]))))
$$;
revoke all on function bakery_private.has_permission(uuid,text) from public,anon,authenticated;
grant execute on function bakery_private.has_permission(uuid,text) to authenticated;
create function bakery_private.is_bakery_owner(p_bakery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select bakery_private.session_allowed() and exists(select 1 from public.bakery_members where bakery_id=p_bakery and user_id=auth.uid() and role='owner')
$$;
revoke all on function bakery_private.is_bakery_owner(uuid) from public,anon,authenticated;
grant execute on function bakery_private.is_bakery_owner(uuid) to authenticated;
create function bakery_private.require_permission(p_bakery uuid,p_permission text) returns void language plpgsql security invoker set search_path='' as $$
begin
 perform bakery_private.require_session();
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 if not bakery_private.has_permission(p_bakery,p_permission) then raise exception 'Operation permission denied' using errcode='42501';end if;
end $$;
revoke all on function bakery_private.require_permission(uuid,text) from public,anon,authenticated;
create function bakery_private.my_permissions(p_bakery uuid) returns text[] language plpgsql stable security definer set search_path='' as $$
declare v_role text;v_permissions text[];
begin
 v_role:=bakery_private.team_role(p_bakery);
 if v_role='owner' then return array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[];end if;
 select permissions into v_permissions from bakery_private.employee_permissions where bakery_id=p_bakery and user_id=auth.uid();
 return coalesce(v_permissions,'{}'::text[]);
end $$;
create function bakery_private.team_permissions(p_bakery uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not bakery_private.is_bakery_owner(p_bakery) then raise exception 'Owner required' using errcode='42501';end if;
 return coalesce((select jsonb_object_agg(m.user_id::text,coalesce(e.permissions,'{}'::text[])) from public.bakery_members m left join bakery_private.employee_permissions e on e.bakery_id=m.bakery_id and e.user_id=m.user_id where m.bakery_id=p_bakery and m.role<>'owner'),'{}'::jsonb);
end $$;
create function bakery_private.normalize_permissions(p_permissions text[]) returns text[] language plpgsql immutable security invoker set search_path='' as $$
begin
 if p_permissions is null or array_position(p_permissions,null) is not null or cardinality(p_permissions)>8 or not(p_permissions <@ array['inventory','recipes','production','purchases','sales','prices','cash','reports']::text[]) then raise exception 'Invalid permissions' using errcode='22023';end if;
 return array(select distinct x from unnest(p_permissions) as p(x) order by x);
end $$;
revoke all on function bakery_private.normalize_permissions(text[]) from public,anon,authenticated;
create function bakery_private.set_employee_permissions(p_bakery uuid,p_user uuid,p_permissions text[]) returns void language plpgsql security definer set search_path='' as $$
declare v_permissions text[];
begin
 perform bakery_private.require_session();
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 if not bakery_private.is_bakery_owner(p_bakery) or not exists(select 1 from public.bakery_members where bakery_id=p_bakery and user_id=p_user and role<>'owner') then raise exception 'Only owner may configure an employee' using errcode='42501';end if;
 v_permissions:=bakery_private.normalize_permissions(p_permissions);
 -- Permit reduction/revocation when expired; new rights require an active subscription.
 if not(v_permissions <@ coalesce((select permissions from bakery_private.employee_permissions where bakery_id=p_bakery and user_id=p_user),'{}'::text[])) and not exists(select 1 from public.saas_subscriptions where bakery_id=p_bakery and status in ('trial','active') and valid_until>statement_timestamp()) then raise exception 'Subscription inactive' using errcode='42501';end if;
 insert into bakery_private.employee_permissions(bakery_id,user_id,permissions,updated_by) values(p_bakery,p_user,v_permissions,auth.uid()) on conflict(bakery_id,user_id) do update set permissions=excluded.permissions,updated_by=excluded.updated_by,updated_at=statement_timestamp();
end $$;
create function bakery_private.invite_employee(p_bakery uuid,p_email text,p_permissions text[]) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_permissions text[];
begin
 if not bakery_private.is_bakery_owner(p_bakery) then raise exception 'Owner required' using errcode='42501';end if;
 v_permissions:=bakery_private.normalize_permissions(p_permissions);
 v_id:=bakery_private.invite_worker(p_bakery,p_email,'admin');
 update bakery_private.worker_invitations set permissions=v_permissions where id=v_id;
 return v_id;
end $$;
create function public.my_permissions(p_bakery uuid) returns text[] language sql security invoker set search_path='' as $$ select bakery_private.my_permissions(p_bakery) $$;
revoke all on function public.my_permissions(uuid),bakery_private.my_permissions(uuid) from public,anon,authenticated;
grant execute on function public.my_permissions(uuid),bakery_private.my_permissions(uuid) to authenticated;
create function public.team_permissions(p_bakery uuid) returns jsonb language sql security invoker set search_path='' as $$ select bakery_private.team_permissions(p_bakery) $$;
revoke all on function public.team_permissions(uuid),bakery_private.team_permissions(uuid) from public,anon,authenticated;
grant execute on function public.team_permissions(uuid),bakery_private.team_permissions(uuid) to authenticated;
create function public.set_employee_permissions(p_bakery uuid,p_user uuid,p_permissions text[]) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_employee_permissions(p_bakery,p_user,p_permissions) $$;
revoke all on function public.set_employee_permissions(uuid,uuid,text[]),bakery_private.set_employee_permissions(uuid,uuid,text[]) from public,anon,authenticated;
grant execute on function public.set_employee_permissions(uuid,uuid,text[]),bakery_private.set_employee_permissions(uuid,uuid,text[]) to authenticated;
create function public.invite_employee(p_bakery uuid,p_email text,p_permissions text[]) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.invite_employee(p_bakery,p_email,p_permissions) $$;
revoke all on function public.invite_employee(uuid,text,text[]),bakery_private.invite_employee(uuid,text,text[]) from public,anon,authenticated;
grant execute on function public.invite_employee(uuid,text,text[]),bakery_private.invite_employee(uuid,text,text[]) to authenticated;
create or replace function bakery_private.invite_worker(p_bakery uuid,p_email text,p_role text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_role text;v_email text:=lower(btrim(p_email));v_id uuid;v_limit integer;
begin
 perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 v_role:=bakery_private.team_role(p_bakery);
 if v_role<>'owner' or p_role is null or p_role not in ('admin','operator','viewer') then raise exception 'Invitation denied' using errcode='42501';end if;
 if v_email is null or char_length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email' using errcode='22023';end if;
 select p.member_limit into v_limit from public.saas_subscriptions s join public.saas_plans p on p.code=s.plan_code where s.bakery_id=p_bakery and s.status in ('trial','active') and s.valid_until>statement_timestamp();
 if not found then raise exception 'Subscription inactive' using errcode='42501';end if;
 update bakery_private.worker_invitations set status='revoked' where bakery_id=p_bakery and status='pending' and expires_at<=statement_timestamp();
 if exists(select 1 from public.bakery_members m join auth.users u on u.id=m.user_id where m.bakery_id=p_bakery and lower(u.email)=v_email) then raise exception 'Already a member' using errcode='23505';end if;
 select id into v_id from bakery_private.worker_invitations where bakery_id=p_bakery and email=v_email and status='pending';
 if found then raise exception 'Invitation already pending' using errcode='23505';end if;
 if (select count(*) from public.bakery_members where bakery_id=p_bakery)+(select count(*) from bakery_private.worker_invitations where bakery_id=p_bakery and status='pending')>=v_limit then raise exception 'Member limit reached' using errcode='23514';end if;
 insert into bakery_private.worker_invitations(bakery_id,email,role,invited_by) values(p_bakery,v_email,'admin',auth.uid()) returning id into v_id;return v_id;
end $$;
create or replace function bakery_private.accept_invitation(p_invite uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare i bakery_private.worker_invitations%rowtype;v_user uuid:=auth.uid();
begin
 perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
 select * into i from bakery_private.worker_invitations where id=p_invite;
 if not found then raise exception 'Invitation unavailable' using errcode='42501';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(i.bakery_id::text,1));
 select * into i from bakery_private.worker_invitations where id=p_invite;
 if i.status='accepted' and i.accepted_by=v_user and exists(select 1 from public.bakery_members m where m.bakery_id=i.bakery_id and m.user_id=v_user) then return i.bakery_id;end if;
 if i.status<>'pending' or i.expires_at<=statement_timestamp() or not exists(select 1 from auth.users u where u.id=v_user and lower(u.email)=i.email and u.email_confirmed_at is not null and not u.is_anonymous) then raise exception 'Invitation unavailable' using errcode='42501';end if;
 -- An invitation cannot outlive the inviter's authorization.
 if not exists(select 1 from public.bakery_members m where m.bakery_id=i.bakery_id and m.user_id=i.invited_by and m.role='owner') then raise exception 'Inviter no longer authorized' using errcode='42501';end if;
 insert into public.bakery_members(bakery_id,user_id,role) values(i.bakery_id,v_user,'admin') on conflict(bakery_id,user_id) do nothing;
 if found then insert into bakery_private.employee_permissions(bakery_id,user_id,permissions,updated_by) values(i.bakery_id,v_user,i.permissions,i.invited_by);end if;
 update bakery_private.worker_invitations set status='accepted',accepted_by=v_user where id=p_invite;return i.bakery_id;
end $$;
create or replace function bakery_private.team_members(p_bakery uuid) returns table(user_id uuid,email text,role text) language plpgsql security definer set search_path='' as $$
begin if bakery_private.team_role(p_bakery) <>'owner' then raise exception 'Team access denied' using errcode='42501';end if;
 return query select m.user_id,u.email::text,m.role from public.bakery_members m join auth.users u on u.id=m.user_id where m.bakery_id=p_bakery order by m.role,u.email limit 100;end $$;
create or replace function bakery_private.team_invitations(p_bakery uuid) returns table(id uuid,email text,role text,status text,expires_at timestamptz) language plpgsql security definer set search_path='' as $$
begin if bakery_private.team_role(p_bakery) <>'owner' then raise exception 'Team access denied' using errcode='42501';end if;
 return query select i.id,i.email,i.role,case when i.status='pending' and i.expires_at<=statement_timestamp() then 'expired' else i.status end,i.expires_at from bakery_private.worker_invitations i where i.bakery_id=p_bakery order by i.created_at desc limit 100;end $$;
create or replace function bakery_private.revoke_invitation(p_bakery uuid,p_invite uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_role text;begin perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));v_role:=bakery_private.team_role(p_bakery);
 if v_role <>'owner' then raise exception 'Invitation denied' using errcode='42501';end if;
 update bakery_private.worker_invitations set status='revoked' where id=p_invite and bakery_id=p_bakery and status='pending' and (v_role='owner' or role<>'admin');
 if not found then raise exception 'Invitation unavailable' using errcode='42501';end if;end $$;
create or replace function bakery_private.remove_worker(p_bakery uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_role text;begin perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));v_role:=bakery_private.team_role(p_bakery);
 if v_role <>'owner' or p_user=auth.uid() then raise exception 'Removal denied' using errcode='42501';end if;
 delete from public.bakery_members where bakery_id=p_bakery and user_id=p_user and role<>'owner' and (v_role='owner' or role in ('operator','viewer'));
 if not found then raise exception 'Removal denied' using errcode='42501';end if;end $$;
create policy employee_insert_gate on public.branches as restrictive for insert to authenticated with check (bakery_private.is_bakery_owner(bakery_id));
create policy employee_update_gate on public.branches as restrictive for update to authenticated using (bakery_private.is_bakery_owner(bakery_id)) with check (bakery_private.is_bakery_owner(bakery_id));
create policy employee_insert_gate on public.ingredients as restrictive for insert to authenticated with check (bakery_private.has_permission(bakery_id,'inventory'));
create policy employee_update_gate on public.ingredients as restrictive for update to authenticated using (bakery_private.has_permission(bakery_id,'inventory')) with check (bakery_private.has_permission(bakery_id,'inventory'));
create policy employee_insert_gate on public.suppliers as restrictive for insert to authenticated with check (bakery_private.has_permission(bakery_id,'purchases'));
create policy employee_update_gate on public.suppliers as restrictive for update to authenticated using (bakery_private.has_permission(bakery_id,'purchases')) with check (bakery_private.has_permission(bakery_id,'purchases'));
create policy employee_read_gate on public.ingredients as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'inventory') or bakery_private.has_permission(bakery_id,'recipes') or bakery_private.has_permission(bakery_id,'production') or bakery_private.has_permission(bakery_id,'purchases'));
create policy employee_read_gate on public.stock_balances as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'inventory') or bakery_private.has_permission(bakery_id,'recipes') or bakery_private.has_permission(bakery_id,'production'));
create policy employee_read_gate on public.stock_movements as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'inventory'));
create policy employee_read_gate on public.stock_lots as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'inventory') or bakery_private.has_permission(bakery_id,'recipes') or bakery_private.has_permission(bakery_id,'production'));
create policy employee_read_gate on public.stock_lot_allocations as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'inventory'));
create policy employee_read_gate on public.ingredient_cost_history as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'inventory') or bakery_private.has_permission(bakery_id,'purchases'));
create policy employee_read_gate on public.recipe_versions as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'recipes') or bakery_private.has_permission(bakery_id,'production') or bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'prices') or bakery_private.has_permission(bakery_id,'reports'));
create policy employee_read_gate on public.recipe_items as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'recipes') or bakery_private.has_permission(bakery_id,'production'));
create policy employee_read_gate on public.production_batches as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'production') or bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'reports'));
create policy employee_read_gate on public.production_consumption as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'production'));
create policy employee_read_gate on public.suppliers as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'purchases'));
create policy employee_read_gate on public.purchase_receipts as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'purchases') or bakery_private.has_permission(bakery_id,'reports'));
create policy employee_read_gate on public.purchase_items as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'purchases'));
create policy employee_read_gate on public.sales as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'cash') or bakery_private.has_permission(bakery_id,'reports'));
create policy employee_read_gate on public.sale_items as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'reports'));
create policy employee_read_gate on public.cash_shifts as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'cash'));
create policy employee_read_gate on public.cash_entries as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'cash') or bakery_private.has_permission(bakery_id,'sales'));
create policy employee_read_gate on public.recipe_prices as restrictive for select to authenticated using (bakery_private.has_permission(bakery_id,'sales') or bakery_private.has_permission(bakery_id,'prices'));
create or replace function bakery_private.apply_lot_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text,p_lot_code text,p_expires_on date,p_waste_lot uuid)
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
revoke all on function bakery_private.apply_lot_movement(uuid,uuid,uuid,uuid,text,numeric,text,text,date,uuid) from public,anon,authenticated;
create or replace function bakery_private.record_lot_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text,p_lot_code text,p_expires_on date,p_waste_lot uuid) returns uuid language plpgsql security definer set search_path='' as $$
begin
 perform bakery_private.require_permission(p_bakery,'inventory');
 return bakery_private.apply_lot_movement(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,p_reason,p_lot_code,p_expires_on,p_waste_lot);
end $$;
create or replace function bakery_private.set_stock_minimum(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_minimum numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform bakery_private.require_permission(p_bakery,'inventory');
 if p_minimum is null or not (p_minimum between 0 and 99999999999) or p_minimum<>round(p_minimum,3) then raise exception 'Invalid minimum' using errcode='22023'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 perform bakery_private.assert_inventory_access(p_bakery,p_branch,p_ingredient,true);
 insert into public.stock_balances(bakery_id,branch_id,ingredient_id,minimum) values(p_bakery,p_branch,p_ingredient,p_minimum)
 on conflict(bakery_id,branch_id,ingredient_id) do update set minimum=excluded.minimum;
end $$;
create or replace function bakery_private.create_recipe_version(p_bakery uuid,p_name text,p_yield integer,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_recipe uuid; v_version integer; v_item jsonb; v_ingredient uuid; v_quantity numeric;
begin
 perform bakery_private.require_permission(p_bakery,'recipes');
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
create or replace function bakery_private.complete_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_existing public.production_batches%rowtype; v_batch uuid; v_yield integer; v_line record; v_qty numeric; v_move uuid; v_total numeric:=0;
begin
 perform bakery_private.require_permission(p_bakery,'production');
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
  v_move:=bakery_private.apply_lot_movement(p_bakery,p_branch,v_line.ingredient_id,gen_random_uuid(),'out',v_qty,'Producción '||v_batch::text,null,null,null);
  insert into public.production_consumption(bakery_id,batch_id,ingredient_id,movement_id,quantity,unit_cost)
  values(p_bakery,v_batch,v_line.ingredient_id,v_move,v_qty,v_line.reference_cost);
  v_total:=v_total+v_qty*v_line.reference_cost;
 end loop;
 update public.production_batches set reference_cost=v_total where bakery_id=p_bakery and id=v_batch;
 return v_batch;
end $$;
create or replace function bakery_private.receive_purchase(p_bakery uuid,p_branch uuid,p_supplier uuid,p_request uuid,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.purchase_receipts%rowtype; v_receipt uuid; v_line jsonb; v_ingredient uuid; v_qty numeric; v_cost numeric; v_move uuid; v_total numeric:=0;
begin
 perform bakery_private.require_permission(p_bakery,'purchases');
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
  v_move:=bakery_private.apply_lot_movement(p_bakery,p_branch,v_ingredient,gen_random_uuid(),'in',v_qty,'Compra '||v_receipt::text,v_line->>'lot_code',nullif(v_line->>'expires_on','')::date,null);
  insert into public.purchase_items(bakery_id,receipt_id,ingredient_id,movement_id,quantity,unit_cost)
  values(p_bakery,v_receipt,v_ingredient,v_move,v_qty,v_cost);
  v_total:=v_total+round(v_qty*v_cost,2);
 end loop;
 update public.purchase_receipts set total=v_total where bakery_id=p_bakery and id=v_receipt;
 return v_receipt;
end $$;
create or replace function bakery_private.record_sale(p_bakery uuid,p_branch uuid,p_request uuid,p_payment text,p_items jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.sales%rowtype; v_sale uuid; v_line jsonb; v_batch uuid; v_units numeric; v_price numeric; v_available bigint; v_total numeric:=0;
begin
 perform bakery_private.require_permission(p_bakery,'sales');
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
create or replace function bakery_private.open_cash_shift(p_bakery uuid,p_branch uuid,p_request uuid,p_opening numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.cash_shifts%rowtype; v_id uuid;
begin
 perform bakery_private.require_permission(p_bakery,'cash');
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
create or replace function bakery_private.add_cash_entry(p_bakery uuid,p_branch uuid,p_shift uuid,p_request uuid,p_direction text,p_amount numeric,p_reason text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.cash_entries%rowtype; v_id uuid; v_expected numeric;
begin
 perform bakery_private.require_permission(p_bakery,'cash');
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
create or replace function bakery_private.close_cash_shift(p_bakery uuid,p_branch uuid,p_shift uuid,p_counted numeric)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_shift public.cash_shifts%rowtype; v_expected numeric;
begin
 perform bakery_private.require_permission(p_bakery,'cash');
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
create or replace function bakery_private.set_recipe_price(p_bakery uuid,p_recipe uuid,p_price numeric)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform bakery_private.require_permission(p_bakery,'prices');
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 if auth.uid() is null or not exists(select 1 from public.bakery_members m where m.bakery_id=p_bakery and m.user_id=auth.uid() and m.role in ('owner','admin')) then raise exception 'Price access denied' using errcode='42501'; end if;
 if p_price is null or not(p_price>0 and p_price<=9999999999.99) or p_price<>round(p_price,2)
 or not exists(select 1 from public.recipe_versions r where r.bakery_id=p_bakery and r.id=p_recipe) then raise exception 'Invalid price or recipe' using errcode='22023'; end if;
 insert into public.recipe_prices(bakery_id,recipe_id,unit_price,updated_by) values(p_bakery,p_recipe,p_price,auth.uid())
 on conflict(bakery_id,recipe_id) do update set unit_price=excluded.unit_price,updated_by=excluded.updated_by,updated_at=now();
end $$;
commit;
