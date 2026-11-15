#!/bin/zsh
# 重新生成全部宣传图：src/*.html → out/*.png（2160×2880 母版）+ out/*.jpg（1080×1440，质量 90）
# 用法：./render.sh            全部
#       ./render.sh 02-notch    只渲染一张
set -euo pipefail
cd "${0:A:h}"

CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$CHROME" ]] || { echo "找不到 Chrome：$CHROME（可用 CHROME=... 指定）" >&2; exit 1; }
mkdir -p out
PROFILE=$(mktemp -d)
trap 'rm -rf "$PROFILE"' EXIT

pages=(src/[0-9]*.html)
[[ $# -gt 0 ]] && pages=(src/$1.html)

for page in $pages; do
  name=${page:t:r}
  png="out/veil-$name.png"
  jpg="out/veil-$name.jpg"
  rm -f "$png" "$jpg"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --no-first-run \
    --user-data-dir="$PROFILE" --allow-file-access-from-files \
    --force-device-scale-factor=2 --window-size=1080,1440 \
    --virtual-time-budget=3000 \
    --screenshot="$PWD/$png" "file://$PWD/$page" >/dev/null 2>&1
  [[ -s "$png" ]] || { echo "✗ 渲染失败：$page" >&2; exit 1; }
  sips -s format jpeg -s formatOptions 90 --resampleWidth 1080 "$png" --out "$jpg" >/dev/null
  size() { sips -g pixelWidth -g pixelHeight "$1" | awk '/pixel/{printf "%s ", $2}'; }
  [[ "$(size $png)" == "2160 2880 " && "$(size $jpg)" == "1080 1440 " ]] || { echo "✗ 尺寸不对：$png / $jpg" >&2; exit 1; }
  echo "✓ $png  $(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixel/{printf $2" "}')→ $jpg"
done
