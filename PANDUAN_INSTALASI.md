# Panduan Instalasi Vynora Music (Termux + GitHub Actions + Supabase)

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
6. [Playlist bersama & Party (tanpa Google)](#6-playlist-bersama--party-tanpa-google)
7. [Layar login: email & Google](#7-layar-login-email--google)
8. [Update aplikasi & pop-up pembaruan](#8-update-aplikasi--pop-up-pembaruan)
9. [Cara manual (tanpa skrip)](#9-cara-manual-tanpa-skrip)
10. [Masalah umum](#10-masalah-umum)
11. [Lisensi](#11-lisensi)

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

**A. Dari zip di HP** (mis. `VynoraMusic-2.0.0.zip` ada di folder Download):
```bash
cd ~
unzip ~/storage/downloads/VynoraMusic-2.0.0.zip
cd VynoraMusic-main

```

**B. Dari repo yang sudah ada:**
```bash
git clone https://github.com/USERNAME/HokTifyy
cd VynoraMusic
```

---

## 4. Setup sekali jalan (`termux/setup.sh`)

```bash
bash termux/setup.sh
```

Skrip akan menanyakan/ mengerjakan berurutan:

1. Memasang `git`, `gh` (GitHub CLI), `openjdk-17`, `jq`, `termux-api`, `openssl`.
2. **Login GitHub** — pilih *GitHub.com → HTTPS → Login with a web browser*. Salin kode 8 karakter, buka link di browser HP, masukkan kode, setujui.
3. Membuat repo (default `Vynora Music`, **public**) dan meng-upload source.
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
2. Workflow **Build Vynora Music APK** dijalankan; Termux memantau progresnya (`gh run watch`).
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
| `VynoraMusic-android-arm64-v8a.apk` | HP modern (hampir semua HP sejak ±2017) |
| `VynoraMusic-android-armeabi-v7a.apk` | HP 32-bit lama |
| `VynoraMusic-android-x86_64.apk` | Emulator / Chromebook |
| `VynoraMusic-android-universal.apk` | **Bingung? pilih ini** (lebih besar, cocok di semua) |

---

## 6. Playlist bersama & Party (tanpa Google)

Fitur ini **tidak wajib login Google**. Saat kamu menekan *Buat playlist bersama* / *Party*, aplikasi otomatis masuk sebagai **pengguna anonim** lewat Supabase.

### 6.1 Aktifkan sekali di Supabase
1. Supabase Dashboard → **Authentication → Sign In / Providers** (di versi lama: *Providers*).
2. Aktifkan **Allow anonymous sign-ins** → **Save**.
3. Pastikan `supabase/schema.sql` sudah di-**Run** (bagian 2.2). Tanpa ini muncul error tabel `shared_playlists` tidak ditemukan.

### 6.2 Cara memakai
- **Membuat:** *Buat Playlist Baru* → isi nama → nyalakan saklar **"Jadikan Playlist Bersama"** → simpan. Aplikasi menampilkan **kode 6 karakter**; bagikan ke teman.
- **Bergabung:** teman membuka menu gabung playlist bersama (*Join Shared Playlist*) dan memasukkan kodenya.
- Lagu yang ditambahkan anggota muncul langsung di semua HP (Realtime).
- **Party Room:** satu orang menekan buat room (host), yang lain gabung dengan kode; pemutaran disinkronkan.

### 6.3 Batasan akun anonim
- Identitas anonim tersimpan di HP. Jika aplikasi di-**uninstall** atau datanya dihapus, kamu dianggap pengguna baru: kepemilikan playlist lama hilang (anggota lain tetap aman, dan kamu bisa bergabung ulang memakai kode).
- Ingin akun permanen? Login Google di bagian 7.

### 6.4 Cek berhasil
Supabase → **Table Editor → `shared_playlists`**: baris baru muncul setelah kamu membuat playlist bersama. Di **Authentication → Users** akan terlihat pengguna *Anonymous*.

Jika muncul pesan *"Login otomatis gagal… anonymous sign-ins"* → langkah 6.1 belum diaktifkan.

---

## 7. Layar login: email & Google

Saat Vynora Music dibuka **pertama kali** (setelah onboarding) muncul layar login dengan tiga pilihan:
**Email + kata sandi**, **Google**, atau **Lanjutkan sebagai Tamu**. Layar ini tampil sekali; pilihan tamu atau login yang berhasil membuatnya tidak muncul lagi. Layar menyesuaikan ukuran: satu kolom di HP, dua panel di tablet/desktop. Layar ini otomatis dilewati jika `SUPABASE_URL` / `SUPABASE_ANON_KEY` belum diisi.

### 7.1 Login email (tanpa setup tambahan)
1. Supabase → **Authentication → Sign In / Providers → Email**: pastikan **Enable Email provider** aktif.
2. **Confirm email** (pilih salah satu):
   - **Nonaktif** → pendaftar langsung masuk (paling mudah untuk pemakaian pribadi).
   - **Aktif** → pendaftar menerima email konfirmasi; setelah klik tautannya baru bisa masuk. Aplikasi menampilkan petunjuk ini otomatis.
3. Fitur *Lupa kata sandi* mengirim tautan reset lewat email (butuh SMTP bawaan Supabase, terbatas beberapa email/jam; untuk pemakaian ramai, pasang SMTP sendiri di *Authentication → SMTP Settings*).

### 7.2 Login Google (opsional)

Pemutar musik dan playlist bersama berjalan **tanpa login Google** (lihat bagian 6). Login Google hanya untuk akun permanen yang tidak hilang saat aplikasi di-uninstall.

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
6. Di aplikasi: **Pengaturan → Login Google**.

---

## 8. Update aplikasi & pop-up pembaruan

### Cara kerja
1. Setiap build di GitHub otomatis memakai **nomor build yang naik sendiri** (nomor run) dan membuat release baru bertag `v<versi>+<nomor>`. Kamu **tidak perlu** mengedit `pubspec.yaml` untuk tiap build.
2. Tiap kali Vynora Music dibuka, aplikasi mengecek release terbaru repo kamu.
3. Jika ada yang lebih baru, muncul **pop-up "Pembaruan Tersedia"** berisi catatan perubahan dengan tombol:
   - **Perbarui Langsung** → mengunduh APK di dalam aplikasi lalu membuka installer Android → tekan *Install*.
   - **Web** → membuka halaman repo.
   - **Nanti** → menutup pop-up (muncul lagi saat aplikasi dibuka berikutnya).

> Android **tidak mengizinkan update benar-benar otomatis/senyap** untuk aplikasi di luar Play Store. Pop-up + satu ketukan *Install* adalah yang paling otomatis yang bisa dilakukan.

### Syarat agar pop-up muncul
- Repo **public** (aplikasi membaca GitHub tanpa login).
- APK terpasang dibuild dari repo itu (build ini sudah membawa `HOKTIFYY_REPO` otomatis).
- Build baru ditandatangani **keystore yang sama** (dibuat `setup.sh`), kalau tidak, installer menolak menimpa.
- Release punya file `VynoraMusic-android-universal.apk` (otomatis dibuat workflow).

### Merilis update
```bash
cd ~/hoktifyy
# ... ubah kode / pengaturan ...
bash termux/build.sh
```
Versi tampilan (mis. `1.0.0` → `1.1.0`) cukup diubah di `pubspec.yaml` bila mau; angka setelah `+` diabaikan karena diganti nomor run.

Mengganti secret (mis. project Supabase baru):
```bash
gh secret set SUPABASE_URL -R $(cat ~/.hoktifyy_repo) -b "https://yyyy.supabase.co"
bash termux/build.sh
```

### Menguji pop-up
Pasang APK build lama, jalankan build baru sampai selesai, lalu buka kembali Vynora Music di HP (pastikan internet aktif).

---

## 9. Cara manual (tanpa skrip)

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
3. Tab **Actions → Build Vynora Music APK → Run workflow**.
4. Selesai → tab **Releases** → unduh APK → install.

---

## 10. Masalah umum

| Gejala | Solusi |
|---|---|
| `termux-open` tidak membuka installer | Buka *Files → Download → Vynora Music-….apk* manual. Izinkan **Install unknown apps** untuk Termux/Files. |
| *App not installed* / *conflict* | Ada versi lama dengan tanda-tangan berbeda → uninstall dulu, lalu install. Pakai keystore tetap (langkah 4) agar tidak terulang. |
| Workflow gagal di *Build APK* | Buka log di tab Actions → salin error. Source ini belum pernah dikompilasi di lingkungan pembuat panduan, jadi build pertama bisa menemukan penyesuaian kecil. |
| `gh: command not found` | `pkg install gh` |
| `gh auth login` tidak bisa buka browser | Normal di Termux: salin kode & buka `https://github.com/login/device` manual. |
| Build terpotong saat Termux ditutup | Build tetap lanjut di GitHub. Jalankan `bash termux/install.sh USERNAME/HokTifyy` setelah selesai. |
| Fitur login/playlist bersama error | Cek secret `SUPABASE_URL`/`SUPABASE_ANON_KEY` benar, `schema.sql` sudah di-Run, dan (untuk login) langkah 6. |
| `permission denied for table shared_playlists` (42501) | Jalankan ulang `supabase/schema.sql` terbaru di SQL Editor (berisi `GRANT` untuk role `authenticated`). |
| `Email not confirmed` | *Confirm email* aktif di Supabase: buka tautan di email konfirmasi, atau nonaktifkan opsi itu (bagian 7.1). |
| `Must be logged in` / `Login otomatis gagal` | Aktifkan *Allow anonymous sign-ins* (bagian 6.1) lalu coba lagi. Pastikan APK sudah dibuild dengan secret Supabase. |
| Cek update tidak muncul | Repo harus **public**, build baru harus selesai dan terbit di Releases. Tag otomatis `v<versi>+<nomor run>`. |

---

## 11. Lisensi

Vynora Music adalah turunan **StreamBeats** (© 2026 DuskCipher) dengan source oleh **Valora Official**, berlisensi **GNU GPL v2 atau lebih baru**. Berkas [`LICENSE`](LICENSE) dan kredit Valora **tidak boleh dihapus**; rincian perubahan di [`NOTICE.md`](NOTICE.md). Jika membagikan APK ke orang lain, sediakan source code-nya (repo public sudah memenuhi).
