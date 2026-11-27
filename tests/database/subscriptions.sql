begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002'),('00000000-0000-4000-8000-000000000003'),('00000000-0000-4000-8000-000000000004'),('00000000-0000-4000-8000-000000000005');
insert into bakery_private.platform_admins(user_id) values('00000000-0000-4000-8000-000000000003');
insert into public.bakeries(id,name) values ('10000000-0000-4000-8000-000000000001','A'),('10000000-0000-4000-8000-000000000002','B');
insert into public.bakery_members(bakery_id,user_id,role) values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','owner'),('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','operator'),('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000005','viewer'),('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','owner');
insert into public.branches(id,bakery_id,name) values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Centro'),('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Centro');
do $$ begin
 begin insert into public.bakery_members(bakery_id,user_id,role) values('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','viewer'); raise exception 'member quota bypass'; exception when check_violation then null; end;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ begin
 if (select count(*) from public.saas_subscriptions)<>1 or (select status from public.saas_subscriptions)<>'trial' then raise exception 'trial or tenant scope'; end if;
 if (select valid_until from public.saas_subscriptions)<statement_timestamp()+interval '13 days' then raise exception 'trial duration'; end if;
 begin insert into public.branches(bakery_id,name) values('10000000-0000-4000-8000-000000000001','Sur'); raise exception 'branch quota bypass'; exception when check_violation then null; end;
 begin update public.saas_subscriptions set status='active'; raise exception 'self upgrade'; exception when insufficient_privilege then null; end;
 begin perform * from public.list_customers(); raise exception 'admin escalation'; exception when insufficient_privilege then null; end;
 begin perform public.set_subscription('10000000-0000-4000-8000-000000000001','growth','active',now()+interval '30 days'); raise exception 'self upgrade rpc'; exception when insufficient_privilege then null; end;
 insert into public.ingredients(bakery_id,name,unit) values('10000000-0000-4000-8000-000000000001','Harina','kg');
 perform public.open_cash_shift('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',10);
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
do $$ begin
 if (select count(*) from public.list_customers())<>2 then raise exception 'admin list'; end if;
 if exists(select 1 from public.ingredients) then raise exception 'admin operational access'; end if;
 perform public.set_subscription('10000000-0000-4000-8000-000000000001','growth','active',now()+interval '30 days');
 perform public.set_subscription('10000000-0000-4000-8000-000000000001','growth','active',now()+interval '30 days');
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
insert into public.branches(bakery_id,name) values('10000000-0000-4000-8000-000000000001','Sur'),('10000000-0000-4000-8000-000000000001','Norte');
do $$ begin
 begin insert into public.branches(bakery_id,name) values('10000000-0000-4000-8000-000000000001','Este'); raise exception 'growth limit'; exception when check_violation then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
select public.set_subscription('10000000-0000-4000-8000-000000000001','starter','suspended',now()+interval '30 days');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ declare v_shift uuid; v_ing uuid; begin
 if (select count(*) from public.branches)<>3 then raise exception 'historical read'; end if;
 select id into v_ing from public.ingredients;
 begin update public.ingredients set name='Otro'; raise exception 'suspended edit'; exception when insufficient_privilege then null; end;
 begin perform public.record_stock_movement('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_ing,'40000000-0000-4000-8000-000000000002','in',1,'Compra'); raise exception 'suspended movement'; exception when insufficient_privilege then null; end;
 select id into v_shift from public.cash_shifts;
 perform public.close_cash_shift('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_shift,10);
 update public.branches set active=false where name='Sur';
 begin update public.branches set active=true where name='Sur'; raise exception 'suspended activation'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.saas_subscriptions set status='active',valid_until=now()-interval '1 second' where bakery_id='10000000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$ begin
 begin insert into public.ingredients(bakery_id,name,unit) values('10000000-0000-4000-8000-000000000002','Harina','kg'); raise exception 'expired write'; exception when insufficient_privilege then null; end;
end $$;
reset role;
do $$ begin
 if (select count(*) from bakery_private.subscription_events where bakery_id='10000000-0000-4000-8000-000000000001')<>2 then raise exception 'audit or duplicate event'; end if;
end $$;
rollback;
