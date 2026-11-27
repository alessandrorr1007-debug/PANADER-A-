-- Draft: apply after tenant-foundation.sql in an isolated test environment.
begin;
create schema bakery_private;
revoke all on schema bakery_private from public, anon, authenticated;
grant usage on schema bakery_private to authenticated;
-- This narrowly scoped definer is necessary to bootstrap the first membership.
-- Keep bakery_private outside PostgREST exposed schemas.
create function bakery_private.create_initial_bakery(p_name text,p_branch text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
 v_user uuid := auth.uid();
 v_bakery uuid;
begin
 if v_user is null or not exists (
  select 1 from auth.users u where u.id=v_user and u.email_confirmed_at is not null and not u.is_anonymous
 ) then raise exception 'Verified account required' using errcode='42501'; end if;
 if p_name is null or p_branch is null or char_length(btrim(p_name)) not between 1 and 120
 or char_length(btrim(p_branch)) not between 1 and 120 then
  raise exception 'Invalid business or branch name' using errcode='22023';
 end if;
 -- Serialize concurrent onboarding calls from the same account.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
 if exists(select 1 from public.bakery_members where user_id=v_user) then
  raise exception 'Account already has a business membership' using errcode='23505';
 end if;
 insert into public.bakeries(name) values (btrim(p_name)) returning id into v_bakery;
 insert into public.bakery_members(bakery_id,user_id,role) values(v_bakery,v_user,'owner');
 insert into public.branches(bakery_id,name) values(v_bakery,btrim(p_branch));
 return v_bakery;
end $$;
revoke all on function bakery_private.create_initial_bakery(text,text) from public, anon, authenticated;
grant execute on function bakery_private.create_initial_bakery(text,text) to authenticated;
create function public.create_initial_bakery(p_name text,p_branch text)
returns uuid language sql security invoker set search_path = '' as $$
 select bakery_private.create_initial_bakery(p_name,p_branch)
$$;
revoke all on function public.create_initial_bakery(text,text) from public, anon, authenticated;
grant execute on function public.create_initial_bakery(text,text) to authenticated;
commit;
