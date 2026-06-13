#!/usr/bin/env bash
# Adena Baby — sosyal giriş + diğer dart-define'larla çalıştır/derle.
# Tüm değerler dart_defines.json'dan okunur (Google/Apple/RevenueCat/AdMob).
#
# Kullanım:
#   scripts/run.sh run    -d emulator-5554        # emülatör (local API, override yok)
#   scripts/run.sh apk                            # debug APK derle
#   scripts/run.sh run    -d <ios> --dart-define=API_BASE_URL=https://...  # fiziksel
#
# Not: emülatörde API_BASE_URL VERME (default 10.0.2.2 doğru). Fiziksel cihazda
# LAN IP / tünel / cloud URL'sini ek --dart-define ile geç.
set -e
cd "$(dirname "$0")/.."

DEFINES="--dart-define-from-file=dart_defines.json"
CMD="${1:-run}"; shift || true

case "$CMD" in
  run) flutter run $DEFINES "$@" ;;
  apk) flutter build apk --debug $DEFINES "$@" ;;
  ios) flutter build ios --no-codesign $DEFINES "$@" ;;
  *)   echo "bilinmeyen komut: $CMD (run|apk|ios)"; exit 1 ;;
esac
