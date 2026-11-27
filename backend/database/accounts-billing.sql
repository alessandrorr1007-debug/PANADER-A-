-- Draft after subscriptions.sql. Keep bakery_private outside exposed schemas.
begin;
create table bakery_private.portal_sessions(
 session_id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 label text not null check(char_length(label) between 1 and 80), started_at timestamptz not null default now(), revoked_at timestamptz
);
create unique index portal_one_active on bakery_private.portal_sessions(user_id) where revoked_at is null;
create table bakery_private.worker_invitations(
 id uuid primary key default gen_random_uuid(), bakery_id uuid not null references public.bakeries(id),
 email text not null, role text not null check(role in ('admin','operator','viewer')), invited_by uuid not null,
 created_at timestamptz not null default now(), expires_at timestamptz not null default now()+interval '7 days',
 status text not null default 'pending' check(status in ('pending','accepted','revoked')), accepted_by uuid
);
create unique index worker_pending_email on bakery_private.worker_invitations(bakery_id,email) where status='pending';
create table bakery_private.billing_prices(
 plan_code text not null references public.saas_plans(code), period text not null check(period in ('month','year')),
 amount numeric(12,2) not null check(amount>0), enabled boolean not null default false, primary key(plan_code,period)
);
create table bakery_private.billing_methods(
 method text primary key check(method in ('yape','plin','transfer')), instructions text not null check(char_length(btrim(instructions)) between 1 and 500), enabled boolean not null default false
);
create table bakery_private.billing_payments(
 id uuid primary key default gen_random_uuid(), bakery_id uuid not null references public.bakeries(id), request_id uuid not null,
 plan_code text not null references public.saas_plans(code), period text not null check(period in ('month','year')),
 method text not null references bakery_private.billing_methods(method), reference text not null, amount numeric(12,2) not null check(amount>0),
 submitted_by uuid not null, created_at timestamptz not null default now(),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 reviewed_by uuid, reviewed_at timestamptz, review_note text, granted_until timestamptz,
 unique(bakery_id,request_id), check((status='pending' and reviewed_by is null and reviewed_at is null and granted_until is null)
 or (status='approved' and reviewed_by is not null and reviewed_at is not null and granted_until is not null)
 or (status='rejected' and reviewed_by is not null and reviewed_at is not null and granted_until is null))
);
create unique index billing_one_pending on bakery_private.billing_payments(bakery_id) where status='pending';
create unique index billing_reference_once on bakery_private.billing_payments(method,reference) where status in ('pending','approved');
do $$ declare t text; begin
 foreach t in array array['portal_sessions','worker_invitations','billing_prices','billing_methods','billing_payments'] loop
 execute format('alter table bakery_private.%I enable row level security',t);
 execute format('revoke all on bakery_private.%I from public, anon, authenticated',t);
 end loop;
end $$;

-- A real signed session_id must exist in Auth. No browser-generated ID is trusted.
create function bakery_private.session_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from bakery_private.portal_sessions p join auth.sessions s on s.id=p.session_id and s.user_id=p.user_id
 join auth.users u on u.id=p.user_id where p.user_id=auth.uid() and p.session_id::text=auth.jwt()->>'session_id'
 and p.revoked_at is null and u.email_confirmed_at is not null and not u.is_anonymous)
$$;
revoke all on function bakery_private.session_allowed() from public,anon,authenticated;
grant execute on function bakery_private.session_allowed() to authenticated;
create function bakery_private.require_session() returns void language plpgsql security invoker set search_path='' as $$
begin if not bakery_private.session_allowed() then raise exception 'Portal session inactive' using errcode='42501'; end if; end $$;
revoke all on function bakery_private.require_session() from public,anon,authenticated;
grant execute on function bakery_private.require_session() to authenticated;

