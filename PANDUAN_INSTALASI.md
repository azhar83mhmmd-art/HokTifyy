# Panduan Instalasi HokTifyy (Termux + GitHub Actions + Supabase)

> **Cara kerjanya:** Flutter + Rust **tidak bisa dikompilasi langsung di Termux** (tidak ada SDK Flutter resmi untuk Android, dan build butuh Android NDK + Rust). Karena itu:
>
> 1. **GitHub Actions** yang meng-compile APK (gratis, ±15–30 menit).
> 2. **Termux** dipakai untuk: upload source → isi secrets → memicu build → mengunduh & memasang APK.
> 3. **Supabase** menjadi database cloud (playlist bersama, party room, login).
>
> Semua dilakukan dari HP. Tidak perlu PC.

---

## Daftar isi

1. [Yang dibutuhkan](#1-yang-dibutuhkan)
2. [Siapkan Supabase](#2-siapkan-supabase)
3. [Siapkan Termux](#3-siapkan-termux)
4. [Setup sekali jalan](#4-setup-sekali-jalan-termuxsetupsh)
5. [Build & install APK](#5-build--install-apk)
6. [Login Google (opsional)](#6-login-google-opsional)
7. [Update aplikasi](#7-update-aplikasi)
8. [Cara manual (tanpa skrip)](#8-cara-manual-tanpa-skrip)
9. [Masalah umum](#9-masalah-umum)
10. [Lisensi](#10-lisensi)

---

## 1. Yang dibutuhkan

| Kebutuhan | Keterangan |
|---|---|
| HP Android 5.0+ | RAM bebas ≥ 2 GB, ruang ±500 MB |
| Termux | Pasang dari **F-Droid** atau GitHub Releases Termux. *Versi Play Store sudah usang, jangan dipakai.* |
| Termux:API (opsional) | Dari F-Droid; membuat `termux-open` & wake-lock lebih andal |
| Akun GitHub | <https://github.com/signup> |
| Akun Supabase | <https://supabase.com> (gratis) |

---

## 2. Siapkan Supabase

### 2.1 Buat project
1. Login <https://supabase.com/dashboard> → **New project**.
2. Isi nama (mis. `hoktifyy`), password database (simpan), pilih region terdekat (Singapore).
3. Tunggu sampai status project *Healthy*.

### 2.2 Buat tabel
1. Menu **SQL Editor** → **New query**.
2. Buka file [`supabase/schema.sql`](supabase/schema.sql), **salin seluruh isinya**, tempel, tekan **Run**.
3. Pastikan muncul *Success*. Skrip ini membuat tabel `shared_playlists`, aturan keamanan (RLS), trigger penjaga, dan mengaktifkan Realtime. Aman dijalankan ulang.

### 2.3 Ambil URL & key
Menu **Project Settings → API**:

| Nilai | Dipakai sebagai |
|---|---|
| **Project URL** (`https://xxxx.supabase.co`) | `SUPABASE_URL` |
| **anon public** key | `SUPABASE_ANON_KEY` |

> ⚠️ Pakai **anon** key. **Jangan pernah** memakai `service_role` key di aplikasi.

### 2.4 Aktifkan Realtime
**Project Settings → API → Realtime** harus aktif (default aktif). Fitur *Party Room* memakai Realtime Broadcast.

---

## 3. Siapkan Termux

Buka Termux, lalu:

```bash
pkg update -y && pkg upgrade -y
pkg install -y git unzip
termux-setup-storage          # izinkan akses penyimpanan
```

Salin source ke Termux. Pilih salah satu:

**A. Dari zip di HP** (mis. `HokTifyy-source.zip` ada di folder Download):
```bash
cd ~
unzip ~/storage/downloads/HokTifyy-source.zip
cd HokTifyy
```

**B. Dari repo yang sudah ada:**
```bash
git clone https://github.com/USERNAME/HokTifyy
cd HokTifyy
```

---

## 4. Setup sekali jalan (`termux/setup.sh`)

```bash
bash termux/setup.sh
```

Skrip akan menanyakan/ mengerjakan berurutan:

1. Memasang `git`, `gh` (GitHub CLI), `openjdk-17`, `jq`, `termux-api`, `openssl`.
2. **Login GitHub** — pilih *GitHub.com → HTTPS → Login with a web browser*. Salin kode 8 karakter, buka link di browser HP, masukkan kode, setujui.
3. Membuat repo (default `HokTifyy`, **public**) dan meng-upload source.
   *Public disarankan:* lisensi GPL mewajibkan source tersedia bagi penerima APK, dan fitur cek-update di dalam aplikasi hanya bisa membaca release repo public.
4. Meminta `SUPABASE_URL`, `SUPABASE_ANON_KEY` (dari langkah 2.3) dan `GOOGLE_WEB_CLIENT_ID` (boleh kosong dulu) → disimpan sebagai **GitHub Secrets**.
5. Membuat **keystore** penanda-tangan APK di `~/.hoktifyy-keystore/` dan mengunggahnya sebagai secret.

> 🔐 **Backup `~/.hoktifyy-keystore/`** (salin ke Download / simpan di tempat aman).
> Jika keystore hilang atau berubah, APK baru **tidak bisa menimpa** versi lama — harus uninstall dulu (data lokal ikut hilang).

Di akhir, skrip menawarkan langsung menjalankan build.

---

## 5. Build & install APK

```bash
bash termux/build.sh
```

Yang terjadi:
1. Perubahan terbaru di-push ke GitHub.
2. Workflow **Build HokTifyy APK** dijalankan; Termux memantau progresnya (`gh run watch`).
3. Setelah sukses, `termux/install.sh` mengunduh APK sesuai arsitektur HP (arm64-v8a / x86_64 / universal), menyalin ke folder **Download**, lalu membuka installer Android.
4. Jika diminta, aktifkan **"Izinkan dari sumber ini"** untuk Termux → tekan **Install**.

Pantau juga lewat browser: `https://github.com/USERNAME/HokTifyy/actions`.

### Hanya install (tanpa build) — mis. di HP lain
```bash
pkg install -y curl jq
curl -fsSL https://raw.githubusercontent.com/USERNAME/HokTifyy/main/termux/install.sh | bash -s -- USERNAME/HokTifyy
```
atau buka tab **Releases** di repo dan unduh APK langsung dari browser:

| File | Untuk |
|---|---|
| `HokTifyy-android-arm64-v8a.apk` | HP modern (hampir semua HP sejak ±2017) |
| `HokTifyy-android-armeabi-v7a.apk` | HP 32-bit lama |
| `HokTifyy-android-x86_64.apk` | Emulator / Chromebook |
| `HokTifyy-android-universal.apk` | **Bingung? pilih ini** (lebih besar, cocok di semua) |

---

## 6. Login Google (opsional)

Pemutar musik berjalan **tanpa login**. Login hanya dibutuhkan untuk *playlist bersama* dan *party room*.

1. **Google Cloud Console** → buat project → *APIs & Services → OAuth consent screen* (External).
2. *Credentials → Create credentials → OAuth client ID*:
   - **Web application** → catat **Client ID** dan **Client secret**.
   - **Android** → Package name `com.hoktifyy.app`, SHA-1 dari keystore kamu:
     ```bash
     source ~/.hoktifyy-keystore/credentials.txt
     keytool -list -v -keystore ~/.hoktifyy-keystore/hoktifyy.jks -alias hoktifyy -storepass "$STORE_PASSWORD" | grep SHA1
     ```
3. **Supabase → Authentication → Providers → Google**: aktifkan, isi Client ID & Secret (dari *Web application*). Jika muncul error nonce, aktifkan **Skip nonce checks**.
4. Simpan Client ID *Web* sebagai secret:
   ```bash
   gh secret set GOOGLE_WEB_CLIENT_ID -R USERNAME/HokTifyy -b "xxxx.apps.googleusercontent.com"
   ```
5. Build ulang: `bash termux/build.sh`.

---

## 7. Update aplikasi

1. Ubah versi di `pubspec.yaml`, mis. `version: 1.0.1+2` (angka setelah `+` **harus naik**).
2. `bash termux/build.sh` — release baru bernama tag `v1.0.1+2`.
3. Aplikasi yang sudah terpasang akan menampilkan dialog **Pembaruan tersedia** (cek update membaca release terbaru repo kamu).

Mengubah secret (mis. ganti project Supabase):
```bash
gh secret set SUPABASE_URL -R USERNAME/HokTifyy -b "https://yyyy.supabase.co"
bash termux/build.sh
```

---

## 8. Cara manual (tanpa skrip)

1. Buat repo di github.com, upload seluruh isi folder.
2. Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Isi |
|---|---|
| `SUPABASE_URL` | Project URL Supabase |
| `SUPABASE_ANON_KEY` | anon public key |
| `GOOGLE_WEB_CLIENT_ID` | (opsional) Web client ID Google |
| `KEYSTORE_BASE64` | `base64 -w0 hoktifyy.jks` |
| `STORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS` | password & alias keystore |

   Tanpa secret keystore, workflow tetap jalan memakai keystore **sementara** (APK tidak bisa di-update menimpa build lama).
3. Tab **Actions → Build HokTifyy APK → Run workflow**.
4. Selesai → tab **Releases** → unduh APK → install.

---

## 9. Masalah umum

| Gejala | Solusi |
|---|---|
| `termux-open` tidak membuka installer | Buka *Files → Download → HokTifyy-….apk* manual. Izinkan **Install unknown apps** untuk Termux/Files. |
| *App not installed* / *conflict* | Ada versi lama dengan tanda-tangan berbeda → uninstall dulu, lalu install. Pakai keystore tetap (langkah 4) agar tidak terulang. |
| Workflow gagal di *Build APK* | Buka log di tab Actions → salin error. Source ini belum pernah dikompilasi di lingkungan pembuat panduan, jadi build pertama bisa menemukan penyesuaian kecil. |
| `gh: command not found` | `pkg install gh` |
| `gh auth login` tidak bisa buka browser | Normal di Termux: salin kode & buka `https://github.com/login/device` manual. |
| Build terpotong saat Termux ditutup | Build tetap lanjut di GitHub. Jalankan `bash termux/install.sh USERNAME/HokTifyy` setelah selesai. |
| Fitur login/playlist bersama error | Cek secret `SUPABASE_URL`/`SUPABASE_ANON_KEY` benar, `schema.sql` sudah di-Run, dan (untuk login) langkah 6. |
| Cek update tidak muncul | Repo harus **public**, tag harus berformat `v<versi>+<build>` dengan build lebih besar dari yang terpasang. |

---

## 10. Lisensi

HokTifyy adalah turunan **StreamBeats** (© 2026 DuskCipher) dengan source oleh **Valora Official**, berlisensi **GNU GPL v2 atau lebih baru**. Berkas [`LICENSE`](LICENSE) dan kredit Valora **tidak boleh dihapus**; rincian perubahan di [`NOTICE.md`](NOTICE.md). Jika membagikan APK ke orang lain, sediakan source code-nya (repo public sudah memenuhi).
