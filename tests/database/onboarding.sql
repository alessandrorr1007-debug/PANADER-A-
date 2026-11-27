begin;
insert into auth.users(id,email_confirmed_at,is_anonymous) values
 ('00000000-0000-4000-8000-000000000011',now(),false),
 ('00000000-0000-4000-8000-000000000012',null,false),
 ('00000000-0000-4000-8000-000000000013',now(),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
do $$ declare id uuid; begin
 begin perform public.create_initial_bakery('','Centro'); raise exception 'invalid accepted'; exception when invalid_parameter_value then null; end;
 id:=public.create_initial_bakery(' Aurora ',' Centro ');
 if not exists(select 1 from public.bakeries b where b.id=id and name='Aurora') then raise exception 'missing bakery'; end if;
 if not exists(select 1 from public.bakery_members m where m.bakery_id=id and role='owner' and user_id=auth.uid()) then raise exception 'missing owner'; end if;
 if not exists(select 1 from public.branches b where b.bakery_id=id and name='Centro') then raise exception 'missing branch'; end if;
 begin perform public.create_initial_bakery('Otro','Centro'); raise exception 'duplicate accepted'; exception when unique_violation then null; end;
 if (select count(*) from public.bakeries)<>1 then raise exception 'duplicate business'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000012',true);
do $$ begin
 if exists(select 1 from public.bakeries) then raise exception 'cross-tenant read'; end if;
 begin perform public.create_initial_bakery('Otro','Centro'); raise exception 'unverified accepted'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000013',true);
do $$ begin
 begin perform public.create_initial_bakery('Otro','Centro'); raise exception 'anonymous user accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.create_initial_bakery('Otro','Centro'); raise exception 'anonymous role accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
