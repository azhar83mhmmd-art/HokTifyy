#!/data/data/com.termux/files/usr/bin/bash
# Mengunduh APK Vynora Music terbaru dari GitHub Releases lalu membuka installer Android.
# Tidak perlu login untuk repo public.
# Pakai:  bash termux/install.sh user/repo
#   atau: curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/termux/install.sh | bash -s -- USER/REPO
set -euo pipefail
REPO="${1:-$(cat "$HOME/.hoktifyy_repo" 2>/dev/null || true)}"
[ -n "$REPO" ] || { echo "Pakai: bash install.sh user/repo"; exit 1; }
command -v curl >/dev/null || pkg install -y curl
command -v jq   >/dev/null || pkg install -y jq
command -v termux-open >/dev/null || pkg install -y termux-tools

case "$(uname -m)" in
  aarch64)  ABI="arm64-v8a" ;;
  x86_64)   ABI="x86_64" ;;
  *)        ABI="universal" ;;   # armv7 / armv8l / lainnya
esac
echo "Arsitektur: $(uname -m)  ->  APK: $ABI"

JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
TAG="$(echo "$JSON" | jq -r .tag_name)"
URL="$(echo "$JSON" | jq -r --arg abi "$ABI" '.assets[] | select(.name | endswith("android-"+$abi+".apk")) | .browser_download_url' | head -n1)"
[ -n "$URL" ] || URL="$(echo "$JSON" | jq -r '.assets[] | select(.name | endswith("android-universal.apk")) | .browser_download_url' | head -n1)"
[ -n "$URL" ] || { echo "APK tidak ditemukan di release $TAG. Pastikan build sudah selesai & repo public."; exit 1; }

OUT="$HOME/HokTifyy-${TAG//+/_}.apk"
echo "Mengunduh $TAG ..."
curl -fL --progress-bar -o "$OUT" "$URL"

if [ -d "$HOME/storage/downloads" ]; then
  cp -f "$OUT" "$HOME/storage/downloads/"
  echo "Salinan: Download/$(basename "$OUT")"
fi

echo "Membuka installer Android ..."
echo "Jika muncul 'Izinkan dari sumber ini' untuk Termux, aktifkan lalu tekan Install."
termux-open "$OUT" || echo "Buka manual: Files -> Download -> $(basename "$OUT")"
