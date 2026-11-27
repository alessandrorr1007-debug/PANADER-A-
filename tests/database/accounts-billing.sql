begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('00000000-0000-4000-8000-000000000001','owner@example.test',now()),
 ('00000000-0000-4000-8000-000000000002','worker@example.test',now()),
 ('00000000-0000-4000-8000-000000000003','platform@example.test',now()),
 ('00000000-0000-4000-8000-000000000004','outsider@example.test',now()),
 ('00000000-0000-4000-8000-000000000005','other@example.test',now());
insert into auth.sessions(id,user_id) values
 ('30000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001'),
 ('30000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002'),
 ('30000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000003'),
 ('30000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-000000000004'),
 ('30000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000001');
insert into bakery_private.platform_admins values('00000000-0000-4000-8000-000000000003');
insert into public.bakeries(id,name) values('10000000-0000-4000-8000-000000000001','A'),('10000000-0000-4000-8000-000000000002','B');
insert into public.bakery_members(bakery_id,user_id,role) values('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','owner'),('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000004','owner');
insert into public.branches(id,bakery_id,name) values('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Main');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000002',true);
do $$ begin
 if public.portal_session_status() then raise exception 'unregistered status';end if;
 begin perform public.register_portal_session('spoof');raise exception 'session spoof accepted';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.bakeries) then raise exception 'unregistered read';end if;
 begin perform public.open_cash_shift('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',0);raise exception 'unregistered write';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000001',true);
select public.register_portal_session('Caja');
do $$ declare v_inv uuid;begin
 if not public.portal_session_status() or (select count(*) from public.bakeries)<>1 then raise exception 'registered read';end if;
 v_inv:=public.invite_worker('10000000-0000-4000-8000-000000000001','WORKER@EXAMPLE.TEST','operator');
 perform set_config('test.invite',v_inv::text,true);
 perform public.invite_worker('10000000-0000-4000-8000-000000000001','other@example.test','viewer');
 begin perform public.invite_worker('10000000-0000-4000-8000-000000000001','extra@example.test','viewer');raise exception 'quota bypass';exception when check_violation then null;end;
 begin perform public.invite_worker('10000000-0000-4000-8000-000000000002','extra@example.test','viewer');raise exception 'cross tenant invite';exception when insufficient_privilege then null;end;
 begin perform public.set_billing_price('starter','month',29,true);raise exception 'self price';exception when insufficient_privilege then null;end;
 if (select jsonb_array_length(public.billing_options()->'prices'))<>0 then raise exception 'prices enabled by default';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000004',true);
select public.register_portal_session('Otro negocio');
do $$ begin
 if exists(select 1 from public.my_invitations()) then raise exception 'invite leak';end if;
 begin perform public.accept_invitation(current_setting('test.invite')::uuid);raise exception 'wrong email accepted';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000002',true);
select public.register_portal_session('Producción');
do $$ begin
 if (select count(*) from public.my_invitations())<>1 then raise exception 'invite not found';end if;
 perform public.accept_invitation(current_setting('test.invite')::uuid);
 perform public.accept_invitation(current_setting('test.invite')::uuid);
 if (select role from public.bakery_members)<>'operator' then raise exception 'wrong role';end if;
 begin perform public.invite_worker('10000000-0000-4000-8000-000000000001','extra@example.test','admin');raise exception 'operator invite';exception when insufficient_privilege then null;end;
 begin perform public.submit_billing_payment('10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','starter','month','yape','ABCD',29);raise exception 'operator payment';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000003',true);
select public.register_portal_session('Admin');
select public.set_billing_price('starter','month',29,true);
select public.set_billing_method('yape','Fixture only',true);
do $$ begin if exists(select 1 from public.bakeries) or (select count(*) from public.list_customers())<>2 then raise exception 'platform isolation';end if;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000005',true);
select public.register_portal_session('Nuevo equipo');
do $$ declare p uuid;begin
 if not public.portal_session_status() or (select count(*) from public.my_portal_sessions())<>2 then raise exception 'session history';end if;
 begin perform public.submit_billing_payment('10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','starter','month','yape','ABCD',1);raise exception 'tampered amount';exception when invalid_parameter_value then null;end;
 p:=public.submit_billing_payment('10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','starter','month','yape','ABCD',29);
 if p<>public.submit_billing_payment('10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','starter','month','yape','ABCD',29) then raise exception 'payment retry';end if;
 perform set_config('test.payment',p::text,true);
 if (select status from public.saas_subscriptions)<>'trial' then raise exception 'self activation';end if;
 begin perform public.review_billing_payment(p,true,'fake');raise exception 'self review';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000001',true);
do $$ begin
 if public.portal_session_status() or exists(select 1 from public.bakeries) then raise exception 'revoked read';end if;
 begin perform public.register_portal_session('Old');raise exception 'revoked reclaim';exception when insufficient_privilege then null;end;
 begin perform public.open_cash_shift('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',0);raise exception 'revoked write';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000003',true);
select public.review_billing_payment(current_setting('test.payment')::uuid,true,'Verified test fixture');
select public.review_billing_payment(current_setting('test.payment')::uuid,true,'Retry');
reset role;
do $$ begin
 if (select count(*) from bakery_private.subscription_events where bakery_id='10000000-0000-4000-8000-000000000001')<>1 then raise exception 'double activation';end if;
 if not exists(select 1 from public.saas_subscriptions s join bakery_private.billing_payments p using(bakery_id) where s.status='active' and p.status='approved' and s.valid_until=p.granted_until and s.valid_until>now()+interval '27 days') then raise exception 'payment not activated';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000004',true);
do $$ begin
 begin perform public.submit_billing_payment('10000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003','starter','month','yape','ABCD',29);raise exception 'duplicate bank ref';exception when unique_violation then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000005',true);
select public.remove_worker('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claim.session_id','30000000-0000-4000-8000-000000000002',true);
do $$ begin if exists(select 1 from public.bakeries) then raise exception 'removed worker read';end if;end $$;
rollback;
