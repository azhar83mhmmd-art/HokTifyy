# Changelog HokTifyy

## [2.0.0] - 2026-11-24

### Added
- **Pencarian baru bergaya "Getaran"**: beranda pencarian dengan kartu suasana bergaya masonry (Hip Hop & Rap, Pop, Santai, Elektronik, R&B, Pesta). Sekali ketuk langsung mencari lagu sesuai suasana.
- Panel **Lebih Banyak Suasana & Wilayah** (Pop Indonesia, K-Pop & J-Pop, Indie Akustik, Gas Olahraga, Nyetir Malam, Fokus & Belajar).
- Panel **Pencarian Terbaru** + tombol Hapus semua riwayat, dan pintasan riwayat cepat di samping judul Getaran.
- Header merek HokTifyy (logo + gradasi ungu) dengan tombol Pengaturan, serta tombol kembali ke Getaran saat melihat hasil.
- Pemilih lingkup **Online / Perpustakaan Lokal** (Lokal membuka tab musik lokal).
- Kartu Getaran memakai foto artis (dikompres, sekitar 0,5 MB total) dengan seni kontur sebagai cadangan bila gambar gagal dimuat.

### Changed
- Kotak pencarian jadi pil penuh dengan placeholder baru; filter (Semua/Track/Album/Artist/Playlist) hanya muncul saat melihat hasil.
- Baris **Sumber** (ytmusic/ytvideo) dibuat satu garis ringkas.
- Teks pada chip filter terpilih diperjelas (kontras lebih baik).
- Versi aplikasi naik dari 1.0.0 menjadi **2.0.0**.

---

## [1.0.0] - 2026-11-21

### Changed
- Rebrand dari StreamBeats menjadi **HokTifyy** dengan ikon baru (berbasis StreamBeats © DuskCipher, source by Valora Official, GPL v2+).
- Application ID menjadi `com.hoktifyy.app`.
- Supabase kini dikonfigurasi lewat `--dart-define` / GitHub Secrets (tanpa key hardcode); skema SQL tersedia di `supabase/schema.sql`.
- Cek update memakai GitHub Releases repo sendiri.

### Added
- Layar login awal (email + kata sandi, Google, tamu), responsif HP/tablet; lupa kata sandi lewat email.
- Playlist bersama & Party otomatis memakai login anonim Supabase (tanpa wajib Google).
- Pop-up update punya tombol "Nanti"; nomor build naik otomatis tiap build GitHub.
- Workflow GitHub Actions untuk build APK dan skrip Termux (`termux/`) untuk setup, build, dan install.

---
_Riwayat di bawah ini berasal dari StreamBeats (proyek asal)._

## [3.2.7] - 2026-10-07

### Added
- **Multi-Platform Support**: Rilis resmi untuk Android, Windows 10/11, Linux, macOS, dan iOS.
- **Dedicated Android APKs**: Varian arm64-v8a (modern 64-bit), universal, armeabi-v7a (32-bit), dan x86_64.
- **Tanda Tangan Resmi V1 & V2**: Menjamin instalasi lancar di semua tipe Android tanpa error paket rusak.
- **Arsip Multi-OS Standalone**: Paket installer Windows (.exe & .zip), Linux (.tar.gz), macOS (.dmg & .zip), dan iOS (.ipa).

### Changed
- Peningkatan stabilitas sistem pembaruan dan perbaikan parser changelog in-app.
- Optimasi pemutaran musik di latar belakang dan notifikasi audio.
- Pembaruan sistem sinkronisasi lirik karaoke offline dan unduhan cepat.

## [3.2.6] - 2026-10-07

### Added
- **Multi-Platform Support**: Rilis resmi untuk Android, Windows 10/11, Linux, macOS, dan iOS.
- **Dedicated Android APKs**: Varian arm64-v8a (modern 64-bit), universal, armeabi-v7a (32-bit), dan x86_64.
- **Tanda Tangan Resmi V1 & V2**: Menjamin instalasi lancar di semua tipe Android tanpa error paket rusak.
- **Arsip Linux Standalone**: Paket bundle `.tar.gz` untuk distribusi Linux x64.

### Changed
- Peningkatan pemutaran musik di latar belakang dan integrasi notifikasi audio.
- Pembaruan sistem sinkronisasi lirik karaoke offline dan unduhan batch cepat.
- Optimalisasi deteksi jaringan dan auto-recovery stream.

## [Unreleased]

### Changed
- **UI/UX Enhancements**:
    - Updated app logo and high-resolution icons.
    - Improved themes, glassmorphism, and color schemes.
    - Redesigned and updated the "About" page to include build number.
    - Enhanced Android notification media artwork.
- **Dependencies**: Upgraded Flutter, `flutter_bloc`, and Android Gradle Plugin.

## [2.11.6] - 2025-05-05

### Changed
- Refactored import/export playlist functionality.

### Fixed
- Resolved issues with plugin-based streaming.
- Addressed bugs related to imported provider playlists.

## Patch 7
- Sinkron otomatis lagu disukai + playlist (termasuk hasil impor) ke Supabase per akun (`user_library`); digabung saat login.
- Keluar akun tidak menyentuh data lokal; layar login muncul lagi di pembukaan berikutnya (tidak perlu "hapus data aplikasi").

## Patch 8
- Ikon aplikasi baru (arch + play), latar #1B1A20.
- Halaman Tentang: hapus Telegram & Valora Store, partner "SANN404GRUP & Azhar", link Saluran WhatsApp baru.
- Sisa nama StreamBeats/BloomeTunes yang terlihat pengguna diganti HokTifyy (nama file ekspor, kanal notifikasi, Discord).

## Patch 9
- Impor playlist besar (300+ lagu) tidak lagi "Timed out fetching tracks" (timeout 10 dtk -> 5 menit), penyimpanan per batch.

## Patch 10
- Tema bergaya Sonara/Material 3: palet tonal violet, font Inter, pill navigasi aktif, bottom bar kaca mengambang.
- Logo aplikasi tetap memakai logo APK (busur + play) di semua tempat.

## Patch 12
- Beranda: header (tombol menu tonal, sapaan tanpa emoji, judul lebih besar), search bar pill + tombol filter tonal, kartu hero playlist pilihan (kaca, tombol "Putar sekarang" warna tonal, tanpa huruf kapital semua).

## Patch 13
- Ciri khas HokTifyy: motif lengkung (ArchGlyph) pada judul bagian, tombol "Lihat semua" berbentuk pil, ekualiser beranimasi untuk lagu yang sedang diputar, baris lagu aktif bertinta ungu, kartu lebih membulat; label vertikal diganti judul horizontal.

## Patch 14
- UI mengikuti Sonara lebih dekat: latar hitam murni, judul "Beranda" besar + avatar inisial, judul bagian tebal dengan panah, kartu hero editorial (label "Dengarkan sekarang"), cover persegi lebih besar bersudut 14, daftar lagu dengan garis tipis.

## Patch 15
- Logo/ikon aplikasi diganti: not musik + tombol play + gelombang suara (putih di latar hitam).
