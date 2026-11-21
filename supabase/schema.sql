-- =====================================================================
--  HokTifyy - skema database Supabase
--  Jalankan SELURUH isi file ini di: Supabase Dashboard -> SQL Editor -> Run
--  Aman dijalankan ulang (idempotent).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Tabel playlist bersama
--    (dipakai lib/services/supabase_playlist_service.dart)
-- ---------------------------------------------------------------------
create table if not exists public.shared_playlists (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,                                  -- kode 6 karakter untuk join
  title       text not null,
  owner_id    uuid not null references auth.users (id) on delete cascade,
  members     uuid[] not null default '{}',                          -- daftar user id anggota
  songs       jsonb  not null default '[]'::jsonb,                   -- [{id,title,artist,thumbnailUrl,durationMs}]
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists shared_playlists_members_idx
  on public.shared_playlists using gin (members);

-- ---------------------------------------------------------------------
-- 2. Row Level Security
--    Aplikasi memakai anon key, jadi RLS WAJIB aktif.
-- ---------------------------------------------------------------------
alter table public.shared_playlists enable row level security;

drop policy if exists "playlist_select_authenticated" on public.shared_playlists;
drop policy if exists "playlist_insert_owner"         on public.shared_playlists;
drop policy if exists "playlist_update_authenticated" on public.shared_playlists;
drop policy if exists "playlist_delete_owner"         on public.shared_playlists;

-- Semua user yang login boleh mencari playlist berdasarkan kode (perlu untuk "join").
create policy "playlist_select_authenticated"
  on public.shared_playlists for select
  to authenticated
  using (true);

-- Hanya boleh membuat playlist atas nama sendiri.
create policy "playlist_insert_owner"
  on public.shared_playlists for insert
  to authenticated
  with check (owner_id = auth.uid() and auth.uid() = any (members));

-- Update diizinkan untuk user login; aturan detailnya dijaga trigger di bawah.
create policy "playlist_update_authenticated"
  on public.shared_playlists for update
  to authenticated
  using (true)
  with check (true);

-- Hanya pemilik yang boleh menghapus.
create policy "playlist_delete_owner"
  on public.shared_playlists for delete
  to authenticated
  using (owner_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. Trigger penjaga update
--    - non-member : hanya boleh menambahkan DIRINYA SENDIRI ke members (join)
--    - member     : boleh mengubah songs (tambah lagu) + join
--    - owner      : boleh mengubah semuanya kecuali id/code/owner_id
-- ---------------------------------------------------------------------
create or replace function public.shared_playlists_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- kolom ini tidak boleh berubah oleh siapa pun
  if new.id is distinct from old.id
     or new.code is distinct from old.code
     or new.owner_id is distinct from old.owner_id then
    raise exception 'id, code and owner_id are immutable';
  end if;

  if uid <> old.owner_id then
    -- title hanya boleh diubah owner
    if new.title is distinct from old.title then
      raise exception 'only owner can rename playlist';
    end if;

    -- members: hanya boleh menambah diri sendiri
    if new.members is distinct from old.members then
      if not (new.members @> old.members
              and array_length(new.members, 1) = coalesce(array_length(old.members, 1), 0) + 1
              and uid = any (new.members)
              and not (uid = any (old.members))) then
        raise exception 'you may only add yourself to members';
      end if;
    end if;

    -- songs: hanya anggota (atau yang baru saja join di update yang sama)
    if new.songs is distinct from old.songs then
      if not (uid = any (old.members)) then
        raise exception 'only members can edit songs';
      end if;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists shared_playlists_guard_trg on public.shared_playlists;
create trigger shared_playlists_guard_trg
  before update on public.shared_playlists
  for each row execute function public.shared_playlists_guard();

-- ---------------------------------------------------------------------
-- 4. Realtime
--    Dibutuhkan agar playlist bersama ter-update langsung di semua perangkat
--    (supabase_flutter: .from('shared_playlists').stream(...)).
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shared_playlists'
  ) then
    alter publication supabase_realtime add table public.shared_playlists;
  end if;
end $$;

-- Catatan: fitur "Party Room" memakai Realtime *Broadcast* (channel party_<kode>),
-- tidak butuh tabel. Pastikan Realtime aktif di Project Settings -> API.
