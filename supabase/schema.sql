-- iD Fresh Artwork Library — database setup
-- Run once in Supabase → SQL Editor → New query → paste → Run.
-- Safe to run again: it drops and recreates its own policies and triggers.

-- 1. Tables ---------------------------------------------------------------
create table if not exists public.projects (
  id          text primary key,                       -- e.g. AW-399
  doc         jsonb not null,                         -- full project record used by the app
  stage       text generated always as (doc->>'stage') stored,
  product     text generated always as (doc->>'product') stored,
  updated_at  timestamptz not null default now()
);
create index if not exists projects_stage_idx on public.projects (stage);

create table if not exists public.settings (
  id          text primary key,                       -- 'brand'
  doc         jsonb not null,
  updated_at  timestamptz not null default now()
);

-- The team list: who can sign in, and what they can do.
-- Access levels: admin, requester (Marketing), designer (Creative/agency), approver (Quality/Legal/Manufacturing), viewer.
create table if not exists public.team (
  email       text primary key check (email = lower(email) and email like '%@idfreshfood.com'),
  full_name   text not null,
  department  text,
  role        text not null default 'viewer' check (role in ('admin','requester','designer','approver','viewer')),
  invited_at  timestamptz,
  invited_by  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

drop trigger if exists touch_projects on public.projects;
create trigger touch_projects before update on public.projects for each row execute function public.touch_updated_at();
drop trigger if exists touch_settings on public.settings;
create trigger touch_settings before update on public.settings for each row execute function public.touch_updated_at();
drop trigger if exists touch_team on public.team;
create trigger touch_team before update on public.team for each row execute function public.touch_updated_at();

-- 2. Who is signed in, and what can they do ------------------------------------
create or replace function public.is_company() returns boolean
language sql stable as $$
  select coalesce(lower(auth.jwt()->>'email') like '%@idfreshfood.com', false)
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.team where email = lower(auth.jwt()->>'email')
$$;

create or replace function public.is_admin() returns boolean
language sql stable as $$ select coalesce(public.my_role() = 'admin', false) $$;

create or replace function public.can_edit() returns boolean       -- everyone on the team except viewers
language sql stable as $$ select public.is_company() and coalesce(public.my_role(), 'viewer') <> 'viewer' $$;

alter table public.projects enable row level security;
alter table public.settings enable row level security;
alter table public.team     enable row level security;

drop policy if exists "company reads projects"   on public.projects;
drop policy if exists "company adds projects"    on public.projects;
drop policy if exists "company edits projects"   on public.projects;
drop policy if exists "team reads projects"      on public.projects;
drop policy if exists "team adds projects"       on public.projects;
drop policy if exists "team edits projects"      on public.projects;
create policy "team reads projects" on public.projects for select to authenticated using (public.is_company() and public.my_role() is not null);
create policy "team adds projects"  on public.projects for insert to authenticated with check (public.can_edit());
create policy "team edits projects" on public.projects for update to authenticated using (public.can_edit()) with check (public.can_edit());
-- No delete policy: projects can't be deleted from the app.

drop policy if exists "company reads settings" on public.settings;
drop policy if exists "company adds settings"  on public.settings;
drop policy if exists "company edits settings" on public.settings;
drop policy if exists "team reads settings"    on public.settings;
drop policy if exists "admins add settings"    on public.settings;
drop policy if exists "admins edit settings"   on public.settings;
create policy "team reads settings"  on public.settings for select to authenticated using (public.is_company() and public.my_role() is not null);
create policy "admins add settings"  on public.settings for insert to authenticated with check (public.is_admin());
create policy "admins edit settings" on public.settings for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "team reads team"     on public.team;
drop policy if exists "admins add people"   on public.team;
drop policy if exists "admins edit people"  on public.team;
drop policy if exists "admins remove people" on public.team;
create policy "team reads team"      on public.team for select to authenticated using (public.is_company() and public.my_role() is not null);
create policy "admins add people"    on public.team for insert to authenticated with check (public.is_admin());
create policy "admins edit people"   on public.team for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins remove people" on public.team for delete to authenticated using (public.is_admin() and email <> lower(auth.jwt()->>'email'));

-- Workflow rules enforced by the database, so nobody can bypass the app to
-- approve as someone else, skip approval, or log actions in another person's name.
create or replace function public.my_name() returns text
language sql stable security definer set search_path = public as $$
  select full_name from public.team where email = lower(auth.jwt()->>'email')
$$;

create or replace function public.guard_project_write() returns trigger
language plpgsql set search_path = public as $$
declare
  me_name text := public.my_name();
  me_role text := public.my_role();
  old_doc jsonb := '{}'::jsonb;
  old_ap  jsonb;
  new_ap  jsonb := coalesce(new.doc->'approvals', '{}'::jsonb);
  appr    jsonb := case when jsonb_typeof(new.doc->'approvers') = 'array' then new.doc->'approvers' else '[]'::jsonb end;
  k text; e jsonb; arr text;
begin
  -- The SQL editor, seed scripts and server-side functions are not restricted.
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if me_role is null then raise exception 'You are not on the team list'; end if;
  if me_role = 'admin' then return new; end if;

  if tg_op = 'UPDATE' then
    old_doc := old.doc;
  elsif exists (select 1 from public.projects where id = new.id) then
    return new;  -- upsert of an existing row: the BEFORE UPDATE run of this trigger does the checks
  end if;

  if jsonb_typeof(new_ap) <> 'object' then raise exception 'approvals must be an object'; end if;
  old_ap := coalesce(old_doc->'approvals', '{}'::jsonb);

  -- 1. Approvers are chosen once, from real approvers, and never yourself.
  if tg_op = 'INSERT' then
    if jsonb_array_length(appr) = 0 then raise exception 'Pick at least one approver'; end if;
    if exists (select 1 from jsonb_array_elements_text(appr) a(n)
               where a.n = me_name
                  or not exists (select 1 from public.team t where t.full_name = a.n and t.role in ('approver', 'admin'))) then
      raise exception 'Approvers must be approvers on the team list, and not you';
    end if;
  elsif (old_doc->'approvers') is distinct from (new.doc->'approvers') then
    raise exception 'Only admins can change the approver list';
  end if;

  -- 2. You can only record your own sign-off, as an approver. Clearing all approvals is allowed (new version / request changes).
  if new_ap <> '{}'::jsonb then
    for k in select jsonb_object_keys(old_ap || new_ap) loop
      if (old_ap->k) is distinct from (new_ap->k) and (me_role <> 'approver' or k is distinct from me_name) then
        raise exception 'You can only record your own approval';
      end if;
    end loop;
    if (old_doc->'version') is distinct from (new.doc->'version') then
      raise exception 'A new artwork version must start with no approvals';
    end if;
  end if;

  -- 3. Stages can't be skipped: Final files and Live need every listed approver's sign-off.
  if (new.doc->>'stage') is distinct from (old_doc->>'stage') and (new.doc->>'stage') in ('final', 'live') then
    if tg_op = 'INSERT' then raise exception 'New requests start at Brief or Design'; end if;
    if jsonb_array_length(appr) = 0 then raise exception 'No approvers on this project'; end if;
    if exists (select 1 from jsonb_array_elements_text(appr) a(n) where (new_ap->>a.n) is distinct from 'approved') then
      raise exception 'Artwork needs every approver''s sign-off first';
    end if;
    if (new.doc->>'stage') = 'live' and (old_doc->>'stage') is distinct from 'final' then
      raise exception 'Files go live only from the Final files stage';
    end if;
  end if;

  -- 4. Attribution: requests, notes, activity and files are recorded in your own name.
  if tg_op = 'INSERT' and (new.doc->>'requestedBy') is distinct from me_name then
    raise exception 'Requests must be raised in your own name';
  end if;
  if tg_op = 'UPDATE' and (old_doc->'requestedBy') is distinct from (new.doc->'requestedBy') then
    raise exception 'Only admins can change who raised a request';
  end if;
  foreach arr in array array['notes', 'activity', 'files'] loop
    for e in select x from jsonb_array_elements(coalesce(new.doc->arr, '[]'::jsonb)) x loop
      if not (coalesce(old_doc->arr, '[]'::jsonb) @> jsonb_build_array(e))
         and (e->>'by') is distinct from me_name
         and not (arr = 'activity' and (e->>'by') = 'System') then
        raise exception 'New % entries must be in your own name', arr;
      end if;
    end loop;
  end loop;
  return new;
end $$;

drop trigger if exists guard_project_write on public.projects;
create trigger guard_project_write before insert or update on public.projects
  for each row execute function public.guard_project_write();

-- Old per-person name table from the first version (no longer used).
drop table if exists public.profiles;

-- 3. Invite-only sign-in: only people on the team list can create an account ---
create or replace function public.block_external_signups() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if lower(coalesce(new.email, '')) not like '%@idfreshfood.com' then
    raise exception 'Only @idfreshfood.com email addresses can sign in';
  end if;
  if not exists (select 1 from public.team where email = lower(new.email)) then
    raise exception 'This email hasn''t been added to the Artwork Library yet. Ask an admin to invite you.';
  end if;
  return new;
end $$;
drop trigger if exists block_external_signups on auth.users;
create trigger block_external_signups before insert on auth.users
  for each row execute function public.block_external_signups();

-- 4. File storage (private bucket, 50 MB per file) -----------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('artwork', 'artwork', false, 52428800)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "company reads artwork files"   on storage.objects;
drop policy if exists "company uploads artwork files" on storage.objects;
drop policy if exists "team reads artwork files"      on storage.objects;
drop policy if exists "team uploads artwork files"    on storage.objects;
create policy "team reads artwork files" on storage.objects for select to authenticated
  using (bucket_id = 'artwork' and public.is_company() and public.my_role() is not null);
create policy "team uploads artwork files" on storage.objects for insert to authenticated
  with check (bucket_id = 'artwork' and public.can_edit());

-- 5. Live updates ---------------------------------------------------------------
do $$ begin
  begin alter publication supabase_realtime add table public.projects; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.settings; exception when duplicate_object then null; end;
  -- The team list is not broadcast live (removal events could reveal emails); the app reloads it instead.
  begin alter publication supabase_realtime drop table public.team;    exception when others then null; end;
end $$;

-- 6. Starting data -----------------------------------------------------------------
insert into public.settings (id, doc) values ('brand', '{"palette":[{"name":"iD Fresh Teal","hex":"#037D70"}],"qrDomains":["idfreshfood.com"],"minFontPt":6,"notes":""}')
on conflict (id) do nothing;

-- First admin, so someone can sign in and invite everyone else.
insert into public.team (email, full_name, department, role)
values ('jaspal@idfreshfood.com', 'Jaspal Khalsa', 'Creative', 'admin')
on conflict (email) do update set role = 'admin';
