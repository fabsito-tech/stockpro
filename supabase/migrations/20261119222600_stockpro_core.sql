-- STOCKPRO core schema, RLS, and transactional stock operations.
-- Designed for a FRESH Supabase project. Review and apply manually; this file has NOT been executed.
-- No destructive DROP/TRUNCATE statements. Keep service_role out of browser clients.

begin;

-- ---------- Types ----------
create type public.store_role as enum ('owner', 'admin', 'employee');
create type public.sale_status as enum ('paid', 'voided');
create type public.stock_movement_kind as enum ('sale', 'adjustment', 'return', 'receipt');

-- ---------- Tenant and identity ----------
create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Usuario' check (char_length(display_name) between 1 and 120),
  avatar_url text check (avatar_url is null or char_length(avatar_url) <= 2048),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stores (
  store_id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,58}[a-z0-9]$'),
  logo_url text check (logo_url is null or char_length(logo_url) <= 2048),
  currency_code text not null default 'ARS' check (currency_code ~ '^[A-Z]{3}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, name)
);

create table public.store_members (
  store_id uuid not null references public.stores(store_id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.store_role not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (store_id, user_id)
);
create index store_members_user_active_idx on public.store_members (user_id, store_id) where is_active;
create unique index store_members_one_active_owner_idx on public.store_members (store_id) where role = 'owner' and is_active;

-- Definer helpers avoid recursive RLS policies on store_members. They only expose
-- the caller's role for the supplied tenant; callers cannot impersonate another user.
create function public.current_store_role(p_store_id uuid)
returns public.store_role
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select m.role
  from public.store_members as m
  where m.store_id = p_store_id
    and m.user_id = auth.uid()
    and m.is_active
  limit 1
$$;

create function public.is_store_member(p_store_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select public.current_store_role(p_store_id) is not null
$$;

create function public.can_manage_store(p_store_id uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public, auth
as $$
  select coalesce(public.current_store_role(p_store_id) in ('owner'::public.store_role, 'admin'::public.store_role), false)
$$;

-- Profiles are provisioned from Supabase Auth. User metadata never determines roles.
create function public.handle_new_auth_user()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(nullif(left(btrim(new.raw_user_meta_data ->> 'full_name'), 120), ''),
             nullif(left(split_part(coalesce(new.email, ''), '@', 1), 120), ''),
             'Usuario')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;
create trigger on_auth_user_created_stockpro
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- Tenant creation and member administration are RPC-only. Owners are created
-- only by create_store; set_store_member cannot assign or alter the owner role.
create function public.create_store(p_name text, p_slug text)
returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_store_id uuid;
  v_slug text;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 1 and 120 then
    raise exception 'Invalid store name' using errcode = '22023';
  end if;
  v_slug := lower(regexp_replace(btrim(coalesce(p_slug, '')), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  if char_length(v_slug) not between 3 and 60 then raise exception 'Invalid store slug' using errcode = '22023'; end if;
  insert into public.stores (name, slug) values (btrim(p_name), v_slug) returning store_id into v_store_id;
  insert into public.store_members (store_id, user_id, role) values (v_store_id, auth.uid(), 'owner');
  return v_store_id;
end;
$$;

create function public.set_store_member(p_store_id uuid, p_user_id uuid, p_role public.store_role, p_active boolean default true)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_existing_role public.store_role;
begin
  if auth.uid() is null or public.current_store_role(p_store_id) is distinct from 'owner'::public.store_role then
    raise exception 'Only the store owner can manage members' using errcode = '42501';
  end if;
  if p_user_id is null or p_role is null or p_role = 'owner'::public.store_role then
    raise exception 'Invalid member or role; ownership cannot be assigned here' using errcode = '22023';
  end if;
  select m.role into v_existing_role
  from public.store_members m where m.store_id = p_store_id and m.user_id = p_user_id
  for update;
  if v_existing_role = 'owner'::public.store_role then
    raise exception 'The owner cannot be changed with this operation' using errcode = '42501';
  end if;
  insert into public.store_members (store_id, user_id, role, is_active)
  values (p_store_id, p_user_id, p_role, coalesce(p_active, true))
  on conflict (store_id, user_id) do update
    set role = excluded.role, is_active = excluded.is_active, updated_at = now();
end;
$$;

-- ---------- Product catalog and inventory ----------
create table public.categories (
  category_id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(store_id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, category_id),
  unique (store_id, name)
);
create index categories_store_active_idx on public.categories (store_id, name) where is_active;

create table public.products (
  product_id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(store_id) on delete cascade,
  category_id uuid,
  name text not null check (char_length(btrim(name)) between 1 and 180),
  brand text check (brand is null or char_length(brand) <= 120),
  description text check (description is null or char_length(description) <= 5000),
  purchase_price numeric(12,2) not null default 0 check (purchase_price >= 0),
  sale_price numeric(12,2) not null check (sale_price >= 0),
  image_url text check (image_url is null or char_length(image_url) <= 2048),
  is_active boolean not null default true,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, product_id),
  foreign key (store_id, category_id) references public.categories(store_id, category_id) on delete restrict
);
create index products_store_category_idx on public.products (store_id, category_id);
create index products_store_name_idx on public.products (store_id, lower(name));
create index products_public_catalog_idx on public.products (store_id, name) where is_active and is_published;

create table public.product_variants (
  variant_id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  product_id uuid not null,
  sku text not null check (char_length(btrim(sku)) between 1 and 80),
  size text check (size is null or char_length(size) <= 40),
  color text check (color is null or char_length(color) <= 60),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  low_stock_threshold integer not null default 3 check (low_stock_threshold >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, variant_id),
  unique (store_id, product_id, variant_id),
  unique (store_id, sku),
  foreign key (store_id, product_id) references public.products(store_id, product_id) on delete restrict
);
create index product_variants_product_idx on public.product_variants (store_id, product_id);
create index product_variants_low_stock_idx on public.product_variants (store_id, stock_quantity) where is_active;
create unique index product_variants_option_unique_idx
  on public.product_variants (store_id, product_id, lower(coalesce(size, '')), lower(coalesce(color, '')));

-- ---------- Customers, sales, and audit ----------
create table public.customers (
  customer_id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(store_id) on delete cascade,
  full_name text not null check (char_length(btrim(full_name)) between 1 and 180),
  email text check (email is null or char_length(email) <= 320),
  phone text check (phone is null or char_length(phone) <= 40),
  notes text check (notes is null or char_length(notes) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (store_id, customer_id)
);
create index customers_store_name_idx on public.customers (store_id, lower(full_name));
create index customers_store_email_idx on public.customers (store_id, lower(email)) where email is not null;

create table public.sales (
  sale_id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(store_id) on delete cascade,
  customer_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  status public.sale_status not null default 'paid',
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  idempotency_key text not null check (char_length(btrim(idempotency_key)) between 8 and 128),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{32}$'),
  total_amount numeric(14,2) not null default 0 check (total_amount >= 0),
  created_at timestamptz not null default now(),
  unique (store_id, sale_id),
  unique (store_id, idempotency_key),
  foreign key (store_id, customer_id) references public.customers(store_id, customer_id) on delete restrict
);
create index sales_store_created_idx on public.sales (store_id, created_at desc);
create index sales_store_customer_idx on public.sales (store_id, customer_id) where customer_id is not null;

create table public.sale_items (
  sale_item_id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  sale_id uuid not null,
  product_id uuid not null,
  variant_id uuid not null,
  product_name_snapshot text not null check (char_length(product_name_snapshot) between 1 and 180),
  sku_snapshot text not null check (char_length(sku_snapshot) between 1 and 80),
  size_snapshot text,
  color_snapshot text,
  quantity integer not null check (quantity > 0),
  unit_sale_price numeric(12,2) not null check (unit_sale_price >= 0),
  unit_purchase_price numeric(12,2) not null check (unit_purchase_price >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  foreign key (store_id, sale_id) references public.sales(store_id, sale_id) on delete restrict,
  foreign key (store_id, product_id) references public.products(store_id, product_id) on delete restrict,
  foreign key (store_id, variant_id) references public.product_variants(store_id, variant_id) on delete restrict,
  foreign key (store_id, product_id, variant_id) references public.product_variants(store_id, product_id, variant_id) on delete restrict
);
create index sale_items_sale_idx on public.sale_items (store_id, sale_id);
create index sale_items_product_idx on public.sale_items (store_id, product_id);

create table public.stock_movements (
  movement_id uuid primary key default gen_random_uuid(),
  store_id uuid not null,
  variant_id uuid not null,
  sale_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  kind public.stock_movement_kind not null,
  quantity_delta integer not null check (quantity_delta <> 0),
  reason text check (reason is null or char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  foreign key (store_id, variant_id) references public.product_variants(store_id, variant_id) on delete restrict,
  foreign key (store_id, sale_id) references public.sales(store_id, sale_id) on delete restrict,
  check ((kind = 'sale' and quantity_delta < 0 and sale_id is not null)
      or (kind = 'return' and quantity_delta > 0 and sale_id is not null)
      or (kind in ('adjustment', 'receipt') and sale_id is null))
);
create index stock_movements_variant_created_idx on public.stock_movements (store_id, variant_id, created_at desc);
create index stock_movements_sale_idx on public.stock_movements (store_id, sale_id) where sale_id is not null;

-- Updated timestamps are server-controlled.
create function public.set_updated_at()
returns trigger language plpgsql set search_path = pg_catalog
as $$ begin new.updated_at := now(); return new; end $$;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger stores_set_updated_at before update on public.stores for each row execute function public.set_updated_at();
create trigger store_members_set_updated_at before update on public.store_members for each row execute function public.set_updated_at();
create trigger categories_set_updated_at before update on public.categories for each row execute function public.set_updated_at();
create trigger products_set_updated_at before update on public.products for each row execute function public.set_updated_at();
create trigger product_variants_set_updated_at before update on public.product_variants for each row execute function public.set_updated_at();
create trigger customers_set_updated_at before update on public.customers for each row execute function public.set_updated_at();

-- ---------- Public catalog: only explicitly public fields; private base tables are not granted to anon ----------
create view public.public_catalog
with (security_barrier = true)
as
select
  s.slug as store_slug,
  s.name as store_name,
  p.product_id,
  p.name,
  p.brand,
  p.description,
  p.sale_price,
  p.image_url,
  c.name as category,
  coalesce(
    jsonb_agg(jsonb_build_object('size', v.size, 'color', v.color)
              order by v.size nulls first, v.color nulls first)
      filter (where v.variant_id is not null),
    '[]'::jsonb
  ) as available_variants
from public.products p
join public.stores s on s.store_id = p.store_id and s.is_active
left join public.categories c on c.store_id = p.store_id and c.category_id = p.category_id and c.is_active
left join public.product_variants v on v.store_id = p.store_id and v.product_id = p.product_id and v.is_active and v.stock_quantity > 0
where p.is_active and p.is_published
group by s.slug, s.name, p.product_id, p.name, p.brand, p.description, p.sale_price, p.image_url, c.name;

-- ---------- Transactional sales and stock adjustments ----------
create function public.record_sale(
  p_store_id uuid,
  p_idempotency_key text,
  p_items jsonb,
  p_customer_id uuid default null
)
returns table (sale_id uuid, total_amount numeric(14,2), was_replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_actor uuid := auth.uid();
  v_lines jsonb;
  v_customer_id uuid;
  v_hash text;
  v_prior public.sales%rowtype;
  v_line record;
  v_variant record;
  v_sale_id uuid;
  v_total numeric(14,2) := 0;
begin
  if v_actor is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if public.current_store_role(p_store_id) is null or public.current_store_role(p_store_id) not in ('owner'::public.store_role, 'admin'::public.store_role, 'employee'::public.store_role) then
    raise exception 'Not a member of this store' using errcode = '42501';
  end if;
  if p_idempotency_key is null or char_length(btrim(p_idempotency_key)) not between 8 and 128 then
    raise exception 'Invalid idempotency key' using errcode = '22023';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'Items must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) not between 1 and 100 then
    raise exception 'Items array must contain 1 to 100 entries' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements(p_items) e where jsonb_typeof(e) <> 'object'
            or not (e ? 'variant_id') or not (e ? 'quantity')) then
    raise exception 'Each item needs variant_id and quantity' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) as r(variant_id uuid, quantity integer)
    where r.variant_id is null or r.quantity is null or r.quantity <= 0 or r.quantity > 100000
  ) then raise exception 'Invalid variant or quantity' using errcode = '22023'; end if;

  select jsonb_agg(jsonb_build_object('variant_id', x.variant_id, 'quantity', x.quantity) order by x.variant_id)
  into v_lines
  from (
    select r.variant_id, sum(r.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as r(variant_id uuid, quantity integer)
    group by r.variant_id
  ) x;
  if v_lines is null or exists (
    select 1 from jsonb_to_recordset(v_lines) as r(variant_id uuid, quantity integer)
    where r.quantity > 100000
  ) then
    raise exception 'Quantity per variant exceeds the sale limit' using errcode = '22023';
  end if;
  v_hash := md5(v_lines::text);
  v_customer_id := p_customer_id;

  -- Serialize retries for a given tenant/idempotency key, including simultaneous retries.
  perform pg_advisory_xact_lock(hashtextextended(p_store_id::text || ':' || p_idempotency_key, 0));
  select * into v_prior from public.sales s
  where s.store_id = p_store_id and s.idempotency_key = p_idempotency_key;
  if found then
    if v_prior.created_by <> v_actor or v_prior.request_hash <> v_hash or v_prior.customer_id is distinct from p_customer_id then
      raise exception 'Idempotency key was already used for a different request' using errcode = '23505';
    end if;
    return query select v_prior.sale_id, v_prior.total_amount, true;
    return;
  end if;

  if p_customer_id is not null and not exists (
    select 1 from public.customers c where c.store_id = p_store_id and c.customer_id = p_customer_id
  ) then raise exception 'Customer not found in this store' using errcode = '23503'; end if;

  -- Lock in stable UUID order to avoid deadlocks across overlapping baskets.
  for v_line in
    select r.variant_id, r.quantity from jsonb_to_recordset(v_lines) as r(variant_id uuid, quantity integer)
    order by r.variant_id
  loop
    select pv.variant_id, pv.product_id, pv.sku, pv.size, pv.color, pv.stock_quantity,
           pv.is_active as variant_active, p.name as product_name,
           p.is_active as product_active, p.sale_price, p.purchase_price
    into v_variant
    from public.product_variants pv
    join public.products p on p.store_id = pv.store_id and p.product_id = pv.product_id
    where pv.store_id = p_store_id and pv.variant_id = v_line.variant_id
    for update of pv;
    if not found or not v_variant.variant_active or not v_variant.product_active then
      raise exception 'Product variant is unavailable' using errcode = 'P0001';
    end if;
    if v_variant.stock_quantity < v_line.quantity then
      raise exception 'Insufficient stock for variant %', v_line.variant_id using errcode = 'P0001';
    end if;
    v_total := v_total + (v_variant.sale_price * v_line.quantity);
  end loop;

  insert into public.sales (store_id, customer_id, created_by, currency_code, idempotency_key, request_hash, total_amount)
  select p_store_id, v_customer_id, v_actor, s.currency_code, p_idempotency_key, v_hash, v_total
  from public.stores s where s.store_id = p_store_id and s.is_active
  returning public.sales.sale_id into v_sale_id;
  if v_sale_id is null then raise exception 'Store is inactive or unavailable' using errcode = 'P0001'; end if;

  for v_line in
    select r.variant_id, r.quantity from jsonb_to_recordset(v_lines) as r(variant_id uuid, quantity integer)
    order by r.variant_id
  loop
    select pv.variant_id, pv.product_id, pv.sku, pv.size, pv.color, pv.stock_quantity,
           p.name as product_name, p.sale_price, p.purchase_price
    into v_variant
    from public.product_variants pv
    join public.products p on p.store_id = pv.store_id and p.product_id = pv.product_id
    where pv.store_id = p_store_id and pv.variant_id = v_line.variant_id
    for update of pv;
    insert into public.sale_items (store_id, sale_id, product_id, variant_id,
      product_name_snapshot, sku_snapshot, size_snapshot, color_snapshot, quantity,
      unit_sale_price, unit_purchase_price, line_total)
    values (p_store_id, v_sale_id, v_variant.product_id, v_variant.variant_id,
      v_variant.product_name, v_variant.sku, v_variant.size, v_variant.color, v_line.quantity,
      v_variant.sale_price, v_variant.purchase_price, v_variant.sale_price * v_line.quantity);
    update public.product_variants pv
      set stock_quantity = pv.stock_quantity - v_line.quantity
      where pv.store_id = p_store_id and pv.variant_id = v_line.variant_id;
    insert into public.stock_movements (store_id, variant_id, sale_id, created_by, kind, quantity_delta, reason)
    values (p_store_id, v_line.variant_id, v_sale_id, v_actor, 'sale', -v_line.quantity, 'Venta registrada');
  end loop;

  return query select v_sale_id, v_total, false;
end;
$$;

create function public.adjust_stock(p_store_id uuid, p_variant_id uuid, p_quantity_delta integer, p_reason text)
returns integer
language plpgsql security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_actor uuid := auth.uid();
  v_stock integer;
  v_next integer;
begin
  if v_actor is null or public.current_store_role(p_store_id) is null or public.current_store_role(p_store_id) not in ('owner'::public.store_role, 'admin'::public.store_role) then
    raise exception 'Only a store owner or admin can adjust stock' using errcode = '42501';
  end if;
  if p_quantity_delta is null or p_quantity_delta = 0 or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then
    raise exception 'A non-zero quantity and reason are required' using errcode = '22023';
  end if;
  select pv.stock_quantity into v_stock from public.product_variants pv
  where pv.store_id = p_store_id and pv.variant_id = p_variant_id for update;
  if not found then raise exception 'Variant not found in this store' using errcode = 'P0002'; end if;
  v_next := v_stock + p_quantity_delta;
  if v_next < 0 then raise exception 'Stock cannot become negative' using errcode = 'P0001'; end if;
  update public.product_variants set stock_quantity = v_next
  where store_id = p_store_id and variant_id = p_variant_id;
  insert into public.stock_movements (store_id, variant_id, created_by, kind, quantity_delta, reason)
  values (p_store_id, p_variant_id, v_actor,
          case when p_quantity_delta > 0 then 'receipt'::public.stock_movement_kind else 'adjustment'::public.stock_movement_kind end,
          p_quantity_delta, btrim(p_reason));
  return v_next;
end;
$$;

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;
alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.stock_movements enable row level security;

create policy profiles_select_self on public.profiles for select to authenticated using (user_id = (select auth.uid()));
create policy profiles_update_self on public.profiles for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy stores_select_member on public.stores for select to authenticated using (public.is_store_member(store_id));
create policy stores_update_manager on public.stores for update to authenticated using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

create policy members_select_self_or_manager on public.store_members for select to authenticated
  using (user_id = (select auth.uid()) or public.can_manage_store(store_id));

create policy categories_select_member on public.categories for select to authenticated using (public.is_store_member(store_id));
create policy categories_insert_manager on public.categories for insert to authenticated with check (public.can_manage_store(store_id));
create policy categories_update_manager on public.categories for update to authenticated using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

create policy products_select_member on public.products for select to authenticated using (public.is_store_member(store_id));
create policy products_insert_manager on public.products for insert to authenticated with check (public.can_manage_store(store_id));
create policy products_update_manager on public.products for update to authenticated using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

create policy variants_select_member on public.product_variants for select to authenticated using (public.is_store_member(store_id));
create policy variants_insert_manager on public.product_variants for insert to authenticated with check (public.can_manage_store(store_id));
create policy variants_update_manager on public.product_variants for update to authenticated using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

create policy customers_select_member on public.customers for select to authenticated using (public.is_store_member(store_id));
create policy customers_insert_member on public.customers for insert to authenticated with check (public.is_store_member(store_id));
create policy customers_update_manager on public.customers for update to authenticated using (public.can_manage_store(store_id)) with check (public.can_manage_store(store_id));

create policy sales_select_member on public.sales for select to authenticated using (public.is_store_member(store_id));
create policy sale_items_select_member on public.sale_items for select to authenticated using (public.is_store_member(store_id));
create policy stock_movements_select_member on public.stock_movements for select to authenticated using (public.is_store_member(store_id));

-- ---------- Least-privilege API grants ----------
revoke all on public.profiles, public.stores, public.store_members, public.categories,
  public.products, public.product_variants, public.customers, public.sales,
  public.sale_items, public.stock_movements from anon, authenticated;
revoke all on public.public_catalog from anon, authenticated;

-- Profile edits cannot alter user_id; commercial deletes are deliberately omitted
-- (archive via is_active so historical sales/audit records are retained).
grant select on public.profiles to authenticated;
grant update (display_name, avatar_url) on public.profiles to authenticated;
grant select on public.stores to authenticated;
grant update (name, logo_url, currency_code) on public.stores to authenticated;
grant select on public.store_members to authenticated;
grant select on public.categories to authenticated;
grant insert (store_id, name, is_active) on public.categories to authenticated;
grant update (name, is_active) on public.categories to authenticated;
grant select on public.products to authenticated;
grant insert (store_id, category_id, name, brand, description, purchase_price, sale_price, image_url, is_active, is_published) on public.products to authenticated;
grant update (category_id, name, brand, description, purchase_price, sale_price, image_url, is_active, is_published) on public.products to authenticated;
-- store_id/product_id/SKU/options can be inserted; stock quantity is changed only by RPC.
grant select, insert (store_id, product_id, sku, size, color, low_stock_threshold, is_active),
  update (sku, size, color, low_stock_threshold, is_active) on public.product_variants to authenticated;
grant select on public.customers to authenticated;
grant insert (store_id, full_name, email, phone, notes) on public.customers to authenticated;
grant update (full_name, email, phone, notes) on public.customers to authenticated;
grant select on public.sales, public.sale_items, public.stock_movements to authenticated;
grant select on public.public_catalog to anon, authenticated;

revoke all on function public.current_store_role(uuid) from public, anon;
revoke all on function public.is_store_member(uuid) from public, anon;
revoke all on function public.can_manage_store(uuid) from public, anon;
revoke all on function public.handle_new_auth_user() from public, anon, authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.create_store(text, text) from public, anon;
revoke all on function public.set_store_member(uuid, uuid, public.store_role, boolean) from public, anon;
revoke all on function public.record_sale(uuid, text, jsonb, uuid) from public, anon;
revoke all on function public.adjust_stock(uuid, uuid, integer, text) from public, anon;
grant execute on function public.current_store_role(uuid) to authenticated;
grant execute on function public.is_store_member(uuid) to authenticated;
grant execute on function public.can_manage_store(uuid) to authenticated;
grant execute on function public.create_store(text, text) to authenticated;
grant execute on function public.set_store_member(uuid, uuid, public.store_role, boolean) to authenticated;
grant execute on function public.record_sale(uuid, text, jsonb, uuid) to authenticated;
grant execute on function public.adjust_stock(uuid, uuid, integer, text) to authenticated;

commit;
