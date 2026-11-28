-- =====================================================================
--  Vynora Music - Stats Leaderboard, Listening Sessions & Profil
--  Jalankan SELURUH isi file ini di: Supabase Dashboard -> SQL Editor -> Run
--  Jalankan SETELAH supabase/schema.sql. Aman dijalankan ulang (idempotent).
--
--  Tidak mengubah tabel lama (shared_playlists, user_library).
--  Semua penulisan durasi HANYA lewat RPC record_listening_session()
--  (security definer). Role authenticated tidak punya hak INSERT/UPDATE/
--  DELETE langsung ke tabel sesi maupun total, jadi client tidak bisa
--  mengarang durasi. service_role key TIDAK dipakai di aplikasi.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Zona waktu periode (diputuskan backend, bukan client).
--    Minggu berjalan = Senin 00:00, bulan berjalan = tanggal 1 00:00,
--    keduanya menurut zona waktu di bawah. Ubah di SATU tempat ini saja.
-- ---------------------------------------------------------------------
create or replace function public.stats_tz()
returns text language sql immutable as $$ select 'Asia/Jakarta'::text $$;

create or replace function public.stats_period_start(p_period text, p_at timestamptz default now())
returns date language sql stable as $$
  select case p_period
    when 'week'  then date_trunc('week',  p_at at time zone public.stats_tz())::date
    when 'month' then date_trunc('month', p_at at time zone public.stats_tz())::date
    else date '1970-01-01'                       -- 'all'
  end
$$;

-- ---------------------------------------------------------------------
-- 1. Profil publik (menambah data tampilan; auth.users tidak diubah)
-- ---------------------------------------------------------------------
create table if not exists public.profiles (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  display_name  text not null default 'Listener',
  username      text,
  bio           text,
  avatar_url    text,
  accent_color  text,                       -- '#RRGGBB' atau null
  frame         text not null default 'none',
  is_public     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint profiles_display_name_len check (char_length(display_name) between 1 and 30),
  constraint profiles_username_fmt     check (username is null or username ~ '^[a-z0-9_.]{3,20}$'),
  constraint profiles_bio_len          check (bio is null or char_length(bio) <= 160),
  constraint profiles_accent_fmt       check (accent_color is null or accent_color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint profiles_frame_valid      check (frame in ('none','ring','double','soft'))
);
create unique index if not exists profiles_username_uidx
  on public.profiles (lower(username)) where username is not null;

-- Profil otomatis untuk akun baru (termasuk anonim) + backfill akun lama.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
                  'Listener ' || right(new.id::text, 4)), 30)
  )
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function public.handle_new_user();

insert into public.profiles (user_id, display_name)
select u.id,
       left(coalesce(nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
                     nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
                     'Listener ' || right(u.id::text, 4)), 30)
from auth.users u
on conflict (user_id) do nothing;

-- ---------------------------------------------------------------------
-- 2. Sesi mendengarkan (riwayat, hanya bisa ditulis lewat RPC)
-- ---------------------------------------------------------------------
create table if not exists public.listening_sessions (
  id               uuid primary key,                 -- dibuat client, dipakai sbg kunci idempotensi
  user_id          uuid not null references auth.users (id) on delete cascade,
  track_id         text not null,
  track_title      text,
  started_at       timestamptz not null,
  ended_at         timestamptz not null,
  duration_seconds integer not null check (duration_seconds between 1 and 21600),
  status           text not null check (status in ('completed','interrupted')),
  recorded_at      timestamptz not null default now(),
  check (ended_at >= started_at)
);
create index if not exists listening_sessions_user_time_idx
  on public.listening_sessions (user_id, ended_at desc);

-- ---------------------------------------------------------------------
-- 3. Total tersimpan per periode (leaderboard membaca ini, bukan histori)
--    period_type: all | month | week ; period_start: awal periode (tz backend)
-- ---------------------------------------------------------------------
create table if not exists public.listening_totals (
  user_id       uuid not null references auth.users (id) on delete cascade,
  period_type   text not null check (period_type in ('all','month','week')),
  period_start  date not null,
  total_seconds bigint not null default 0 check (total_seconds >= 0),
  reached_at    timestamptz not null default now(),   -- tie-breaker: siapa lebih dulu mencapai total
  updated_at    timestamptz not null default now(),
  primary key (user_id, period_type, period_start)
);
create index if not exists listening_totals_rank_idx
  on public.listening_totals (period_type, period_start, total_seconds desc, reached_at asc);