create function bakery_private.register_portal_session(p_label text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_session uuid; old_row bakery_private.portal_sessions%rowtype;
begin
 if v_user is null or p_label is null or char_length(btrim(p_label)) not between 1 and 80 then raise exception 'Invalid session' using errcode='42501'; end if;
 select s.id into v_session from auth.sessions s join auth.users u on u.id=s.user_id where s.user_id=v_user and s.id::text=auth.jwt()->>'session_id' and u.email_confirmed_at is not null and not u.is_anonymous;
 if not found then raise exception 'Verified Auth session required' using errcode='42501'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,2));
 select * into old_row from bakery_private.portal_sessions where session_id=v_session;
 if found then
  if old_row.user_id<>v_user or old_row.revoked_at is not null then raise exception 'Session revoked; sign in again' using errcode='42501'; end if;
  return v_session;
 end if;
 update bakery_private.portal_sessions set revoked_at=now() where user_id=v_user and revoked_at is null;
 insert into bakery_private.portal_sessions(session_id,user_id,label) values(v_session,v_user,btrim(p_label));
 return v_session;
end $$;
create function bakery_private.my_portal_sessions() returns table(session_id uuid,label text,started_at timestamptz,revoked_at timestamptz,is_current boolean)
language plpgsql security definer set search_path='' as $$
begin perform bakery_private.require_session();return query
 select p.session_id,p.label,p.started_at,p.revoked_at,p.session_id::text=auth.jwt()->>'session_id'
 from bakery_private.portal_sessions p where p.user_id=auth.uid() order by p.started_at desc,p.session_id limit 30;end $$;
create function bakery_private.revoke_portal_session(p_session uuid) returns void language plpgsql security definer set search_path='' as $$
begin perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text,2));
 update bakery_private.portal_sessions set revoked_at=coalesce(revoked_at,now()) where user_id=auth.uid() and session_id=p_session;
 if not found then raise exception 'Unknown session' using errcode='42501';end if;end $$;

-- RLS gate every exposed table, including existing views via their security_invoker base tables.
do $$ declare t text; begin
 foreach t in array array['bakeries','bakery_members','branches','ingredients','stock_balances','stock_movements','recipe_versions','recipe_items','production_batches','production_consumption','suppliers','purchase_receipts','purchase_items','sales','sale_items','cash_shifts','cash_entries','recipe_prices','saas_plans','saas_subscriptions'] loop
 execute format('create policy portal_session_gate on public.%I as restrictive for all to authenticated using ((select bakery_private.session_allowed())) with check ((select bakery_private.session_allowed()))',t);
 end loop;
end $$;

create function bakery_private.team_role(p_bakery uuid) returns text language plpgsql security definer set search_path='' as $$
declare v_role text;begin perform bakery_private.require_session();
 select role into v_role from public.bakery_members where bakery_id=p_bakery and user_id=auth.uid();
 if v_role is null then raise exception 'Membership required' using errcode='42501';end if;return v_role;end $$;
