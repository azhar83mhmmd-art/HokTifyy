#!/data/data/com.termux/files/usr/bin/bash
# =====================================================================
#  HokTifyy - setup sekali jalan di Termux
#  - memasang tool yang dibutuhkan
#  - login GitHub, membuat repo, mengunggah source
#  - mengisi GitHub Secrets (Supabase, Google, keystore)
#  Jalankan dari folder source:   bash termux/setup.sh
# =====================================================================
set -euo pipefail

say()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
ask()  { local p="$1" d="${2:-}" v; read -r -p "$p${d:+ [$d]}: " v; echo "${v:-$d}"; }

cd "$(dirname "$0")/.."

say "1/6 Memasang paket Termux"
pkg update -y
pkg install -y git gh openjdk-17 curl jq termux-api openssl
[ -d "$HOME/storage" ] || termux-setup-storage || true

say "2/6 Login GitHub"
if ! gh auth status >/dev/null 2>&1; then
  echo "Pilih: GitHub.com -> HTTPS -> login with a web browser."
  echo "Salin kode yang muncul, buka link-nya di browser HP, lalu setujui."
  gh auth login -h github.com -p https -w
fi
gh auth setup-git
GH_USER="$(gh api user -q .login)"
echo "Login sebagai: $GH_USER"

say "3/6 Membuat repo GitHub dan mengunggah source"
REPO_NAME="$(ask 'Nama repo' 'HokTifyy')"
VIS="$(ask 'Visibilitas repo (public/private). Public disarankan (lisensi GPL + fitur update-in-app)' 'public')"
[ -d .git ] || git init -b main
git config user.name  >/dev/null 2>&1 || git config user.name  "$GH_USER"
git config user.email >/dev/null 2>&1 || git config user.email "${GH_USER}@users.noreply.github.com"
git add -A
git commit -m "HokTifyy: initial import (based on StreamBeats, source by Valora Official)" || true
if gh repo view "$GH_USER/$REPO_NAME" >/dev/null 2>&1; then
  warn "Repo $GH_USER/$REPO_NAME sudah ada, hanya push."
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$GH_USER/$REPO_NAME.git"
  git push -u origin main
else
  gh repo create "$GH_USER/$REPO_NAME" "--$VIS" --source=. --remote=origin --push
fi
REPO="$GH_USER/$REPO_NAME"

say "4/6 Secrets Supabase"
echo "Ambil dari Supabase Dashboard -> Project Settings -> API."
SB_URL="$(ask 'SUPABASE_URL (https://xxxx.supabase.co)')"
SB_KEY="$(ask 'SUPABASE_ANON_KEY (anon public, BUKAN service_role)')"
G_ID="$(ask 'GOOGLE_WEB_CLIENT_ID (kosongkan jika belum punya)' '')"
[ -n "$SB_URL" ] && gh secret set SUPABASE_URL      -R "$REPO" -b "$SB_URL"
[ -n "$SB_KEY" ] && gh secret set SUPABASE_ANON_KEY -R "$REPO" -b "$SB_KEY"
[ -n "$G_ID"  ] && gh secret set GOOGLE_WEB_CLIENT_ID -R "$REPO" -b "$G_ID"

say "5/6 Keystore penandatangan APK"
KS_DIR="$HOME/.hoktifyy-keystore"
KS="$KS_DIR/hoktifyy.jks"
if [ -f "$KS" ]; then
  warn "Keystore sudah ada di $KS - memakai yang itu. Isi password-nya dari file $KS_DIR/credentials.txt"
  # shellcheck disable=SC1091
  source "$KS_DIR/credentials.txt"
else
  mkdir -p "$KS_DIR"; chmod 700 "$KS_DIR"
  STORE_PASSWORD="$(openssl rand -hex 16)"
  KEY_ALIAS="hoktifyy"
  keytool -genkeypair -keystore "$KS" -alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$STORE_PASSWORD" -keypass "$STORE_PASSWORD" \
    -dname "CN=HokTifyy, OU=Mobile, O=HokTifyy, C=ID"
  printf 'STORE_PASSWORD=%s\nKEY_ALIAS=%s\n' "$STORE_PASSWORD" "$KEY_ALIAS" > "$KS_DIR/credentials.txt"
  chmod 600 "$KS" "$KS_DIR/credentials.txt"
  warn "BACKUP folder $KS_DIR. Kalau keystore hilang, update APK akan gagal (harus uninstall dulu)."
fi
base64 -w0 "$KS" | gh secret set KEYSTORE_BASE64 -R "$REPO"
gh secret set STORE_PASSWORD -R "$REPO" -b "$STORE_PASSWORD"
gh secret set KEY_PASSWORD   -R "$REPO" -b "$STORE_PASSWORD"
gh secret set KEY_ALIAS      -R "$REPO" -b "$KEY_ALIAS"

say "6/6 Selesai"
echo "$REPO" > "$HOME/.hoktifyy_repo"
echo "Repo     : https://github.com/$REPO"
echo "Langkah  : bash termux/build.sh      (build di GitHub, lalu otomatis install)"
if [ "$(ask 'Jalankan build sekarang? (y/n)' 'y')" = "y" ]; then
  exec bash termux/build.sh
fi
