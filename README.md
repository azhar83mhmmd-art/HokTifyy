<p align="center"><img src="assets/icons/hoktifyy_logo.png" width="160" alt="Vynora Music"></p>

# Vynora Music

Pemutar musik gratis tanpa iklan (Flutter + Rust). Turunan dari **StreamBeats**
(© 2026 DuskCipher) — source oleh **Valora Official**. Lisensi **GPL v2+** (lihat [`LICENSE`](LICENSE), [`NOTICE.md`](NOTICE.md)).

- Database cloud: **Supabase** (playlist bersama, party room, login Google)
- Database lokal: Isar (library, riwayat, unduhan — tetap offline)
- Build APK: **GitHub Actions**, dipasang lewat **Termux**

➡️ Panduan lengkap: **[PANDUAN_INSTALASI.md](PANDUAN_INSTALASI.md)**

Ringkas:

```bash
# di Termux
pkg install -y git
git clone https://github.com/USERNAME/HokTifyy && cd Vynora Music   # atau ekstrak zip source
bash termux/setup.sh      # sekali saja: login GitHub, repo, secrets Supabase, keystore
bash termux/build.sh      # build di GitHub lalu install otomatis
```