-- ---------------------------------------------------------------------
-- 4. RLS + hak akses
-- ---------------------------------------------------------------------
alter table public.profiles          enable row level security;
alter table public.listening_sessions enable row level security;
alter table public.listening_totals   enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "sessions_select_own" on public.listening_sessions;
create policy "sessions_select_own" on public.listening_sessions
  for select to authenticated using (user_id = auth.uid());

-- Total tidak sensitif dan dibutuhkan agar Realtime bisa memberi sinyal
-- "ada perubahan" ke semua pendengar. Penulisan tetap hanya lewat RPC.
drop policy if exists "totals_select_authenticated" on public.listening_totals;
create policy "totals_select_authenticated" on public.listening_totals
  for select to authenticated using (true);

revoke all on public.profiles, public.listening_sessions, public.listening_totals from anon, authenticated;
grant select on public.profiles, public.listening_sessions, public.listening_totals to authenticated;

-- ---------------------------------------------------------------------
-- 5. Peringkat internal (dipakai RPC lain, tidak dibuka ke client)
-- ---------------------------------------------------------------------
create or replace function public.stats_rank_of(p_user uuid, p_period text)
returns bigint language plpgsql stable security definer set search_path = public as $$
declare
  ps date := public.stats_period_start(p_period);
  me record;
begin
  select t.total_seconds, t.reached_at into me
  from public.listening_totals t
  where t.user_id = p_user and t.period_type = p_period
    and t.period_start = ps and t.total_seconds > 0;
  if not found then return null; end if;

  return 1 + (
    select count(*) from public.listening_totals o
    where o.period_type = p_period and o.period_start = ps and o.total_seconds > 0
      and (o.total_seconds > me.total_seconds
           or (o.total_seconds = me.total_seconds
               and (o.reached_at < me.reached_at
                    or (o.reached_at = me.reached_at and o.user_id < p_user))))
  );