revoke all on function bakery_private.team_role(uuid) from public,anon,authenticated;
create function bakery_private.invite_worker(p_bakery uuid,p_email text,p_role text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_role text;v_email text:=lower(btrim(p_email));v_id uuid;v_limit integer;
begin
 perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 v_role:=bakery_private.team_role(p_bakery);
 if v_role not in ('owner','admin') or p_role is null or p_role not in ('admin','operator','viewer') or (p_role='admin' and v_role<>'owner') then raise exception 'Invitation denied' using errcode='42501';end if;
 if v_email is null or char_length(v_email)>254 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Invalid email' using errcode='22023';end if;
 select p.member_limit into v_limit from public.saas_subscriptions s join public.saas_plans p on p.code=s.plan_code where s.bakery_id=p_bakery and s.status in ('trial','active') and s.valid_until>statement_timestamp();
 if not found then raise exception 'Subscription inactive' using errcode='42501';end if;
 update bakery_private.worker_invitations set status='revoked' where bakery_id=p_bakery and status='pending' and expires_at<=statement_timestamp();
 if exists(select 1 from public.bakery_members m join auth.users u on u.id=m.user_id where m.bakery_id=p_bakery and lower(u.email)=v_email) then raise exception 'Already a member' using errcode='23505';end if;
 select id into v_id from bakery_private.worker_invitations where bakery_id=p_bakery and email=v_email and status='pending';
 if found then raise exception 'Invitation already pending' using errcode='23505';end if;
 if (select count(*) from public.bakery_members where bakery_id=p_bakery)+(select count(*) from bakery_private.worker_invitations where bakery_id=p_bakery and status='pending')>=v_limit then raise exception 'Member limit reached' using errcode='23514';end if;
 insert into bakery_private.worker_invitations(bakery_id,email,role,invited_by) values(p_bakery,v_email,p_role,auth.uid()) returning id into v_id;return v_id;
end $$;
create function bakery_private.my_invitations() returns table(id uuid,bakery_name text,role text,expires_at timestamptz) language plpgsql security definer set search_path='' as $$
begin perform bakery_private.require_session();return query select i.id,b.name,i.role,i.expires_at
 from bakery_private.worker_invitations i join public.bakeries b on b.id=i.bakery_id join auth.users u on u.id=auth.uid()
 where i.email=lower(u.email) and i.status='pending' and i.expires_at>statement_timestamp() and u.email_confirmed_at is not null and not u.is_anonymous order by i.created_at desc limit 100;end $$;
create function bakery_private.accept_invitation(p_invite uuid) returns uuid language plpgsql security definer set search_path='' as $$
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
 if not exists(select 1 from public.bakery_members m where m.bakery_id=i.bakery_id and m.user_id=i.invited_by and (m.role='owner' or (m.role='admin' and i.role<>'admin'))) then raise exception 'Inviter no longer authorized' using errcode='42501';end if;
 insert into public.bakery_members(bakery_id,user_id,role) values(i.bakery_id,v_user,i.role) on conflict(bakery_id,user_id) do nothing;
 update bakery_private.worker_invitations set status='accepted',accepted_by=v_user where id=p_invite;return i.bakery_id;
end $$;
create function bakery_private.team_members(p_bakery uuid) returns table(user_id uuid,email text,role text) language plpgsql security definer set search_path='' as $$
begin if bakery_private.team_role(p_bakery) not in ('owner','admin') then raise exception 'Team access denied' using errcode='42501';end if;
 return query select m.user_id,u.email::text,m.role from public.bakery_members m join auth.users u on u.id=m.user_id where m.bakery_id=p_bakery order by m.role,u.email limit 100;end $$;
create function bakery_private.team_invitations(p_bakery uuid) returns table(id uuid,email text,role text,status text,expires_at timestamptz) language plpgsql security definer set search_path='' as $$
begin if bakery_private.team_role(p_bakery) not in ('owner','admin') then raise exception 'Team access denied' using errcode='42501';end if;
 return query select i.id,i.email,i.role,case when i.status='pending' and i.expires_at<=statement_timestamp() then 'expired' else i.status end,i.expires_at from bakery_private.worker_invitations i where i.bakery_id=p_bakery order by i.created_at desc limit 100;end $$;
create function bakery_private.revoke_invitation(p_bakery uuid,p_invite uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_role text;begin perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));v_role:=bakery_private.team_role(p_bakery);
 if v_role not in ('owner','admin') then raise exception 'Invitation denied' using errcode='42501';end if;
 update bakery_private.worker_invitations set status='revoked' where id=p_invite and bakery_id=p_bakery and status='pending' and (v_role='owner' or role<>'admin');
 if not found then raise exception 'Invitation unavailable' using errcode='42501';end if;end $$;
create function bakery_private.remove_worker(p_bakery uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
declare v_role text;begin perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));v_role:=bakery_private.team_role(p_bakery);
 if v_role not in ('owner','admin') or p_user=auth.uid() then raise exception 'Removal denied' using errcode='42501';end if;
 delete from public.bakery_members where bakery_id=p_bakery and user_id=p_user and role<>'owner' and (v_role='owner' or role in ('operator','viewer'));
 if not found then raise exception 'Removal denied' using errcode='42501';end if;end $$;

