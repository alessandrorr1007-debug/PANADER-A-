begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002'),('00000000-0000-4000-8000-000000000003'),('00000000-0000-4000-8000-000000000004');
insert into public.bakeries(id,name) values ('10000000-0000-4000-8000-000000000001','A'),('10000000-0000-4000-8000-000000000002','B');
insert into public.bakery_members(bakery_id,user_id,role) values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','owner'),('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','viewer'),('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','operator'),('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000004','owner');
insert into public.branches(id,bakery_id,name) values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Centro'),('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Centro');
insert into public.ingredients(id,bakery_id,name,unit,reference_cost) values ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Harina','kg',4),('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','Azucar','kg',6),('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','Sal','kg',2);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ declare v_recipe uuid; v_second uuid; v_batch uuid; begin
 perform public.record_stock_movement('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','in',20,'Compra');
 perform public.record_stock_movement('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000002','in',3.9,'Compra');
 v_recipe:=public.create_recipe_version('10000000-0000-4000-8000-000000000001','Pan',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":5},{"ingredient_id":"30000000-0000-4000-8000-000000000002","quantity":1}]'::jsonb);
 v_second:=public.create_recipe_version('10000000-0000-4000-8000-000000000001','pan',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":6},{"ingredient_id":"30000000-0000-4000-8000-000000000002","quantity":1}]'::jsonb);
 if (select version from public.recipe_versions where id=v_second)<>2 then raise exception 'version'; end if;
 begin perform public.create_recipe_version('10000000-0000-4000-8000-000000000001','Otro',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000003","quantity":1}]'::jsonb); raise exception 'foreign ingredient'; exception when invalid_parameter_value then null; end;
 begin perform public.create_recipe_version('10000000-0000-4000-8000-000000000001','Otro',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1},{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":2}]'::jsonb); raise exception 'duplicate ingredient'; exception when unique_violation then null; end;
 begin perform public.create_recipe_version('10000000-0000-4000-8000-000000000001','Otro',0,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb); raise exception 'invalid yield'; exception when invalid_parameter_value then null; end;
 if (select count(*) from public.recipe_versions)<>2 then raise exception 'recipe rollback'; end if;
 v_batch:=public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000003',150);
 if v_batch<>public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000003',150) then raise exception 'retry'; end if;
 begin perform public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000003',151); raise exception 'conflicting retry'; exception when unique_violation then null; end;
 if (select quantity from public.stock_balances where ingredient_id='30000000-0000-4000-8000-000000000001')<>12.5 then raise exception 'flour balance'; end if;
 if (select quantity from public.stock_balances where ingredient_id='30000000-0000-4000-8000-000000000002')<>2.4 then raise exception 'sugar balance'; end if;
 if (select reference_cost from public.production_batches where id=v_batch)<>39 then raise exception 'reference cost'; end if;
 update public.ingredients set reference_cost=7 where id='30000000-0000-4000-8000-000000000001';
 if (select reference_cost from public.production_batches where id=v_batch)<>39 then raise exception 'cost snapshot'; end if;
 if (select unit_cost from public.production_consumption where ingredient_id='30000000-0000-4000-8000-000000000001')<>4 then raise exception 'line cost snapshot'; end if;
 -- First ingredient can be consumed, second cannot: entire transaction must roll back.
 begin perform public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000004',250); raise exception 'insufficient stock accepted'; exception when check_violation then null; end;
 if (select quantity from public.stock_balances where ingredient_id='30000000-0000-4000-8000-000000000001')<>12.5 or (select quantity from public.stock_balances where ingredient_id='30000000-0000-4000-8000-000000000002')<>2.4 then raise exception 'atomic rollback'; end if;
 if (select count(*) from public.production_batches)<>1 or (select count(*) from public.stock_movements)<>4 or (select count(*) from public.production_consumption)<>2 then raise exception 'ledger rollback'; end if;
 begin perform public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',v_recipe,'40000000-0000-4000-8000-000000000005',1); raise exception 'cross branch'; exception when invalid_parameter_value then null; end;
 begin update public.recipe_items set quantity=100; raise exception 'direct edit'; exception when insufficient_privilege then null; end;
 begin delete from public.production_batches; raise exception 'direct delete'; exception when insufficient_privilege then null; end;
 v_recipe:=public.create_recipe_version('10000000-0000-4000-8000-000000000001','Pan redondeo',3,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb);
 perform public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000006',1);
 if (select quantity from public.stock_balances where ingredient_id='30000000-0000-4000-8000-000000000001')<>12.166 then raise exception 'rounding'; end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$ declare v_recipe uuid; begin
 select id into v_recipe from public.recipe_versions where name='Pan';
 if (select count(*) from public.recipe_versions)<>3 then raise exception 'viewer read'; end if;
 begin perform public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000007',1); raise exception 'viewer production'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
do $$ declare v_recipe uuid; begin
 select id into v_recipe from public.recipe_versions where name='Pan';
 begin perform public.create_recipe_version('10000000-0000-4000-8000-000000000001','Otro',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb); raise exception 'operator recipe'; exception when insufficient_privilege then null; end;
 perform public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000008',10);
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
do $$ begin
 if exists(select 1 from public.recipe_versions) or exists(select 1 from public.production_batches) or exists(select 1 from public.production_consumption) then raise exception 'foreign data'; end if;
 begin perform public.create_recipe_version('10000000-0000-4000-8000-000000000001','Otro',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb); raise exception 'foreign write'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.create_recipe_version('10000000-0000-4000-8000-000000000001','Otro',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb); raise exception 'anon write'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
