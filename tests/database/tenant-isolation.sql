-- Run as database administrator in a disposable database. All fixture changes roll back.
begin;
insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003'),
 ('00000000-0000-4000-8000-000000000004'),
 ('00000000-0000-4000-8000-000000000005');
insert into public.bakeries(id,name) values
 ('10000000-0000-4000-8000-000000000001','Aurora'),
 ('10000000-0000-4000-8000-000000000002','Trigal');
insert into public.bakery_members(bakery_id,user_id,role) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','owner'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','owner'),
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','viewer'),
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','admin'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000004','operator');
insert into public.branches(id,bakery_id,name) values
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Centro'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Norte');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ declare n integer; begin
 if (select count(*) from public.bakeries)<>1 then raise exception 'owner bakery scope'; end if;
 if (select count(*) from public.bakery_members)<>1 then raise exception 'membership scope'; end if;
 if (select count(*) from public.branches)<>1 then raise exception 'branch scope'; end if;
 insert into public.branches(bakery_id,name) values ('10000000-0000-4000-8000-000000000001','Sur');
 begin
  insert into public.branches(bakery_id,name) values ('10000000-0000-4000-8000-000000000002','Intrusion');
  raise exception 'cross-tenant insert accepted';
 exception when insufficient_privilege then null; end;
 update public.branches set name='Centro nuevo' where id='20000000-0000-4000-8000-000000000001';
 get diagnostics n=row_count; if n<>1 then raise exception 'own update denied'; end if;
 update public.branches set name='Intrusion' where id='20000000-0000-4000-8000-000000000002';
 get diagnostics n=row_count; if n<>0 then raise exception 'cross-tenant update accepted'; end if;
 begin
  update public.branches set bakery_id='10000000-0000-4000-8000-000000000002' where id='20000000-0000-4000-8000-000000000001';
  raise exception 'tenant reassignment accepted';
 exception when insufficient_privilege then null; end;
 begin
  insert into public.bakery_members(bakery_id,user_id,role) values ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001','owner');
  raise exception 'self-grant accepted';
 exception when insufficient_privilege then null; end;
 begin
  delete from public.branches where id='20000000-0000-4000-8000-000000000001';
  raise exception 'branch delete accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
do $$ declare n integer; begin
 if (select count(*) from public.branches)<>2 then raise exception 'viewer read scope'; end if;
 update public.branches set name='Intrusion' where id='20000000-0000-4000-8000-000000000001';
 get diagnostics n=row_count; if n<>0 then raise exception 'viewer write accepted'; end if;
 begin
  insert into public.branches(bakery_id,name) values ('10000000-0000-4000-8000-000000000001','Intrusion');
  raise exception 'viewer insert accepted';
 exception when insufficient_privilege then null; end;
 begin
  update public.bakery_members set role='owner';
  raise exception 'privilege escalation accepted';
 exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
do $$ declare n integer; begin
 if (select count(*) from public.bakeries)<>2 then raise exception 'multi-membership denied'; end if;
 update public.branches set name='Centro admin' where id='20000000-0000-4000-8000-000000000001';
 get diagnostics n=row_count; if n<>1 then raise exception 'admin write denied'; end if;
 update public.branches set name='Intrusion' where id='20000000-0000-4000-8000-000000000002';
 get diagnostics n=row_count; if n<>0 then raise exception 'operator write accepted'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000005',true);
do $$ begin
 if exists(select 1 from public.bakeries) or exists(select 1 from public.branches) or exists(select 1 from public.bakery_members) then raise exception 'outsider read accepted'; end if;
end $$;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 if exists(select 1 from public.bakeries) then raise exception 'missing identity accepted'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin
  perform count(*) from public.bakeries;
  raise exception 'anonymous access accepted';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
