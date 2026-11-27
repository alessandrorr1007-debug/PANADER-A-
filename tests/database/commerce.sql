begin;
insert into auth.users(id) values ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002'),('00000000-0000-4000-8000-000000000003'),('00000000-0000-4000-8000-000000000004');
insert into public.bakeries(id,name) values ('10000000-0000-4000-8000-000000000001','A'),('10000000-0000-4000-8000-000000000002','B');
insert into public.bakery_members(bakery_id,user_id,role) values ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','owner'),('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002','viewer'),('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003','operator'),('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000004','owner');
insert into public.branches(id,bakery_id,name) values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Centro'),('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Centro');
insert into public.ingredients(id,bakery_id,name,unit,reference_cost) values ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Harina','kg',4),('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Harina','kg',4);
insert into public.suppliers(id,bakery_id,name) values ('50000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Proveedor A'),('50000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','Proveedor B');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
do $$ declare v_receipt uuid; v_recipe uuid; v_batch uuid; v_second uuid; v_sale uuid; begin
 if (select count(*) from public.suppliers)<>1 then raise exception 'supplier isolation'; end if;
 v_receipt:=public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":20,"unit_cost":3.5}]'::jsonb);
 if v_receipt<>public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":20,"unit_cost":3.5}]'::jsonb) then raise exception 'receipt retry'; end if;
 if (select quantity from public.stock_balances)<>20 or (select total from public.purchase_receipts)<>70 then raise exception 'receipt stock or total'; end if;
 begin perform public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":21,"unit_cost":3.5}]'::jsonb); raise exception 'receipt conflict'; exception when unique_violation then null; end;
 begin perform public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1,"unit_cost":4},{"ingredient_id":"30000000-0000-4000-8000-000000000002","quantity":1,"unit_cost":4}]'::jsonb); raise exception 'foreign ingredient'; exception when invalid_parameter_value then null; end;
 begin perform public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000003','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1,"unit_cost":4}]'::jsonb); raise exception 'foreign supplier'; exception when invalid_parameter_value then null; end;
 if (select quantity from public.stock_balances)<>20 or (select count(*) from public.purchase_receipts)<>1 or (select count(*) from public.stock_movements)<>1 then raise exception 'receipt rollback'; end if;
 v_recipe:=public.create_recipe_version('10000000-0000-4000-8000-000000000001','Pan',100,'[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":5}]');
 v_batch:=public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000004',100);
 v_second:=public.complete_production('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',v_recipe,'40000000-0000-4000-8000-000000000005',50);
 if (select sum(available_units) from public.finished_stock)<>150 then raise exception 'production stock'; end if;
 v_sale:=public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000006','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',20,'unit_price',0.5)));
 if v_sale<>public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000006','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',20,'unit_price',0.5))) then raise exception 'sale retry'; end if;
 if (select total from public.sales)<>10 or (select available_units from public.finished_stock where batch_id=v_batch)<>80 then raise exception 'sale stock or total'; end if;
 begin perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000006','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',21,'unit_price',0.5))); raise exception 'sale conflict'; exception when unique_violation then null; end;
 begin perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000007','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',81,'unit_price',0.5))); raise exception 'oversale'; exception when check_violation then null; end;
 begin perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000008','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',1.5,'unit_price',0.5))); raise exception 'fraction units'; exception when invalid_parameter_value then null; end;
 begin perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000009','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',1,'unit_price',0.005))); raise exception 'price precision'; exception when invalid_parameter_value then null; end;
 begin perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000010','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',10,'unit_price',0.5)) || jsonb_build_array(jsonb_build_object('batch_id',v_second,'units',51,'unit_price',0.5))); raise exception 'partial sale'; exception when check_violation then null; end;
 if (select sum(available_units) from public.finished_stock)<>130 or (select count(*) from public.sales)<>1 or (select count(*) from public.sale_items)<>1 then raise exception 'sale rollback'; end if;
 begin update public.sale_items set units=1; raise exception 'direct edit'; exception when insufficient_privilege then null; end;
 begin delete from public.purchase_receipts; raise exception 'direct delete'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$ declare v_batch uuid; begin
 select batch_id into v_batch from public.finished_stock order by output_units desc limit 1;
 if (select count(*) from public.sales)<>1 then raise exception 'viewer read'; end if;
 begin perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000011','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',1,'unit_price',0.5))); raise exception 'viewer sale'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
do $$ declare v_batch uuid; begin
 select batch_id into v_batch from public.finished_stock order by output_units desc limit 1;
 perform public.record_sale('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000012','cash',jsonb_build_array(jsonb_build_object('batch_id',v_batch,'units',10,'unit_price',0.5)));
 begin perform public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000013','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1,"unit_cost":4}]'::jsonb); raise exception 'operator receipt'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
do $$ begin
 if exists(select 1 from public.sales) or exists(select 1 from public.finished_stock) or exists(select 1 from public.purchase_receipts) then raise exception 'foreign read'; end if;
 begin perform public.receive_purchase('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000014','[{"ingredient_id":"30000000-0000-4000-8000-000000000001","quantity":1,"unit_cost":4}]'::jsonb); raise exception 'foreign write'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform count(*) from public.finished_stock; raise exception 'anon stock'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
