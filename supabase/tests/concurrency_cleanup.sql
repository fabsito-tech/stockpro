-- Local disposable DB only. Removes only the fixed concurrency-test fixture IDs.
drop trigger if exists stockpro_test_delay_stock_update on public.product_variants;
drop function if exists public.stockpro_test_delay_stock_update();
delete from public.stock_movements where store_id='30000000-0000-4000-8000-000000000003';
delete from public.sale_items where store_id='30000000-0000-4000-8000-000000000003';
delete from public.sales where store_id='30000000-0000-4000-8000-000000000003';
delete from public.product_variants where store_id='30000000-0000-4000-8000-000000000003';
delete from public.products where store_id='30000000-0000-4000-8000-000000000003';
delete from public.categories where store_id='30000000-0000-4000-8000-000000000003';
delete from public.store_members where store_id='30000000-0000-4000-8000-000000000003';
delete from public.stores where store_id='30000000-0000-4000-8000-000000000003';
delete from auth.users where id='d0000000-0000-4000-8000-000000000001';