-- Manual billing: prices and receiving instructions must be explicitly configured by a platform administrator.
create function bakery_private.set_billing_price(p_plan text,p_period text,p_amount numeric,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin perform bakery_private.require_session();perform bakery_private.assert_platform_admin();
 if p_amount is null or not(p_amount between 0.01 and 9999999999.99) or p_amount<>round(p_amount,2) or p_enabled is null then raise exception 'Invalid price' using errcode='22023';end if;
 insert into bakery_private.billing_prices(plan_code,period,amount,enabled) values(p_plan,p_period,p_amount,p_enabled) on conflict(plan_code,period) do update set amount=excluded.amount,enabled=excluded.enabled;end $$;
create function bakery_private.set_billing_method(p_method text,p_instructions text,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
begin perform bakery_private.require_session();perform bakery_private.assert_platform_admin();
 insert into bakery_private.billing_methods(method,instructions,enabled) values(p_method,btrim(p_instructions),p_enabled) on conflict(method) do update set instructions=excluded.instructions,enabled=excluded.enabled;end $$;
create function bakery_private.billing_options() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_admin boolean;begin perform bakery_private.require_session();select exists(select 1 from bakery_private.platform_admins where user_id=auth.uid()) into v_admin;
 return jsonb_build_object('prices',coalesce((select jsonb_agg(to_jsonb(p) order by p.plan_code,p.period) from bakery_private.billing_prices p where p.enabled or v_admin),'[]'::jsonb),
 'methods',coalesce((select jsonb_agg(to_jsonb(m) order by m.method) from bakery_private.billing_methods m where m.enabled or v_admin),'[]'::jsonb));end $$;
create function bakery_private.submit_billing_payment(p_bakery uuid,p_request uuid,p_plan text,p_period text,p_method text,p_reference text,p_amount numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare v_old bakery_private.billing_payments%rowtype;v_sub public.saas_subscriptions%rowtype;v_amount numeric;v_ref text:=upper(btrim(p_reference));v_id uuid;
begin perform bakery_private.require_session();perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_bakery::text,1));
 if bakery_private.team_role(p_bakery)<>'owner' then raise exception 'Owner required' using errcode='42501';end if;
 if p_request is null or v_ref is null or char_length(v_ref) not between 4 and 80 or v_ref !~ '^[A-Z0-9][A-Z0-9._/-]*$' then raise exception 'Invalid payment reference' using errcode='22023';end if;
 select * into v_old from bakery_private.billing_payments where bakery_id=p_bakery and request_id=p_request;
 if found then
 if v_old.submitted_by=auth.uid() and v_old.plan_code=p_plan and v_old.period=p_period and v_old.method=p_method and v_old.reference=v_ref and v_old.amount=p_amount then return v_old.id;end if;
 raise exception 'Request already used' using errcode='23505';end if;
 select * into v_sub from public.saas_subscriptions where bakery_id=p_bakery;
 if not found or v_sub.status in ('suspended','cancelled') or (v_sub.status='active' and v_sub.valid_until>statement_timestamp() and v_sub.plan_code<>p_plan) then raise exception 'Contact administration to change plan' using errcode='42501';end if;
 select amount into v_amount from bakery_private.billing_prices where plan_code=p_plan and period=p_period and enabled;
 if not found or p_amount is distinct from v_amount or not exists(select 1 from bakery_private.billing_methods where method=p_method and enabled) then raise exception 'Payment option unavailable' using errcode='22023';end if;
 insert into bakery_private.billing_payments(bakery_id,request_id,plan_code,period,method,reference,amount,submitted_by) values(p_bakery,p_request,p_plan,p_period,p_method,v_ref,v_amount,auth.uid()) returning id into v_id;return v_id;
end $$;
create function bakery_private.my_billing_payments(p_bakery uuid) returns table(id uuid,plan_code text,period text,method text,reference text,amount numeric,status text,created_at timestamptz,review_note text,granted_until timestamptz) language plpgsql security definer set search_path='' as $$
begin if bakery_private.team_role(p_bakery)<>'owner' then raise exception 'Owner required' using errcode='42501';end if;
 return query select p.id,p.plan_code,p.period,p.method,p.reference,p.amount,p.status,p.created_at,p.review_note,p.granted_until from bakery_private.billing_payments p where p.bakery_id=p_bakery order by p.created_at desc limit 100;end $$;
create function bakery_private.pending_billing_payments() returns table(id uuid,bakery_name text,plan_code text,period text,method text,reference text,amount numeric,created_at timestamptz) language plpgsql security definer set search_path='' as $$
begin perform bakery_private.require_session();perform bakery_private.assert_platform_admin();
 return query select p.id,b.name,p.plan_code,p.period,p.method,p.reference,p.amount,p.created_at from bakery_private.billing_payments p join public.bakeries b on b.id=p.bakery_id where p.status='pending' order by p.created_at,p.id limit 100;end $$;
create function bakery_private.review_billing_payment(p_payment uuid,p_approve boolean,p_note text) returns void language plpgsql security definer set search_path='' as $$
declare v_pay bakery_private.billing_payments%rowtype;v_sub public.saas_subscriptions%rowtype;v_until timestamptz;v_start timestamptz;v_status text;
begin perform bakery_private.require_session();perform bakery_private.assert_platform_admin();
 if p_approve is null or p_note is null or char_length(btrim(p_note)) not between 1 and 200 then raise exception 'Review note required' using errcode='22023';end if;
 select * into v_pay from bakery_private.billing_payments where id=p_payment;if not found then raise exception 'Unknown payment' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_pay.bakery_id::text,1));
 select * into v_pay from bakery_private.billing_payments where id=p_payment;
 v_status:=case when p_approve then 'approved' else 'rejected' end;
 if v_pay.status<>'pending' then if v_pay.status=v_status then return;end if;raise exception 'Already reviewed' using errcode='23505';end if;
 if p_approve then
 select * into v_sub from public.saas_subscriptions where bakery_id=v_pay.bakery_id;
 if not found or v_sub.status in ('suspended','cancelled') or (v_sub.status='active' and v_sub.valid_until>statement_timestamp() and v_sub.plan_code<>v_pay.plan_code) then raise exception 'Subscription changed; review manually' using errcode='42501';end if;
 v_start:=case when v_sub.status='active' and v_sub.plan_code=v_pay.plan_code then greatest(v_sub.valid_until,statement_timestamp()) else statement_timestamp() end;
 v_until:=((v_start at time zone 'America/Lima')+case when v_pay.period='year' then interval '1 year' else interval '1 month' end) at time zone 'America/Lima';
 perform bakery_private.set_subscription(v_pay.bakery_id,v_pay.plan_code,'active',v_until);
 end if;
 update bakery_private.billing_payments set status=v_status,reviewed_by=auth.uid(),reviewed_at=statement_timestamp(),review_note=btrim(p_note),granted_until=v_until where id=p_payment;
