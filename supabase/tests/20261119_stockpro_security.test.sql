-- STOCKPRO integration/security tests for Supabase local ONLY.
-- Run with: supabase test db (against a disposable local stack).
-- This test rolls back fixtures. Never run against a remote/live project.
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public, auth, pg_catalog;
select no_plan();

-- Stable IDs; test runs in a transaction and rolls back all fixture rows.
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
values
 ('a0000000-0000-4000-8000-000000000001','authenticated','authenticated','owner-a@stockpro.test','',now(),'{}','{"full_name":"Owner A"}'),
 ('a0000000-0000-4000-8000-000000000002','authenticated','authenticated','admin-a@stockpro.test','',now(),'{}','{"full_name":"Admin A"}'),
 ('a0000000-0000-4000-8000-000000000003','authenticated','authenticated','employee-a@stockpro.test','',now(),'{}','{"full_name":"Employee A"}'),
 ('b0000000-0000-4000-8000-000000000001','authenticated','authenticated','owner-b@stockpro.test','',now(),'{}','{"full_name":"Owner B"}'),
 ('c0000000-0000-4000-8000-000000000001','authenticated','authenticated','outsider@stockpro.test','',now(),'{}','{"full_name":"Outsider"}'),
 ('d1000000-0000-4000-8000-000000000001','authenticated','authenticated','invitee@stockpro.test','',now(),'{}','{"full_name":"Invitee"}');

insert into public.stores (store_id, name, slug) values
 ('10000000-0000-4000-8000-000000000001','Tienda A test','stockpro-test-a'),
 ('20000000-0000-4000-8000-000000000002','Tienda B test','stockpro-test-b');
insert into public.store_members (store_id,user_id,role) values
 ('10000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001','owner'),
 ('10000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002','admin'),
 ('10000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000003','employee'),
 ('20000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','owner');
insert into public.categories (category_id,store_id,name) values
 ('11000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','Calzado A'),
 ('22000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Ropa B');
insert into public.products (product_id,store_id,category_id,name,sale_price,purchase_price,is_active,is_published) values
 ('11100000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','A publicado',100,40,true,true),
 ('11100000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','A sin publicar',100,40,true,false),
 ('11100000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','A inactivo',100,40,false,true),
 ('22200000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','22000000-0000-4000-8000-000000000002','B publicado',200,80,true,true);
insert into public.product_variants (variant_id,store_id,product_id,sku,size,color,stock_quantity) values
 ('11110000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','11100000-0000-4000-8000-000000000001','A-SKU-1','38','Negro',10),
 ('11110000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000001','11100000-0000-4000-8000-000000000001','A-SKU-2','39','Negro',1),
 ('11110000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001','11100000-0000-4000-8000-000000000001','A-SKU-3','40','Negro',0),
 ('22220000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','22200000-0000-4000-8000-000000000001','B-SKU-1','M','Azul',7);

-- Structural checks.
select ok((select relrowsecurity from pg_class where oid='public.products'::regclass), 'products has RLS enabled');
select ok((select relrowsecurity from pg_class where oid='public.sales'::regclass), 'sales has RLS enabled');
select ok((select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname = any(array['profiles','stores','store_members','categories','products','product_variants','customers','sales','sale_items','stock_movements'])), 'RLS is enabled on every business table');
select ok((select prosecdef from pg_proc where oid='public.record_sale(uuid,text,jsonb,uuid)'::regprocedure), 'record_sale is SECURITY DEFINER');
select ok((select prosecdef from pg_proc where oid='public.adjust_stock(uuid,uuid,integer,text)'::regprocedure), 'adjust_stock is SECURITY DEFINER');
select ok((select proconfig @> array['search_path=pg_catalog, auth'] from pg_proc where oid='public.record_sale(uuid,text,jsonb,uuid)'::regprocedure), 'record_sale pins safe search_path');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and p.proname in ('current_store_role','is_store_member','can_manage_store','create_store','set_store_member','record_sale','adjust_stock') and not (p.proconfig @> array['search_path=pg_catalog, auth'])), 'all callable SECURITY DEFINER functions pin the safe search_path');
select ok(not has_function_privilege('anon','public.record_sale(uuid,text,jsonb,uuid)','EXECUTE'), 'anon cannot execute record_sale');
select ok(has_function_privilege('authenticated','public.record_sale(uuid,text,jsonb,uuid)','EXECUTE'), 'authenticated can execute sale RPC');
select ok(not has_function_privilege('anon','public.adjust_stock(uuid,uuid,integer,text)','EXECUTE'), 'anon cannot execute adjust_stock');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef and p.proname in ('current_store_role','is_store_member','can_manage_store','create_store','set_store_member','record_sale','adjust_stock') and has_function_privilege('anon',p.oid,'EXECUTE')), 'anon has no EXECUTE on callable SECURITY DEFINER functions');
select ok(not has_function_privilege('authenticated','public.handle_new_auth_user()','EXECUTE'), 'authenticated cannot invoke auth trigger function');

