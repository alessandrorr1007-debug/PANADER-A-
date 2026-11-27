-- One automatic trial per verified email and per Auth identity.
-- Apply after accounts-billing.sql. Keep bakery_private outside Data API.
begin;
create table bakery_private.trial_secret(
 singleton boolean primary key default true check(singleton),
 secret text not null
);
insert into bakery_private.trial_secret(secret) values(gen_random_uuid()::text||gen_random_uuid()::text);
create table bakery_private.trial_claims(
 email_fingerprint bytea primary key check(octet_length(email_fingerprint)=32),
 original_user_id uuid not null unique,
 claimed_at timestamptz not null default statement_timestamp()
);
-- No FK to auth.users: deleting an account must not erase the trial claim.
alter table bakery_private.trial_secret enable row level security;
alter table bakery_private.trial_claims enable row level security;
revoke all on bakery_private.trial_secret,bakery_private.trial_claims from public,anon,authenticated;
create function bakery_private.trial_fingerprint(p_email text) returns bytea
language sql stable security invoker set search_path='' as $$
 select pg_catalog.sha256(pg_catalog.convert_to(s.secret||':'||lower(btrim(p_email)),'UTF8'))
 from bakery_private.trial_secret s where s.singleton
$$;
revoke all on function bakery_private.trial_fingerprint(text) from public,anon,authenticated;
-- Reserve historical owners' claims (if any). Cannot reconstruct accounts erased before deployment.
insert into bakery_private.trial_claims(email_fingerprint,original_user_id,claimed_at)
 select bakery_private.trial_fingerprint(u.email),u.id,m.created_at
 from public.bakery_members m join auth.users u on u.id=m.user_id
 where m.role='owner' and u.email_confirmed_at is not null and not u.is_anonymous and nullif(btrim(u.email),'') is not null
 order by m.created_at,m.user_id on conflict do nothing;

create function bakery_private.trial_eligible() returns boolean
language plpgsql stable security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_email text;
begin
 perform bakery_private.require_session();
 select u.email into v_email from auth.users u where u.id=v_user and u.email_confirmed_at is not null and not u.is_anonymous;
 if not found or nullif(btrim(v_email),'') is null then raise exception 'Verified email required' using errcode='42501';end if;
 return not exists(select 1 from bakery_private.trial_claims c where c.original_user_id=v_user or c.email_fingerprint=bakery_private.trial_fingerprint(v_email));
end $$;
create function public.trial_eligible() returns boolean language sql stable security invoker set search_path='' as $$
 select bakery_private.trial_eligible()
$$;
revoke all on function bakery_private.trial_eligible(),public.trial_eligible() from public,anon,authenticated;
grant execute on function bakery_private.trial_eligible(),public.trial_eligible() to authenticated;

create or replace function bakery_private.create_initial_bakery(p_name text,p_branch text)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_email text;v_bakery uuid;v_claimed boolean;
begin
 perform bakery_private.require_session();
 select u.email into v_email from auth.users u where u.id=v_user and u.email_confirmed_at is not null and not u.is_anonymous;
 if not found or nullif(btrim(v_email),'') is null then raise exception 'Verified email required' using errcode='42501';end if;
 if p_name is null or p_branch is null or char_length(btrim(p_name)) not between 1 and 120 or char_length(btrim(p_branch)) not between 1 and 120 then raise exception 'Invalid business or branch name' using errcode='22023';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
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
 return v_bakery;
end $$;
-- Do not let an administrative trial-state edit reset a trial. Paid/explicit active grants remain available.
create function bakery_private.prevent_trial_reset() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.status='trial' and (old.status<>'trial' or new.valid_until>old.valid_until) then
  raise exception 'Trial cannot be restarted or extended' using errcode='22023';
 end if;return new;
end $$;
revoke all on function bakery_private.prevent_trial_reset() from public,anon,authenticated;
create trigger prevent_trial_reset before update on public.saas_subscriptions for each row execute function bakery_private.prevent_trial_reset();
commit;
