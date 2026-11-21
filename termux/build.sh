#!/data/data/com.termux/files/usr/bin/bash
# Memicu build APK di GitHub Actions, menunggu selesai, lalu memasangnya.
# Pakai:  bash termux/build.sh [user/repo]
set -euo pipefail
REPO="${1:-$(cat "$HOME/.hoktifyy_repo" 2>/dev/null || true)}"
[ -n "$REPO" ] || { echo "Isi repo: bash termux/build.sh user/repo"; exit 1; }
cd "$(dirname "$0")/.."

echo "==> Push perubahan terbaru (jika ada)"
if [ -d .git ]; then
  git add -A
  git commit -m "update" >/dev/null 2>&1 || true
  git push >/dev/null 2>&1 || echo "(push dilewati)"
fi

echo "==> Memicu workflow di $REPO"
gh workflow run build-apk.yml -R "$REPO"
sleep 8
RUN_ID="$(gh run list -R "$REPO" --workflow build-apk.yml --limit 1 --json databaseId -q '.[0].databaseId')"
echo "Run #$RUN_ID  (pantau: https://github.com/$REPO/actions/runs/$RUN_ID)"
echo "Build biasa memakan 15-30 menit. Termux boleh ditinggal, tapi jangan di-swipe-close."
termux-wake-lock 2>/dev/null || true
gh run watch "$RUN_ID" -R "$REPO" --exit-status
termux-wake-unlock 2>/dev/null || true

echo "==> Build sukses, memasang APK"
exec bash termux/install.sh "$REPO"
