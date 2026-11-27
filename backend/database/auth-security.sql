-- Native Supabase MFA, mandatory for platform admins and users with verified factors.
begin;
create function bakery_private.auth_requirements() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_admin boolean;v_factor boolean;
begin
 if v_user is null or not exists(select 1 from auth.sessions s join auth.users u on u.id=s.user_id where s.user_id=v_user and s.id::text=auth.jwt()->>'session_id' and u.email_confirmed_at is not null and not u.is_anonymous) then raise exception 'Verified Auth session required' using errcode='42501';end if;
 select exists(select 1 from bakery_private.platform_admins where user_id=v_user),exists(select 1 from auth.mfa_factors where user_id=v_user and status='verified') into v_admin,v_factor;
 return jsonb_build_object('platform_admin',v_admin,'has_factor',v_factor,'required',v_admin or v_factor);
end $$;
revoke all on function bakery_private.auth_requirements() from public,anon,authenticated;
grant execute on function bakery_private.auth_requirements() to authenticated;
create function public.auth_requirements() returns jsonb language sql stable security invoker set search_path='' as $$ select bakery_private.auth_requirements() $$;
revoke all on function public.auth_requirements() from public,anon,authenticated;
grant execute on function public.auth_requirements() to authenticated;
create function bakery_private.mfa_access_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and case
 when exists(select 1 from bakery_private.platform_admins where user_id=auth.uid()) then
 coalesce(auth.jwt()->>'aal','aal1')='aal2' and exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified')
 when exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified') then coalesce(auth.jwt()->>'aal','aal1')='aal2'
 else true end
$$;
revoke all on function bakery_private.mfa_access_allowed() from public,anon,authenticated;
create or replace function bakery_private.session_allowed() returns boolean language sql stable security definer set search_path='' as $$
 select bakery_private.mfa_access_allowed() and exists(select 1 from bakery_private.portal_sessions p join auth.sessions s on s.id=p.session_id and s.user_id=p.user_id
 join auth.users u on u.id=p.user_id where p.user_id=auth.uid() and p.session_id::text=auth.jwt()->>'session_id'
 and p.revoked_at is null and u.email_confirmed_at is not null and not u.is_anonymous)
$$;
create or replace function bakery_private.register_portal_session(p_label text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_session uuid; old_row bakery_private.portal_sessions%rowtype;
begin
 if v_user is null or p_label is null or char_length(btrim(p_label)) not between 1 and 80 then raise exception 'Invalid session' using errcode='42501'; end if;
 select s.id into v_session from auth.sessions s join auth.users u on u.id=s.user_id where s.user_id=v_user and s.id::text=auth.jwt()->>'session_id' and u.email_confirmed_at is not null and not u.is_anonymous;
 if not found then raise exception 'Verified Auth session required' using errcode='42501'; end if;
 if not bakery_private.mfa_access_allowed() then raise exception 'Second factor required' using errcode='42501';end if;
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
create or replace function bakery_private.assert_platform_admin() returns void language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or not exists(select 1 from bakery_private.platform_admins a where a.user_id=auth.uid()) or not bakery_private.mfa_access_allowed() or not bakery_private.session_allowed() then
 raise exception 'Platform administration requires verified MFA' using errcode='42501';end if;
end $$;
commit;
