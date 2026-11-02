-- Disposable compatibility fixture for Supabase Storage SQL/RLS tests.
-- Real deployments use the Supabase-managed storage schema and API.
do $bootstrap$
declare
  v_storage_schema_exists boolean;
begin
  v_storage_schema_exists := to_regnamespace('storage') is not null;
  if not v_storage_schema_exists then
    execute 'create schema storage';
    execute $sql$
      create table storage.buckets (
        id text primary key,
        name text not null,
        public boolean not null default false,
        file_size_limit bigint,
        allowed_mime_types text[]
      )
    $sql$;
    execute $sql$
      create table storage.objects (
        id uuid primary key default gen_random_uuid(),
        bucket_id text not null references storage.buckets(id),
        name text not null,
        metadata jsonb not null default '{}'::jsonb,
        unique(bucket_id,name)
      )
    $sql$;
    execute 'alter table storage.objects enable row level security';
  else
    if to_regclass('storage.buckets') is null or to_regclass('storage.objects') is null then
      raise exception 'existing storage schema is missing Supabase-managed buckets/objects tables; do not create replacement tables inside a managed schema';
    end if;
  end if;

  if not has_schema_privilege('authenticated','storage','USAGE') then
    execute 'grant usage on schema storage to authenticated';
  end if;
  if not has_table_privilege('authenticated','storage.objects','SELECT') then
    execute 'grant select on storage.objects to authenticated';
  end if;
  if not has_table_privilege('authenticated','storage.objects','INSERT') then
    execute 'grant insert on storage.objects to authenticated';
  end if;
end
$bootstrap$;
