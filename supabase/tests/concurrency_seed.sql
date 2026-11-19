-- Local disposable DB only. Creates exactly one unit for a concurrency race test.
insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
values ('d0000000-0000-4000-8000-000000000001','authenticated','authenticated','race-owner@stockpro.test','',now(),'{}','{"full_name":"Race Owner"}');
insert into public.stores (store_id,name,slug) values ('30000000-0000-4000-8000-000000000003','Race Test Store','stockpro-race-test');
insert into public.store_members (store_id,user_id,role) values ('30000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001','owner');
insert into public.categories (category_id,store_id,name) values ('33000000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000003','Race Test');
insert into public.products (product_id,store_id,category_id,name,sale_price,purchase_price) values ('33300000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000003','33000000-0000-4000-8000-000000000003','Last Unit',10,5);
insert into public.product_variants (variant_id,store_id,product_id,sku,size,color,stock_quantity) values ('33330000-0000-4000-8000-000000000003','30000000-0000-4000-8000-000000000003','33300000-0000-4000-8000-000000000003','RACE-ONE','U','Test',1);

-- Test-only delay ensures overlapping transactions contend on the same row lock.
create function public.stockpro_test_delay_stock_update()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin perform pg_sleep(1); return new; end $$;
create trigger stockpro_test_delay_stock_update
before update of stock_quantity on public.product_variants
for each row when (old.variant_id = '33330000-0000-4000-8000-000000000003'::uuid)
execute function public.stockpro_test_delay_stock_update();
