#!/usr/bin/env python3
"""App Store Connect — distribution sertifikası yönetimi (CI cert-limiti için).

Cloud imzalama (`xcodebuild -allowProvisioningUpdates`) her ephemeral CI
çalıştırmasında YENİ bir distribution sertifikası üretir; bireysel hesabın
limiti dolunca archive "maximum number of certificates" ile patlar. Bu script
her build ÖNCESİ eski distribution sertifikalarını siler → hep yer açılır.

Kimlik bilgileri ortamdan:
  ASC_KEY_ID, ASC_ISSUER_ID, ve ASC_KEY_PATH (yerel .p8 yolu) VEYA
  ASC_KEY_B64 (.p8'in base64'ü, CI secret).

Kullanım:
  python asc_certs.py --list
  python asc_certs.py --revoke-distribution
"""
import base64
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com/v1"
DIST_TYPES = {"DISTRIBUTION", "IOS_DISTRIBUTION"}


def _private_key() -> str:
    path = os.environ.get("ASC_KEY_PATH")
    if path and os.path.exists(path):
        with open(path, "r") as f:
            return f.read()
    b64 = os.environ.get("ASC_KEY_B64")
    if b64:
        return base64.b64decode(b64).decode("utf-8")
    sys.exit("ASC_KEY_PATH veya ASC_KEY_B64 gerekli")


def _token() -> str:
    key_id = os.environ["ASC_KEY_ID"].strip()
    issuer = os.environ["ASC_ISSUER_ID"].strip()
    now = int(time.time())
    payload = {"iss": issuer, "iat": now, "exp": now + 1000, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, _private_key(), algorithm="ES256", headers={"kid": key_id})


def _headers() -> dict:
    return {"Authorization": f"Bearer {_token()}", "Content-Type": "application/json"}


def _get(url):
    """ASC API GET — geçici ağ hatalarına karşı 3 deneme, uzun timeout."""
    last = None
    for attempt in range(3):
        try:
            r = requests.get(url, headers=_headers(), timeout=60)
            r.raise_for_status()
            return r
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(3 * (attempt + 1))
    raise last


def list_certs() -> list:
    certs, url = [], f"{API}/certificates?limit=200"
    while url:
        r = _get(url)
        body = r.json()
        certs.extend(body.get("data", []))
        url = body.get("links", {}).get("next")
    return certs


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "--list"
    certs = list_certs()
    print(f"Toplam sertifika: {len(certs)}")
    for c in certs:
        a = c["attributes"]
        print(f"  - {c['id']} | {a.get('certificateType')} | {a.get('displayName')} | exp {a.get('expirationDate')}")

    if mode in ("--revoke-distribution", "--revoke-all"):
        if mode == "--revoke-all":
            # Tüm CI sertifikaları ephemeral (her build cloud imzalama ile yeniden
            # üretir) → hepsini sil, dev+dist limiti hiç dolmasın.
            targets = list(certs)
        else:
            targets = [c for c in certs if c["attributes"].get("certificateType") in DIST_TYPES]
        print(f"\nRevoke edilecek sertifika: {len(targets)}")
        for c in targets:
            r = requests.delete(f"{API}/certificates/{c['id']}", headers=_headers(), timeout=60)
            ok = r.status_code in (204, 200)
            print(f"  {'OK ' if ok else 'FAIL('+str(r.status_code)+') '}{c['id']} {c['attributes'].get('displayName')}")
        print("Tamam.")


if __name__ == "__main__":
    main()
