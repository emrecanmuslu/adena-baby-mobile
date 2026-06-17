---
name: hata-gosterimi-standardi
description: API hatalarını kullanıcıya gösterirken core/api_error.dart apiErrorText(e) kullan — ham DioException/generic mesaj gösterme
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 31fe5a81-8562-4f94-a996-8e5e22376277
---

Kullanıcıya API/DRF hatası gösterilen HER yerde **`apiErrorText(e)`** (`core/api_error.dart`) kullanılmalı — ham `DioException`/`$e` ya da gerçek sebebi yutan generic mesaj ("Kaydedilemedi", "Silinemedi" vb.) GÖSTERME.

**Why:** Kullanıcı 2026-06-11'de "django'dan gelen hatalara göre düzenle" dedi (kayıt 400'ü "Bu e-posta zaten kayıtlı"ydı ama uygulama sessizce login'e atıyordu). DRF mesajları zaten Türkçe (backend USE_I18N + LANGUAGE_CODE=tr).

**How to apply:** `apiErrorText` DRF biçimlerini çözer: `{"alan":["mesaj"]}` (tek→sade, çok→"Etiket: mesaj"), `{"error":"kod","detail":"insan mesajı"}` (detail alınır, error kodu atlanır), `{"detail":...}`, iç içe/list; gövde yoksa Dio tipi + HTTP koduna (401/403/404/5xx/ağ) göre genel mesaj. Yeni catch/hata gösterimi yazarken: `catch (e) { showAdToast(context, apiErrorText(e)); }` ve provider `.when(error: (e,_) => Text(apiErrorText(e)))`.

**Ayrıca düzeltildi:** Router redirect login/register'da splash'e atıyordu → kayıt/giriş hatası gösterilemeden kullanıcı atılıyordu; `&& !onAuthPage` ile düzeltildi (router.dart). Yerel dosya/IO hataları (paylaşım vb. DioException değil) apiErrorText kapsamı dışı.
