-- Private complimentary subscriptions. Apply after catalog-orders.
begin;
alter table public.saas_subscriptions add column courtesy boolean not null default false, add column courtesy_indefinite boolean not null default false;
create table bakery_private.courtesies(
 email text primary key check(email=lower(btrim(email)) and char_length(email) between 3 and 254),
 bakery_id uuid unique references public.bakeries(id),
 plan_code text not null references public.saas_plans(code),
 status text not null check(status in ('active','suspended','cancelled')),
 valid_until timestamptz check(valid_until is null or isfinite(valid_until)),
 created_at timestamptz not null default statement_timestamp(),
 updated_at timestamptz not null default statement_timestamp(),
 updated_by uuid not null
);
create table bakery_private.courtesy_events(
 id uuid primary key default gen_random_uuid(),email text not null references bakery_private.courtesies(email),actor_id uuid not null,
 previous jsonb,current_state jsonb not null,created_at timestamptz not null default statement_timestamp()
);
alter table bakery_private.courtesies enable row level security;
alter table bakery_private.courtesy_events enable row level security;
revoke all on bakery_private.courtesies,bakery_private.courtesy_events from public,anon,authenticated;
-- A finite sentinel preserves existing date checks and API serialization. Null is the real indefinite term.
create function bakery_private.courtesy_deadline(p_until timestamptz) returns timestamptz language sql immutable set search_path='' as $$
 select coalesce(p_until,'9999-12-31 00:00:00+00'::timestamptz)
$$;
revoke all on function bakery_private.courtesy_deadline(timestamptz) from public,anon,authenticated;
create function bakery_private.guard_courtesy_subscription() returns trigger language plpgsql security definer set search_path='' as $$
declare c bakery_private.courtesies%rowtype;
begin
 select * into c from bakery_private.courtesies where bakery_id=new.bakery_id and status<>'cancelled';
 if found then
  if new.plan_code is distinct from c.plan_code or new.status is distinct from c.status or new.valid_until is distinct from bakery_private.courtesy_deadline(c.valid_until) then raise exception 'Manage this subscription in Courtesies' using errcode='42501'; end if;
  new.courtesy:=true;new.courtesy_indefinite:=c.valid_until is null;
 else new.courtesy:=false;new.courtesy_indefinite:=false;end if;
 return new;
end $$;
revoke all on function bakery_private.guard_courtesy_subscription() from public,anon,authenticated;
create trigger courtesy_subscription_guard before update on public.saas_subscriptions for each row execute function bakery_private.guard_courtesy_subscription();
create function bakery_private.guard_courtesy_payment() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from bakery_private.courtesies where bakery_id=new.bakery_id and status<>'cancelled') then raise exception 'Courtesy does not require payment' using errcode='42501';end if;
 return new;
end $$;
revoke all on function bakery_private.guard_courtesy_payment() from public,anon,authenticated;
create trigger courtesy_payment_guard before insert on bakery_private.billing_payments for each row execute function bakery_private.guard_courtesy_payment();
create function bakery_private.apply_courtesy(p_email text) returns void language plpgsql security definer set search_path='' as $$
declare c bakery_private.courtesies%rowtype;v_old public.saas_subscriptions%rowtype;v_new public.saas_subscriptions%rowtype;
begin
 select * into strict c from bakery_private.courtesies where email=p_email;
 if c.bakery_id is null then return;end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(c.bakery_id::text,1));
 select * into strict v_old from public.saas_subscriptions where bakery_id=c.bakery_id for update;
 update public.saas_subscriptions set plan_code=c.plan_code,status=c.status,valid_until=bakery_private.courtesy_deadline(c.valid_until),updated_at=statement_timestamp() where bakery_id=c.bakery_id returning * into v_new;
 insert into bakery_private.subscription_events(bakery_id,actor_id,previous,current_state) values(c.bakery_id,c.updated_by,to_jsonb(v_old),to_jsonb(v_new));
end $$;
revoke all on function bakery_private.apply_courtesy(text) from public,anon,authenticated;
create function bakery_private.set_courtesy(p_email text,p_plan text,p_until timestamptz,p_status text,p_create boolean) returns void language plpgsql security definer set search_path='' as $$
declare e text:=lower(btrim(p_email));c bakery_private.courtesies%rowtype;n bakery_private.courtesies%rowtype;u uuid;b uuid;s public.saas_subscriptions%rowtype;
begin
 perform bakery_private.assert_platform_admin();
 if e is null or char_length(e)>254 or e !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or p_create is null or p_status is null or p_status not in ('active','suspended','cancelled') or (p_create and p_status<>'active') or not exists(select 1 from public.saas_plans where code=p_plan) or (p_until is not null and (not isfinite(p_until) or p_until>='9999-12-31 00:00:00+00'::timestamptz)) or (p_status='active' and p_until<=statement_timestamp()) then raise exception 'Invalid courtesy' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(e,19));
 select * into c from bakery_private.courtesies where email=e for update;
 if p_create and found then raise exception 'Courtesy already exists' using errcode='23505';end if;
 if not p_create and not found then raise exception 'Unknown courtesy' using errcode='22023';end if;
 if c.status='cancelled' then raise exception 'Cancelled courtesy is final' using errcode='22023';end if;
 b:=c.bakery_id;
 if b is null and p_status='active' then
  if (select count(*) from auth.users where lower(btrim(email))=e and email_confirmed_at is not null and not is_anonymous)>1 then raise exception 'Ambiguous email' using errcode='22023';end if;
  select id into u from auth.users where lower(btrim(email))=e and email_confirmed_at is not null and not is_anonymous;
  if u is not null then
   if exists(select 1 from bakery_private.platform_admins where user_id=u) then raise exception 'Platform admin does not need a subscription' using errcode='22023';end if;
   if (select count(*) from public.bakery_members where user_id=u and role='owner')>1 then raise exception 'Ambiguous business' using errcode='22023';end if;
   select bakery_id into b from public.bakery_members where user_id=u and role='owner';
   if b is null and exists(select 1 from public.bakery_members where user_id=u) then raise exception 'Employee does not own a business' using errcode='22023';end if;
  end if;
 end if;
 if b is not null then
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(b::text,1));
  select * into strict s from public.saas_subscriptions where bakery_id=b for update;
  if c.bakery_id is null and (s.status='active' and s.valid_until>statement_timestamp() or exists(select 1 from bakery_private.billing_payments where bakery_id=b and status='pending')) then raise exception 'Existing active subscription or pending payment' using errcode='42501';end if;
 end if;
 insert into bakery_private.courtesies(email,bakery_id,plan_code,status,valid_until,updated_by) values(e,b,p_plan,p_status,p_until,auth.uid())
 on conflict(email) do update set bakery_id=excluded.bakery_id,plan_code=excluded.plan_code,status=excluded.status,valid_until=excluded.valid_until,updated_by=excluded.updated_by,updated_at=statement_timestamp() returning * into n;
 perform bakery_private.apply_courtesy(e);
 insert into bakery_private.courtesy_events(email,actor_id,previous,current_state) values(e,auth.uid(),case when c.email is null then null else to_jsonb(c) end,to_jsonb(n));