end $$;
create function public.portal_session_status() returns boolean language sql stable security invoker set search_path='' as $$ select bakery_private.session_allowed() $$;
revoke all on function public.portal_session_status() from public,anon,authenticated;
grant execute on function public.portal_session_status() to authenticated;
create function public.register_portal_session(p_label text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.register_portal_session(p_label) $$;
revoke all on function bakery_private.register_portal_session(text),public.register_portal_session(text) from public,anon,authenticated;
grant execute on function bakery_private.register_portal_session(text),public.register_portal_session(text) to authenticated;
create function public.my_portal_sessions() returns table(session_id uuid,label text,started_at timestamptz,revoked_at timestamptz,is_current boolean) language sql security invoker set search_path='' as $$ select * from bakery_private.my_portal_sessions() $$;
revoke all on function bakery_private.my_portal_sessions(),public.my_portal_sessions() from public,anon,authenticated;
grant execute on function bakery_private.my_portal_sessions(),public.my_portal_sessions() to authenticated;
create function public.revoke_portal_session(p_session uuid) returns void language sql security invoker set search_path='' as $$ select bakery_private.revoke_portal_session(p_session) $$;
revoke all on function bakery_private.revoke_portal_session(uuid),public.revoke_portal_session(uuid) from public,anon,authenticated;
grant execute on function bakery_private.revoke_portal_session(uuid),public.revoke_portal_session(uuid) to authenticated;
create function public.invite_worker(p_bakery uuid,p_email text,p_role text) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.invite_worker(p_bakery,p_email,p_role) $$;
revoke all on function bakery_private.invite_worker(uuid,text,text),public.invite_worker(uuid,text,text) from public,anon,authenticated;
grant execute on function bakery_private.invite_worker(uuid,text,text),public.invite_worker(uuid,text,text) to authenticated;
create function public.my_invitations() returns table(id uuid,bakery_name text,role text,expires_at timestamptz) language sql security invoker set search_path='' as $$ select * from bakery_private.my_invitations() $$;
revoke all on function bakery_private.my_invitations(),public.my_invitations() from public,anon,authenticated;
grant execute on function bakery_private.my_invitations(),public.my_invitations() to authenticated;
create function public.accept_invitation(p_invite uuid) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.accept_invitation(p_invite) $$;
revoke all on function bakery_private.accept_invitation(uuid),public.accept_invitation(uuid) from public,anon,authenticated;
grant execute on function bakery_private.accept_invitation(uuid),public.accept_invitation(uuid) to authenticated;
create function public.team_members(p_bakery uuid) returns table(user_id uuid,email text,role text) language sql security invoker set search_path='' as $$ select * from bakery_private.team_members(p_bakery) $$;
revoke all on function bakery_private.team_members(uuid),public.team_members(uuid) from public,anon,authenticated;
grant execute on function bakery_private.team_members(uuid),public.team_members(uuid) to authenticated;
create function public.team_invitations(p_bakery uuid) returns table(id uuid,email text,role text,status text,expires_at timestamptz) language sql security invoker set search_path='' as $$ select * from bakery_private.team_invitations(p_bakery) $$;
revoke all on function bakery_private.team_invitations(uuid),public.team_invitations(uuid) from public,anon,authenticated;
grant execute on function bakery_private.team_invitations(uuid),public.team_invitations(uuid) to authenticated;
create function public.revoke_invitation(p_bakery uuid,p_invite uuid) returns void language sql security invoker set search_path='' as $$ select bakery_private.revoke_invitation(p_bakery,p_invite) $$;
revoke all on function bakery_private.revoke_invitation(uuid,uuid),public.revoke_invitation(uuid,uuid) from public,anon,authenticated;
grant execute on function bakery_private.revoke_invitation(uuid,uuid),public.revoke_invitation(uuid,uuid) to authenticated;
create function public.remove_worker(p_bakery uuid,p_user uuid) returns void language sql security invoker set search_path='' as $$ select bakery_private.remove_worker(p_bakery,p_user) $$;
revoke all on function bakery_private.remove_worker(uuid,uuid),public.remove_worker(uuid,uuid) from public,anon,authenticated;
grant execute on function bakery_private.remove_worker(uuid,uuid),public.remove_worker(uuid,uuid) to authenticated;
create function public.set_billing_price(p_plan text,p_period text,p_amount numeric,p_enabled boolean) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_billing_price(p_plan,p_period,p_amount,p_enabled) $$;
revoke all on function bakery_private.set_billing_price(text,text,numeric,boolean),public.set_billing_price(text,text,numeric,boolean) from public,anon,authenticated;
grant execute on function bakery_private.set_billing_price(text,text,numeric,boolean),public.set_billing_price(text,text,numeric,boolean) to authenticated;
create function public.set_billing_method(p_method text,p_instructions text,p_enabled boolean) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_billing_method(p_method,p_instructions,p_enabled) $$;
revoke all on function bakery_private.set_billing_method(text,text,boolean),public.set_billing_method(text,text,boolean) from public,anon,authenticated;
grant execute on function bakery_private.set_billing_method(text,text,boolean),public.set_billing_method(text,text,boolean) to authenticated;
create function public.billing_options() returns jsonb language sql security invoker set search_path='' as $$ select bakery_private.billing_options() $$;
revoke all on function bakery_private.billing_options(),public.billing_options() from public,anon,authenticated;
grant execute on function bakery_private.billing_options(),public.billing_options() to authenticated;
create function public.submit_billing_payment(p_bakery uuid,p_request uuid,p_plan text,p_period text,p_method text,p_reference text,p_amount numeric) returns uuid language sql security invoker set search_path='' as $$ select bakery_private.submit_billing_payment(p_bakery,p_request,p_plan,p_period,p_method,p_reference,p_amount) $$;
revoke all on function bakery_private.submit_billing_payment(uuid,uuid,text,text,text,text,numeric),public.submit_billing_payment(uuid,uuid,text,text,text,text,numeric) from public,anon,authenticated;
grant execute on function bakery_private.submit_billing_payment(uuid,uuid,text,text,text,text,numeric),public.submit_billing_payment(uuid,uuid,text,text,text,text,numeric) to authenticated;
create function public.my_billing_payments(p_bakery uuid) returns table(id uuid,plan_code text,period text,method text,reference text,amount numeric,status text,created_at timestamptz,review_note text,granted_until timestamptz) language sql security invoker set search_path='' as $$ select * from bakery_private.my_billing_payments(p_bakery) $$;
revoke all on function bakery_private.my_billing_payments(uuid),public.my_billing_payments(uuid) from public,anon,authenticated;
grant execute on function bakery_private.my_billing_payments(uuid),public.my_billing_payments(uuid) to authenticated;
create function public.pending_billing_payments() returns table(id uuid,bakery_name text,plan_code text,period text,method text,reference text,amount numeric,created_at timestamptz) language sql security invoker set search_path='' as $$ select * from bakery_private.pending_billing_payments() $$;
revoke all on function bakery_private.pending_billing_payments(),public.pending_billing_payments() from public,anon,authenticated;
grant execute on function bakery_private.pending_billing_payments(),public.pending_billing_payments() to authenticated;
create function public.review_billing_payment(p_payment uuid,p_approve boolean,p_note text) returns void language sql security invoker set search_path='' as $$ select bakery_private.review_billing_payment(p_payment,p_approve,p_note) $$;
revoke all on function bakery_private.review_billing_payment(uuid,boolean,text),public.review_billing_payment(uuid,boolean,text) from public,anon,authenticated;
grant execute on function bakery_private.review_billing_payment(uuid,boolean,text),public.review_billing_payment(uuid,boolean,text) to authenticated;
create or replace function public.create_initial_bakery(p_name text,p_branch text) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.create_initial_bakery(p_name,p_branch); end $$;
create or replace function public.record_stock_movement(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_request uuid,p_direction text,p_quantity numeric,p_reason text) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.record_stock_movement(p_bakery,p_branch,p_ingredient,p_request,p_direction,p_quantity,p_reason); end $$;
create or replace function public.set_stock_minimum(p_bakery uuid,p_branch uuid,p_ingredient uuid,p_minimum numeric) returns void language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); perform bakery_private.set_stock_minimum(p_bakery,p_branch,p_ingredient,p_minimum); return; end $$;
create or replace function public.create_recipe_version(p_bakery uuid,p_name text,p_yield integer,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.create_recipe_version(p_bakery,p_name,p_yield,p_items); end $$;
create or replace function public.complete_production(p_bakery uuid,p_branch uuid,p_recipe uuid,p_request uuid,p_units integer) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.complete_production(p_bakery,p_branch,p_recipe,p_request,p_units); end $$;
create or replace function public.receive_purchase(p_bakery uuid,p_branch uuid,p_supplier uuid,p_request uuid,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.receive_purchase(p_bakery,p_branch,p_supplier,p_request,p_items); end $$;
create or replace function public.record_sale(p_bakery uuid,p_branch uuid,p_request uuid,p_payment text,p_items jsonb) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.record_sale(p_bakery,p_branch,p_request,p_payment,p_items); end $$;
create or replace function public.open_cash_shift(p_bakery uuid,p_branch uuid,p_request uuid,p_opening numeric) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.open_cash_shift(p_bakery,p_branch,p_request,p_opening); end $$;
create or replace function public.add_cash_entry(p_bakery uuid,p_branch uuid,p_shift uuid,p_request uuid,p_direction text,p_amount numeric,p_reason text) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.add_cash_entry(p_bakery,p_branch,p_shift,p_request,p_direction,p_amount,p_reason); end $$;
create or replace function public.close_cash_shift(p_bakery uuid,p_branch uuid,p_shift uuid,p_counted numeric) returns uuid language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return bakery_private.close_cash_shift(p_bakery,p_branch,p_shift,p_counted); end $$;
create or replace function public.set_recipe_price(p_bakery uuid,p_recipe uuid,p_price numeric) returns void language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); perform bakery_private.set_recipe_price(p_bakery,p_recipe,p_price); return; end $$;
create or replace function public.list_customers() returns table(bakery_id uuid,name text,plan_code text,status text,valid_until timestamptz,active_branches bigint,members bigint) language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); return query select * from bakery_private.list_customers(); end $$;
create or replace function public.set_subscription(p_bakery uuid,p_plan text,p_status text,p_valid_until timestamptz) returns void language plpgsql security invoker set search_path='' as $$ begin perform bakery_private.require_session(); perform bakery_private.set_subscription(p_bakery,p_plan,p_status,p_valid_until); return; end $$;
commit;
