# NOTICE — Atribusi & Lisensi

**Vynora Music** adalah turunan (modified version) dari **StreamBeats**.

| Peran | Pihak |
|---|---|
| Proyek asli — *StreamBeats* | Copyright (C) 2026 **DuskCipher** (<https://github.com/DuskCipher>) |
| Source code / distribusi yang menjadi dasar | **Valora Official** (Valora Official Grup) |
| Rebrand ke *Vynora Music*, integrasi Supabase, build APK | 21 November 2026 |

## Lisensi

Seluruh proyek tetap berlisensi **GNU General Public License v2 (atau versi lebih baru)**.
Teks lengkap ada di berkas [`LICENSE`](LICENSE) dan **tidak boleh dihapus atau diubah**.
Kredit *Valora Official* di layar splash (`lib/main.dart`), halaman "Tentang"
(`lib/screens/screen/home_views/setting_views/about.dart`) dan `windows/installer.iss`
sengaja dipertahankan.

Sesuai GPL v2 pasal 2(a), berikut pemberitahuan perubahan:

## Daftar perubahan (21 Nov 2026)

- Nama aplikasi **StreamBeats → Vynora Music** (teks UI, label Android/iOS, string lokalisasi).
- Ikon aplikasi diganti (Android, iOS, macOS, Windows) dan aset `assets/icons/hoktifyy_*.png`.
- Application ID **`ls.streambeats.musicplayer` → `com.hoktifyy.app`**.
- Supabase tidak lagi hardcode; kini dikonfigurasi lewat `--dart-define`
  (`lib/core/config/app_config.dart`). Ditambahkan `supabase/schema.sql` (tabel + RLS + trigger + realtime).
- Pengecekan update dialihkan ke GitHub Releases repo sendiri (bukan server upstream).
- Workflow `.github/workflows/build-apk.yml` (khusus Android) menggantikan `main.yml` multi-OS.
- Ditambahkan skrip Termux (`termux/`) dan dokumentasi (`PANDUAN_INSTALASI.md`, `README.md`).
- Nama paket Dart internal (`streambeats`), nama kelas, dan crate Rust **sengaja tidak diubah**
  agar kode tetap konsisten dengan kode yang di-generate.

Karena berlisensi GPL, jika kamu mendistribusikan APK Vynora Music ke orang lain,
sediakan juga source code-nya (cukup dengan repo GitHub publik).