end $$;
create function bakery_private.list_courtesies() returns table(email text,bakery_id uuid,bakery_name text,plan_code text,status text,valid_until timestamptz,updated_at timestamptz) language plpgsql security definer set search_path='' as $$
begin perform bakery_private.assert_platform_admin();return query select c.email,c.bakery_id,b.name,c.plan_code,c.status,c.valid_until,c.updated_at from bakery_private.courtesies c left join public.bakeries b on b.id=c.bakery_id order by c.email;end $$;
create function bakery_private.my_pending_courtesy() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare e text;v jsonb;begin perform bakery_private.require_session();select lower(btrim(email)) into e from auth.users where id=auth.uid() and email_confirmed_at is not null and not is_anonymous;
 select jsonb_build_object('plan_code',c.plan_code,'valid_until',c.valid_until) into v from bakery_private.courtesies c where c.email=e and c.bakery_id is null and c.status='active' and (c.valid_until is null or c.valid_until>statement_timestamp());return v;end $$;
create function public.set_courtesy(p_email text,p_plan text,p_until timestamptz,p_status text,p_create boolean) returns void language sql security invoker set search_path='' as $$ select bakery_private.set_courtesy(p_email,p_plan,p_until,p_status,p_create) $$;
create function public.list_courtesies() returns table(email text,bakery_id uuid,bakery_name text,plan_code text,status text,valid_until timestamptz,updated_at timestamptz) language sql security invoker set search_path='' as $$ select * from bakery_private.list_courtesies() $$;
create function public.my_pending_courtesy() returns jsonb language sql security invoker set search_path='' as $$ select bakery_private.my_pending_courtesy() $$;
revoke all on function bakery_private.set_courtesy(text,text,timestamptz,text,boolean),bakery_private.list_courtesies(),bakery_private.my_pending_courtesy(),public.set_courtesy(text,text,timestamptz,text,boolean),public.list_courtesies(),public.my_pending_courtesy() from public,anon,authenticated;
grant execute on function bakery_private.set_courtesy(text,text,timestamptz,text,boolean),bakery_private.list_courtesies(),bakery_private.my_pending_courtesy(),public.set_courtesy(text,text,timestamptz,text,boolean),public.list_courtesies(),public.my_pending_courtesy() to authenticated;
create or replace function bakery_private.create_initial_bakery(p_name text,p_branch text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_email text;v_bakery uuid;v_claimed boolean;
begin
 perform bakery_private.require_session();
 select u.email into v_email from auth.users u where u.id=v_user and u.email_confirmed_at is not null and not u.is_anonymous;
 if not found or nullif(btrim(v_email),'') is null then raise exception 'Verified email required' using errcode='42501';end if;
 if p_name is null or p_branch is null or char_length(btrim(p_name)) not between 1 and 120 or char_length(btrim(p_branch)) not between 1 and 120 then raise exception 'Invalid business or branch name' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(lower(btrim(v_email)),19));
 if exists(select 1 from public.bakery_members where user_id=v_user) then raise exception 'Account already has a business membership' using errcode='23505';end if;
 -- Unique keys serialize concurrent claims, including separate Auth accounts sharing a normalized address.
 insert into bakery_private.trial_claims(email_fingerprint,original_user_id) values(bakery_private.trial_fingerprint(v_email),v_user) on conflict do nothing;
 v_claimed:=found;
 insert into public.bakeries(name) values(btrim(p_name)) returning id into v_bakery;
 -- Existing provisioning trigger enables a trial within this transaction to bootstrap membership/branch.
 insert into public.bakery_members(bakery_id,user_id,role) values(v_bakery,v_user,'owner');
 insert into public.branches(bakery_id,name) values(v_bakery,btrim(p_branch));
 if not v_claimed then
  -- Expire before commit: no other transaction sees a new usable trial. Owner can still submit a paid renewal.
  update public.saas_subscriptions set valid_until=statement_timestamp(),updated_at=statement_timestamp() where bakery_id=v_bakery;
 end if;
 update bakery_private.courtesies set bakery_id=v_bakery,updated_at=statement_timestamp() where email=lower(btrim(v_email)) and bakery_id is null and status='active' and (valid_until is null or valid_until>statement_timestamp());
 if found then perform bakery_private.apply_courtesy(lower(btrim(v_email))); end if;
 return v_bakery;
end $$;

commit;
