# Changelog HokTifyy

## [1.0.0] - 2026-11-21

### Changed
- Rebrand dari StreamBeats menjadi **HokTifyy** dengan ikon baru (berbasis StreamBeats © DuskCipher, source by Valora Official, GPL v2+).
- Application ID menjadi `com.hoktifyy.app`.
- Supabase kini dikonfigurasi lewat `--dart-define` / GitHub Secrets (tanpa key hardcode); skema SQL tersedia di `supabase/schema.sql`.
- Cek update memakai GitHub Releases repo sendiri.

### Added
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
