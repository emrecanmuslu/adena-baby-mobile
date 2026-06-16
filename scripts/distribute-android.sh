#!/usr/bin/env bash
# Android test build'ini Firebase App Distribution ile dağıtır.
#
# Kullanım:
#   scripts/distribute-android.sh ["sürüm notu"]
#
# Tester'lar e-posta/Firebase App Tester uygulaması ile bildirim alır, tıklayıp
# kurar/günceller (USB/adb gerekmez). İlk çalıştırma App Distribution'ı projede
# otomatik provision eder ve TESTERS'taki adresleri tester olarak ekler.
#
# Notlar:
# - Build cloud API'ye bağlanır (api.adenababy.com, herkesçe güvenilir TLS).
# - Sosyal giriş / IAP / reklam token'ları henüz boş → o akışlar pasif; e-posta
#   girişi + çekirdek takip çalışır.
# - Release imzası hâlâ debug keystore (YAYIN_EKSIKLERI #1) — test için sorun
#   değil, mağaza yüklemesi öncesi upload keystore gerekir.
set -euo pipefail
cd "$(dirname "$0")/.."

API_URL="${API_BASE_URL:-https://api.adenababy.com/api/v1}"
APP_ID="1:160566700344:android:5a4f7f9d13923ee4f8f9cd"   # Firebase Android app id
TESTERS="${TESTERS:-emrecan.muslu@gmail.com}"            # virgülle çoğalt
NOTES="${1:-Test dağıtımı}"

FLUTTER=flutter
command -v flutter >/dev/null 2>&1 || FLUTTER=/c/src/flutter/bin/flutter

echo "▶ Release APK build ediliyor (API=$API_URL)…"
"$FLUTTER" build apk --release --dart-define=API_BASE_URL="$API_URL"

APK="build/app/outputs/flutter-apk/app-release.apk"
echo "▶ Firebase App Distribution'a yükleniyor…"
firebase appdistribution:distribute "$APK" \
  --app "$APP_ID" \
  --testers "$TESTERS" \
  --release-notes "$NOTES"

echo "✓ Dağıtıldı. Tester'lar bildirim alacak; ilk kez ise e-postadaki davete tıklayıp App Tester'ı kurar."
