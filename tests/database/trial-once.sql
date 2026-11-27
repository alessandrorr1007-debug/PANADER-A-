begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001','trial@example.test',now()),
 ('00000000-0000-4000-8000-000000000002','worker@example.test',now()),
 ('00000000-0000-4000-8000-000000000003','platform@example.test',now());
insert into auth.sessions(id,user_id) values
 ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001'),
 ('30000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002'),
 ('30000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000003');
insert into bakery_private.platform_admins values('00000000-0000-4000-8000-000000000003');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000001',true);
do $$ begin
 begin perform public.trial_eligible();raise exception 'unregistered eligibility';exception when insufficient_privilege then null;end;
end $$;
select public.register_portal_session('Trial fixture');
do $$ declare b uuid;i uuid;begin
 if not public.trial_eligible() then raise exception 'new email denied';end if;
 begin perform public.create_initial_bakery('','Principal');raise exception 'invalid name accepted';exception when invalid_parameter_value then null;end;
 if not public.trial_eligible() then raise exception 'failed onboarding burned trial';end if;
 b:=public.create_initial_bakery('First bakery','Principal');
 if public.trial_eligible() then raise exception 'trial claim missing';end if;
 if not exists(select 1 from public.saas_subscriptions where bakery_id=b and status='trial' and valid_until>statement_timestamp()+interval '13 days') then raise exception 'first trial missing';end if;
 begin perform public.create_initial_bakery('Another bakery','Principal');raise exception 'second business';exception when unique_violation then null;end;
 i:=public.invite_worker(b,'worker@example.test','operator');
 perform set_config('test.invite',i::text,true);
 perform set_config('test.first_bakery',b::text,true);
 begin perform * from bakery_private.trial_claims;raise exception 'trial claims exposed';exception when insufficient_privilege then null;end;
 begin perform * from bakery_private.trial_secret;raise exception 'secret exposed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000002',true);
select public.register_portal_session('Worker');
select public.accept_invitation(current_setting('test.invite')::uuid);
do $$ begin
 if not public.trial_eligible() then raise exception 'invitation consumed trial';end if;
 begin perform public.create_initial_bakery('Worker duplicate','Main');raise exception 'member created separate trial';exception when unique_violation then null;end;
end $$;
reset role;
-- Delete original identity, then register another account with the same normalized email.
delete from auth.sessions where user_id='00000000-0000-4000-8000-000000000001';
delete from auth.users where id='00000000-0000-4000-8000-000000000001';
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-4000-8000-000000000004','TRIAL@EXAMPLE.TEST',now());
insert into auth.sessions(id,user_id) values('30000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000004');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000004',true);
select public.register_portal_session('Second device');
do $$ declare b uuid;begin
 if public.trial_eligible() then raise exception 'repeat email eligible';end if;
 b:=public.create_initial_bakery('Paid-only bakery','Principal');
 if not exists(select 1 from public.saas_subscriptions where bakery_id=b and valid_until<=statement_timestamp()) then raise exception 'repeat trial granted';end if;
 if (select count(*) from public.branches)<>1 then raise exception 'paid onboarding missing branch';end if;
 begin insert into public.ingredients(bakery_id,name,unit) values(b,'Harina','kg');raise exception 'expired trial write';exception when insufficient_privilege then null;end;
 perform set_config('test.second_bakery',b::text,true);
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000003',true);
select public.register_portal_session('Platform');
do $$ begin
 begin perform public.set_subscription(current_setting('test.second_bakery')::uuid,'starter','trial',now()+interval '14 days');raise exception 'trial reset';exception when invalid_parameter_value then null;end;
 perform public.set_billing_price('starter','month',29,true);
 perform public.set_billing_method('yape','Test only',true);
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000004',true);
select set_config('test.payment',public.submit_billing_payment(current_setting('test.second_bakery')::uuid,'40000000-0000-4000-8000-000000000001','starter','month','yape','TRIALTEST',29)::text,true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000003',true);
select public.review_billing_payment(current_setting('test.payment')::uuid,true,'Verified fixture');
reset role;
do $$ begin
 if (select count(*) from bakery_private.trial_claims)<>1 then raise exception 'unexpected claim count';end if;
 if not exists(select 1 from public.saas_subscriptions where bakery_id=current_setting('test.second_bakery')::uuid and status='active' and valid_until>now()) then raise exception 'paid activation blocked';end if;
end $$;
rollback;
