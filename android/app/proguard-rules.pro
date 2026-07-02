# Firebase / Google Play services — R8 keep kuralları.
#
# NEDEN: Release build'de R8 obfuscation çalışır. Firebase, alt-SDK'larını
# (Messaging/Analytics/CRASHLYTICS) çalışma anında `ComponentRegistrar`
# implementasyonlarını reflection/metadata ile keşfederek yükler. Keep kuralı
# olmadan R8 bu registrar'ları budar/yeniden adlandırır → Crashlytics eklendikten
# sonra `Firebase.initializeApp()` release'te
#   "FirebaseCrashlytics component is not present" → [core/no-app]
# fırlatır; native init başarılı olsa bile Flutter tarafı kaydolmaz → FCM token
# kaydı (/me/devices) sessizce düşer. (iOS'ta R8 olmadığı için bu yaşanmaz.)
#
# Bu kurallar tüm Firebase component registrar'larını + Firebase/GMS sınıflarını
# korur; initializeApp release'te de hatasız tamamlanır.

# Firebase component sistemi — registrar'lar reflection ile bulunur.
-keep class com.google.firebase.components.ComponentRegistrar { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keepnames class com.google.firebase.components.ComponentRegistrar

# Firebase & Google Play services geneli.
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics: exception sınıf/metod adları anlamlı kalsın + component korunsun.
-keep class com.google.firebase.crashlytics.** { *; }
-keepattributes SourceFile,LineNumberTable,*Annotation*

# flutter_local_notifications (java.time desugaring + reflection).
-keep class com.dexterous.** { *; }