-- Public catalog is a curated view: only active and published products, only in-stock options.
set local role anon;
select throws_ok($$select product_id from public.products$$,'42501',null,'anon cannot read private product rows');
select throws_ok($$select * from public.manager_products$$,'42501',null,'anon cannot read manager product view');
select is((select count(*)::integer from public.public_catalog where store_slug='stockpro-test-a'),1,'public catalog only lists published active items for store A');
select is((select count(*)::integer from public.public_catalog where store_slug='stockpro-test-b'),1,'public catalog only lists published active items for store B');
select is((select count(*)::integer from public.public_catalog where store_slug='stockpro-test-a' and name in ('A sin publicar','A inactivo')),0,'unpublished and inactive items are hidden');
select ok(not exists(select 1 from information_schema.columns where table_schema='public' and table_name='public_catalog' and column_name in ('stock_quantity','purchase_price')),'public catalog view omits private stock quantities and purchase costs');
select is((select jsonb_array_length(available_variants)::integer from public.public_catalog where store_slug='stockpro-test-a'),2,'public catalog exposes in-stock variants but not zero-stock options');
reset role;

-- Owner A cannot read/update/insert into tenant B despite knowing its IDs.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select is((select count(*)::integer from public.products where store_id='20000000-0000-4000-8000-000000000002'),0,'owner A cannot read store B products');
select is((select count(*)::integer from public.manager_products where store_id='20000000-0000-4000-8000-000000000002'),0,'owner A cannot see store B through the manager-only view');
select is((with changed as (update public.products set name='tampered' where store_id='20000000-0000-4000-8000-000000000002' returning 1) select count(*)::integer from changed),0,'owner A cannot modify store B products');
select throws_ok($$insert into public.categories(store_id,name) values ('20000000-0000-4000-8000-000000000002','cross tenant')$$,'42501',null,'owner A cannot insert into store B');
select is((select purchase_price from public.manager_products where product_id='11100000-0000-4000-8000-000000000001'),40::numeric,'owner can read private purchase cost through manager view');
select lives_ok($$insert into public.categories(store_id,name) values ('10000000-0000-4000-8000-000000000001','Owner category')$$,'owner A can create a category in own store');
select lives_ok($$select public.set_store_member('10000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','employee',true)$$,'owner A can add a lower-privilege member');
select throws_ok($$select public.set_store_member('10000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','owner',true)$$,'22023',null,'owner RPC cannot assign another owner');
reset role;

-- Admin A has commercial permissions, but cannot manage members or assign roles.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000002',true);
set local role authenticated;
select lives_ok($$insert into public.categories(store_id,name) values ('10000000-0000-4000-8000-000000000001','Admin category')$$,'admin can manage own catalog');
select lives_ok($$update public.products set name='A publicado editado' where product_id='11100000-0000-4000-8000-000000000001'$$,'admin can update own product');
select is((select purchase_price from public.manager_products where product_id='11100000-0000-4000-8000-000000000001'),40::numeric,'admin can read private purchase cost through manager view');
select throws_ok($$select public.set_store_member('10000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001','admin',true)$$,'42501',null,'admin cannot manage members');
select is(public.adjust_stock('10000000-0000-4000-8000-000000000001','11110000-0000-4000-8000-000000000001',1,'test admin receipt'),11,'admin can make audited stock adjustment');
reset role;