end $$;
revoke all on function public.stats_rank_of(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 6. RPC: catat sesi mendengarkan (validasi server-side + idempoten)
-- ---------------------------------------------------------------------
create or replace function public.record_listening_session(
  p_session_id       uuid,
  p_track_id         text,
  p_track_title      text,
  p_started_at       timestamptz,
  p_ended_at         timestamptz,
  p_duration_seconds integer,
  p_status           text default 'completed'
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid  uuid := auth.uid();
  n    integer;
  per  text;
  ps   date;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_session_id is null or coalesce(trim(p_track_id), '') = '' then
    return jsonb_build_object('accepted', false, 'reason', 'invalid');
  end if;
  if p_status not in ('completed', 'interrupted') then
    return jsonb_build_object('accepted', false, 'reason', 'invalid_status');
  end if;
  if p_started_at is null or p_ended_at is null or p_duration_seconds is null
     or p_duration_seconds < 1 or p_duration_seconds > 21600 then
    return jsonb_build_object('accepted', false, 'reason', 'invalid_duration');
  end if;
  if p_ended_at < p_started_at then
    return jsonb_build_object('accepted', false, 'reason', 'invalid_range');
  end if;
  if p_ended_at > now() + interval '1 minute' then
    return jsonb_build_object('accepted', false, 'reason', 'future');
  end if;
  if p_started_at < now() - interval '3 days' then
    return jsonb_build_object('accepted', false, 'reason', 'stale');
  end if;
  -- Durasi diputar tidak boleh melebihi rentang waktu dinding (toleransi 5 dtk).
  if p_duration_seconds > extract(epoch from (p_ended_at - p_started_at)) + 5 then
    return jsonb_build_object('accepted', false, 'reason', 'duration_exceeds_span');
  end if;

  -- Sesi yang sama tidak boleh dikirim ulang.
  if exists (select 1 from public.listening_sessions where id = p_session_id) then
    return jsonb_build_object('accepted', false, 'reason', 'duplicate');
  end if;

  -- Satu pengguna tidak bisa mendengarkan dua hal bersamaan: tolak sesi yang
  -- tumpang tindih (>5 dtk) dengan sesi miliknya yang sudah tercatat.
  if exists (
    select 1 from public.listening_sessions s
    where s.user_id = uid
      and s.started_at < p_ended_at   - interval '5 seconds'
      and s.ended_at   > p_started_at + interval '5 seconds'
  ) then
    return jsonb_build_object('accepted', false, 'reason', 'overlap');
  end if;

  insert into public.listening_sessions
    (id, user_id, track_id, track_title, started_at, ended_at, duration_seconds, status)
  values
    (p_session_id, uid, left(p_track_id, 200), left(p_track_title, 200),
     p_started_at, p_ended_at, p_duration_seconds, p_status)
  on conflict (id) do nothing;
  get diagnostics n = row_count;
  if n = 0 then
    return jsonb_build_object('accepted', false, 'reason', 'duplicate');
  end if;

  -- Periode ditentukan oleh waktu SELESAI sesi (zona waktu backend).
  foreach per in array array['all', 'month', 'week'] loop
    ps := public.stats_period_start(per, p_ended_at);
    insert into public.listening_totals as t
      (user_id, period_type, period_start, total_seconds, reached_at, updated_at)
    values (uid, per, ps, p_duration_seconds, now(), now())
    on conflict (user_id, period_type, period_start) do update
      set total_seconds = t.total_seconds + excluded.total_seconds,
          reached_at    = now(),
          updated_at    = now();
  end loop;

  return jsonb_build_object('accepted', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. Snapshot peringkat (untuk indikator naik/turun yang tersimpan di server)
--    Tanpa pg_cron: klien memanggil touch_rank_snapshot(); snapshot baru
--    dibuat paling sering 1x/24 jam per periode. Indikator = peringkat pada
--    snapshot terbaru yang umurnya >= 12 jam, dikurangi peringkat sekarang.
-- ---------------------------------------------------------------------
create table if not exists public.listening_rank_snapshots (
  period_type  text        not null check (period_type in ('all','month','week')),
  period_start date        not null,
  gen_at       timestamptz not null,
  user_id      uuid        not null references auth.users (id) on delete cascade,
  rank         integer     not null,
  primary key (period_type, period_start, gen_at, user_id)
);
alter table public.listening_rank_snapshots enable row level security;
revoke all on public.listening_rank_snapshots from anon, authenticated;  -- hanya via fungsi definer

create or replace function public.touch_rank_snapshot(p_period text default 'all')
returns void language plpgsql security definer set search_path = public as $$
declare ps date;
begin
  if auth.uid() is null or p_period not in ('all', 'month', 'week') then return; end if;
  ps := public.stats_period_start(p_period);
  perform pg_advisory_xact_lock(hashtext('rank_snapshot_' || p_period));
  if exists (select 1 from public.listening_rank_snapshots
             where period_type = p_period and period_start = ps
               and gen_at > now() - interval '24 hours') then
    return;
  end if;
  insert into public.listening_rank_snapshots (period_type, period_start, gen_at, user_id, rank)
  select p_period, ps, now(), t.user_id,
         (row_number() over (order by t.total_seconds desc, t.reached_at asc, t.user_id asc))::int
  from public.listening_totals t
  where t.period_type = p_period and t.period_start = ps and t.total_seconds > 0;
  delete from public.listening_rank_snapshots where gen_at < now() - interval '8 days';
end $$;

-- ---------------------------------------------------------------------
-- 8. RPC: leaderboard (paginasi) & peringkat sendiri
--    p_period: all | month | week. p_limit maks 100, p_offset >= 0.
--    prev_rank = peringkat pada snapshot pembanding (null = belum ada data).
--    Profil privat: username & foto disembunyikan dari pengguna lain.
-- ---------------------------------------------------------------------
drop function if exists public.get_leaderboard(text, integer);
drop function if exists public.get_my_rank(text);

create or replace function public.get_leaderboard(
  p_period text default 'all', p_limit integer default 50, p_offset integer default 0)
returns table (
  rank          bigint,
  user_id       uuid,
  display_name  text,
  username      text,
  avatar_url    text,
  accent_color  text,
  frame         text,
  is_public     boolean,
  total_seconds bigint,
  prev_rank     integer
)
language sql stable security definer set search_path = public as $$
  with cur as (select public.stats_period_start(p_period) as ps),
  base as (
    select max(s.gen_at) as gen_at
    from public.listening_rank_snapshots s, cur
    where s.period_type = p_period and s.period_start = cur.ps
      and s.gen_at <= now() - interval '12 hours'
  ),
  ranked as (
    select row_number() over (order by t.total_seconds desc, t.reached_at asc, t.user_id asc) as rnk,
           t.user_id, t.total_seconds
    from public.listening_totals t, cur
    where p_period in ('all', 'month', 'week')
      and t.period_type = p_period and t.period_start = cur.ps and t.total_seconds > 0
  )
  select r.rnk as rank,
         r.user_id,
         p.display_name,
         case when p.is_public or r.user_id = auth.uid() then p.username   end,
         case when p.is_public or r.user_id = auth.uid() then p.avatar_url end,
         p.accent_color,
         p.frame,
         p.is_public,
         r.total_seconds,
         s.rank as prev_rank
  from ranked r
  join public.profiles p on p.user_id = r.user_id
  left join public.listening_rank_snapshots s
         on s.period_type = p_period
        and s.period_start = (select ps from cur)
        and s.gen_at = (select gen_at from base)
        and s.user_id = r.user_id
  order by r.rnk
  limit least(greatest(coalesce(p_limit, 50), 1), 100)
  offset greatest(coalesce(p_offset, 0), 0)
$$;

create or replace function public.get_my_rank(p_period text default 'all')
returns table (
  rank          bigint,
  user_id       uuid,
  display_name  text,
  username      text,
  avatar_url    text,
  accent_color  text,
  frame         text,
  is_public     boolean,
  total_seconds bigint,
  prev_rank     integer
)
language plpgsql stable security definer set search_path = public as $$
declare
  ps date;
  g  timestamptz;
begin
  if auth.uid() is null or p_period not in ('all', 'month', 'week') then
    return;
  end if;
  ps := public.stats_period_start(p_period);
  select max(s.gen_at) into g from public.listening_rank_snapshots s
   where s.period_type = p_period and s.period_start = ps
     and s.gen_at <= now() - interval '12 hours';
  return query
  select public.stats_rank_of(auth.uid(), p_period),
         p.user_id, p.display_name, p.username, p.avatar_url,
         p.accent_color, p.frame, p.is_public, t.total_seconds,
         (select s.rank from public.listening_rank_snapshots s
           where s.period_type = p_period and s.period_start = ps
             and s.gen_at = g and s.user_id = auth.uid())
  from public.listening_totals t
  join public.profiles p on p.user_id = t.user_id
  where t.user_id = auth.uid()
    and t.period_type = p_period
    and t.period_start = ps
    and t.total_seconds > 0;
end $$;

-- ---------------------------------------------------------------------
-- 9. RPC: profil (diri sendiri / pengguna lain, mengikuti privasi)
-- ---------------------------------------------------------------------
create or replace function public.ensure_my_profile()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.profiles (user_id, display_name)
  select u.id,
         left(coalesce(nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
                       nullif(trim(u.raw_user_meta_data ->> 'name'), ''),
                       'Listener ' || right(u.id::text, 4)), 30)
  from auth.users u where u.id = auth.uid()
  on conflict (user_id) do nothing;
end $$;

create or replace function public.get_user_profile(p_user_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  target  uuid := coalesce(p_user_id, auth.uid());
  is_self boolean := (coalesce(p_user_id, auth.uid()) = auth.uid());
  prof    public.profiles%rowtype;
  tot_all bigint; tot_month bigint; tot_week bigint; sess_count bigint;
begin
  if auth.uid() is null or target is null then return null; end if;
  select * into prof from public.profiles where user_id = target;
  if not found then return null; end if;

  if not is_self and not prof.is_public then
    return jsonb_build_object(
      'user_id', prof.user_id, 'display_name', prof.display_name,
      'accent_color', prof.accent_color, 'frame', prof.frame,
      'is_public', false, 'is_self', false);
  end if;

  select coalesce(sum(total_seconds) filter (where period_type = 'all'), 0),
         coalesce(sum(total_seconds) filter (where period_type = 'month'
                    and period_start = public.stats_period_start('month')), 0),
         coalesce(sum(total_seconds) filter (where period_type = 'week'
                    and period_start = public.stats_period_start('week')), 0)
    into tot_all, tot_month, tot_week
  from public.listening_totals where user_id = target;

  select count(*) into sess_count from public.listening_sessions where user_id = target;

  return jsonb_build_object(
    'user_id', prof.user_id, 'display_name', prof.display_name,
    'username', prof.username, 'bio', prof.bio, 'avatar_url', prof.avatar_url,
    'accent_color', prof.accent_color, 'frame', prof.frame,
    'is_public', prof.is_public, 'is_self', is_self,
    'member_since', prof.created_at,
    'total_all', tot_all, 'total_month', tot_month, 'total_week', tot_week,
    'rank_all',   public.stats_rank_of(target, 'all'),
    'rank_month', public.stats_rank_of(target, 'month'),
    'rank_week',  public.stats_rank_of(target, 'week'),
    'sessions', sess_count);
end $$;

-- Ubah profil sendiri. p_patch hanya berisi kunci yang ingin diubah:
-- display_name, username, bio, avatar_url, accent_color, frame, is_public.
-- Nilai null / '' pada username, bio, avatar_url, accent_color = hapus.
create or replace function public.update_my_profile(p_patch jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  v   text;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  insert into public.profiles (user_id) values (uid) on conflict (user_id) do nothing;

  if p_patch ? 'display_name' then
    v := trim(coalesce(p_patch ->> 'display_name', ''));
    if char_length(v) not between 1 and 30 then
      raise exception 'display_name must be 1-30 characters';
    end if;
    update public.profiles set display_name = v where user_id = uid;
  end if;

  if p_patch ? 'username' then
    v := lower(trim(coalesce(p_patch ->> 'username', '')));
    if v = '' then
      update public.profiles set username = null where user_id = uid;
    else
      if v !~ '^[a-z0-9_.]{3,20}$' then
        raise exception 'username must be 3-20 chars: a-z, 0-9, _ or .';
      end if;
      if exists (select 1 from public.profiles where lower(username) = v and user_id <> uid) then
        raise exception 'username already taken' using errcode = '23505';
      end if;
      update public.profiles set username = v where user_id = uid;
    end if;
  end if;

  if p_patch ? 'bio' then
    v := trim(coalesce(p_patch ->> 'bio', ''));
    if char_length(v) > 160 then raise exception 'bio max 160 characters'; end if;
    update public.profiles set bio = nullif(v, '') where user_id = uid;
  end if;

  if p_patch ? 'avatar_url' then
    v := trim(coalesce(p_patch ->> 'avatar_url', ''));
    if v <> '' and position('/avatars/' || uid::text || '/' in v) = 0 then
      raise exception 'avatar must be stored in your own avatars folder';
    end if;
    update public.profiles set avatar_url = nullif(v, '') where user_id = uid;
  end if;

  if p_patch ? 'accent_color' then
    v := trim(coalesce(p_patch ->> 'accent_color', ''));
    if v <> '' and v !~ '^#[0-9A-Fa-f]{6}$' then
      raise exception 'accent_color must be #RRGGBB';
    end if;
    update public.profiles set accent_color = nullif(v, '') where user_id = uid;
  end if;

  if p_patch ? 'frame' then
    v := coalesce(p_patch ->> 'frame', 'none');
    if v not in ('none', 'ring', 'double', 'soft') then
      raise exception 'invalid frame';
    end if;
    update public.profiles set frame = v where user_id = uid;
  end if;

  if p_patch ? 'is_public' then
    update public.profiles set is_public = coalesce((p_patch ->> 'is_public')::boolean, true)
    where user_id = uid;
  end if;

  update public.profiles set updated_at = now() where user_id = uid;
  return public.get_user_profile(uid);
end $$;

-- Hak eksekusi: hanya role authenticated (termasuk login anonim aplikasi).
revoke all on function public.record_listening_session(uuid, text, text, timestamptz, timestamptz, integer, text) from public, anon;
revoke all on function public.get_leaderboard(text, integer, integer) from public, anon;
revoke all on function public.touch_rank_snapshot(text)       from public, anon;
revoke all on function public.get_my_rank(text)               from public, anon;
revoke all on function public.ensure_my_profile()             from public, anon;
revoke all on function public.get_user_profile(uuid)          from public, anon;
revoke all on function public.update_my_profile(jsonb)        from public, anon;
grant execute on function public.record_listening_session(uuid, text, text, timestamptz, timestamptz, integer, text) to authenticated;
grant execute on function public.get_leaderboard(text, integer, integer) to authenticated;
grant execute on function public.touch_rank_snapshot(text)       to authenticated;
grant execute on function public.get_my_rank(text)               to authenticated;
grant execute on function public.ensure_my_profile()             to authenticated;
grant execute on function public.get_user_profile(uuid)          to authenticated;
grant execute on function public.update_my_profile(jsonb)        to authenticated;

-- ---------------------------------------------------------------------
-- 10. Realtime: hanya listening_totals (sinyal "leaderboard berubah").
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'listening_totals'
  ) then
    alter publication supabase_realtime add table public.listening_totals;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 11. Storage: bucket foto profil (maks 2 MB, jpeg/png/webp).
--     Tiap pengguna hanya boleh menulis di folder miliknya: avatars/<uid>/...
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "avatars_read"        on storage.objects;
drop policy if exists "avatars_insert_own"  on storage.objects;
drop policy if exists "avatars_update_own"  on storage.objects;
drop policy if exists "avatars_delete_own"  on storage.objects;

create policy "avatars_read" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
