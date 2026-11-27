begin;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-4000-8000-000000000001','admin@example.test',now()),
('00000000-0000-4000-8000-000000000002','worker@example.test',now()),
('00000000-0000-4000-8000-000000000003','ordinary@example.test',now());
insert into auth.sessions(id,user_id) values
('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001'),
('30000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002'),
('30000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000003');
insert into bakery_private.platform_admins values('00000000-0000-4000-8000-000000000001');
insert into auth.mfa_factors(id,user_id,status) values('50000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','verified'),('50000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','verified');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.aal','aal1',true);
do $$ begin
 if public.auth_requirements()->>'required'<>'true' then raise exception 'admin MFA flag';end if;
 begin perform public.register_portal_session('Admin');raise exception 'aal1 admin registration';exception when insufficient_privilege then null;end;
 begin perform * from public.list_customers();raise exception 'aal1 admin list';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.aal','aal2',true);
select public.register_portal_session('Admin');
do $$ begin if not public.portal_session_status() then raise exception 'aal2 denied';end if;perform * from public.list_customers();end $$;
select set_config('request.jwt.claim.aal','aal1',true);
do $$ begin if public.portal_session_status() then raise exception 'downgrade accepted';end if;
 begin perform public.set_billing_price('starter','month',29,true);raise exception 'admin price bypass';exception when insufficient_privilege then null;end;end $;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000002',true);
do $$ begin
 if public.auth_requirements()->>'has_factor'<>'true' then raise exception 'factor flag';end if;
 begin perform public.register_portal_session('Worker');raise exception 'aal1 enrolled user';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.aal','aal2',true);
select public.register_portal_session('Worker');
select public.create_initial_bakery('Test bakery','Main');
select set_config('request.jwt.claim.aal','aal1',true);
do $$ begin
 if exists(select 1 from public.bakeries) then raise exception 'aal1 data read';end if;
 begin perform public.trial_eligible();raise exception 'aal1 RPC access';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000003',true);
do $$ begin if public.auth_requirements()->>'required'<>'false' then raise exception 'optional MFA';end if;end $$;
select public.register_portal_session('Ordinary');
do $$ begin if not public.portal_session_status() then raise exception 'ordinary denied';end if;
 begin perform * from public.list_customers();raise exception 'ordinary admin';exception when insufficient_privilege then null;end;
end $$;
rollback;