-- Employee A can sell but cannot edit products, manage members, or adjust stock.
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
set local role authenticated;
select throws_ok($$insert into public.products(store_id,name,sale_price) values ('10000000-0000-4000-8000-000000000001','employee product',1)$$,'42501',null,'employee cannot create products');
select is((select count(*)::integer from public.manager_products where store_id='10000000-0000-4000-8000-000000000001'),0,'employee cannot see the manager-only product view');
select throws_ok($$select purchase_price from public.products where product_id='11100000-0000-4000-8000-000000000001'$$,'42501',null,'employee cannot select purchase costs from base products');
select is((with changed as (update public.products set name='employee tamper' where product_id='11100000-0000-4000-8000-000000000001' returning 1) select count(*)::integer from changed),0,'employee cannot update own product');
select throws_ok($$select public.adjust_stock('10000000-0000-4000-8000-000000000001','11110000-0000-4000-8000-000000000001',1,'unauthorized')$$,'42501',null,'employee cannot adjust inventory');
select is((select count(*)::integer from public.store_members where store_id='20000000-0000-4000-8000-000000000002'),0,'employee A cannot enumerate store B members');
select is((select count(*)::integer from public.products where store_id='20000000-0000-4000-8000-000000000002'),0,'employee A cannot query store B products');
select is((with changed as (update public.products set name='cross tenant employee tamper' where store_id='20000000-0000-4000-8000-000000000002' returning 1) select count(*)::integer from changed),0,'employee A cannot modify store B products');
select throws_ok($$select * from public.record_sale('20000000-0000-4000-8000-000000000002','cross-tenant-sale-001','[{"variant_id":"22220000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,null)$$,'42501',null,'employee A cannot call sale RPC for store B');

-- Valid sale, replay idempotency, insufficient stock, invalid quantity and atomic rollback.
select lives_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0001','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":2}]'::jsonb,null)$$,'employee can record a sale with sufficient stock');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000001'),9,'successful sale decrements by sale quantity after the admin receipt');
select is((select count(*)::integer from public.sales where idempotency_key='test-sale-key-0001'),1,'successful sale is recorded once');
select is((select unit_purchase_price from public.sale_items_read where sale_id=(select sale_id from public.sales where idempotency_key='test-sale-key-0001')),null::numeric,'employee sale-history view masks purchase cost');
select throws_ok($$select unit_purchase_price from public.sale_items where sale_id=(select sale_id from public.sales where idempotency_key='test-sale-key-0001')$$,'42501',null,'employee cannot query raw purchase cost snapshot');
select is((select was_replayed from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0001','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":2}]'::jsonb,null)),true,'same idempotent request reports replay');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000001'),9,'idempotent replay does not decrement stock twice');
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0001','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,null)$$,'23505',null,'reusing an idempotency key for a different request is rejected');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000001'),9,'conflicting idempotency retry does not change stock');
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0002','[{"variant_id":"11110000-0000-4000-8000-000000000002","quantity":2}]'::jsonb,null)$$,'P0001',null,'insufficient stock rejects sale');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000002'),1,'insufficient-stock sale does not decrement the insufficient variant');
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0003','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":0}]'::jsonb,null)$$,'22023',null,'zero quantity is rejected');
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0006','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":-1}]'::jsonb,null)$$,'22023',null,'negative quantity is rejected');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000001'),9,'invalid quantity leaves inventory unchanged');
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0004','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":1},{"variant_id":"11110000-0000-4000-8000-000000000002","quantity":2}]'::jsonb,null)$$,'P0001',null,'mixed basket with one insufficient item fails as a whole');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000001'),9,'failed mixed basket rolls back earlier stock rows');
select is((select count(*)::integer from public.sales where idempotency_key='test-sale-key-0004'),0,'failed mixed basket creates no sale header');
select is((select count(*)::integer from public.stock_movements where sale_id in (select sale_id from public.sales where idempotency_key='test-sale-key-0004')),0,'failed mixed basket creates no stock movements');
reset role;

-- Force a late failure after the first variant has been updated to verify statement-level rollback.
create function public.stockpro_test_reject_second_movement()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin
  if new.variant_id = '11110000-0000-4000-8000-000000000002'::uuid then
    raise exception 'forced late failure for atomicity test' using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger stockpro_test_reject_second_movement before insert on public.stock_movements
for each row execute function public.stockpro_test_reject_second_movement();
set local role authenticated;
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','test-sale-key-0005','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":1},{"variant_id":"11110000-0000-4000-8000-000000000002","quantity":1}]'::jsonb,null)$$,'P0001',null,'late failure after an earlier variant update rejects the entire transaction');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000001'),9,'late failure rolls back the first variant stock update');
select is((select stock_quantity from public.product_variants where variant_id='11110000-0000-4000-8000-000000000002'),1,'late failure leaves the second variant unchanged');
select is((select count(*)::integer from public.sales where idempotency_key='test-sale-key-0005'),0,'late failure rolls back the sale header');
select is((select count(*)::integer from public.stock_movements where store_id='10000000-0000-4000-8000-000000000001' and sale_id is not null and kind='sale'),1,'late failure rolls back its stock movements');
reset role;
drop trigger stockpro_test_reject_second_movement on public.stock_movements;
drop function public.stockpro_test_reject_second_movement();
select set_config('request.jwt.claim.sub','a0000000-0000-4000-8000-000000000003',true);
set local role authenticated;

-- B owner is limited to B data; a nonmember has no private access.
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select is((select count(*)::integer from public.products where store_id='10000000-0000-4000-8000-000000000001'),0,'owner B cannot read store A products');
select is((select count(*)::integer from public.manager_products where store_id='10000000-0000-4000-8000-000000000001'),0,'owner B cannot see store A through the manager-only view');
select is((select count(*)::integer from public.sales where store_id='10000000-0000-4000-8000-000000000001'),0,'owner B cannot read store A sales');
reset role;
select set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000001',true);
set local role authenticated;
select is((select count(*)::integer from public.products where store_id='10000000-0000-4000-8000-000000000001'),0,'nonmember cannot read store A products');
select is((select count(*)::integer from public.products where store_id='20000000-0000-4000-8000-000000000002'),0,'nonmember cannot read store B products');
select throws_ok($$select * from public.record_sale('10000000-0000-4000-8000-000000000001','outsider-sale-key-01','[{"variant_id":"11110000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,null)$$,'42501',null,'nonmember cannot call sale RPC for either tenant');
reset role;

select * from finish();
rollback;
