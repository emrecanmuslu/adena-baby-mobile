import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../core/providers.dart';
import '../../core/restart_widget.dart';
import '../../core/theme.dart';
import '../../data/auth_repository.dart';
import '../../data/local_session.dart';
import '../records/record_controller.dart';
import '../../data/sync_gate.dart';
import '../auth/auth_controller.dart';
import 'data_export.dart';

/// Veri & Gizlilik (design ScrPrivacy): veri indir + yedekleme bilgisi +
/// şeffaflık notu + hesabı & verileri sil (GDPR).
class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key});

  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool _exporting = false;
  bool _anon = false; // topluluk anonimliği (community_display == 'anon')
  bool _savingAnon = false;

  @override
  void initState() {
    super.initState();
    _loadCommunityPref();
  }

  Future<void> _loadCommunityPref() async {
    // Hesapsız (local-first): topluluk ayarı yok → sunucuya gitme (401 olmaz).
    if (ref.read(authControllerProvider).asData?.value == null) return;
    try {
      final s = await ref.read(authRepositoryProvider).settings();
      if (mounted) {
        setState(() => _anon = (s['community_display'] as String?) == 'anon');
      }
    } catch (_) {
      // sessiz geç — varsayılan gerçek isim
    }
  }

  Future<void> _setAnon(bool value) async {
    setState(() {
      _anon = value;
      _savingAnon = true;
    });
    try {
      await ref.read(authRepositoryProvider).updateSettings(
          {'community_display': value ? 'anon' : 'name'});
    } catch (e) {
      if (mounted) {
        setState(() => _anon = !value); // geri al
        showAdError(context, apiErrorText(e));
      }
    } finally {
      if (mounted) setState(() => _savingAnon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loggedIn = ref.watch(authControllerProvider).asData?.value != null;
    final analyticsOn = ref.watch(localAnalyticsConsentProvider);
    // Bulut yedeği yalnız premium + oturum açıkken aktif (local-first).
    final cloudBackup = ref.watch(cloudSyncEnabledProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('Veri & Gizlilik')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Note(
            tr('Verin sana ait. Dilediğin an indir, yedekle veya tamamen sil. 🔒'),
            tip: true,
          ),
          adSec(tr('Veri')),
          AdMenuItem(
            icon: 'download',
            color: AppColors.growth,
            bg: AppColors.growthBg,
            title: tr('Verilerimi indir'),
            meta: _exporting ? tr('Hazırlanıyor…') : tr('JSON olarak dışa aktar'),
            trailing: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.growth))
                : null,
            onTap: _exporting ? null : _export,
          ),
          // Local-first: bulut yedeği yalnız Premium'da. Free/hesapsızda veri
          // YALNIZ bu cihazda → doğru durumu göster (yanıltma).
          AdMenuItem(
            icon: 'shield',
            color: AppColors.pump,
            bg: AppColors.pumpBg,
            title: tr('Bulut yedekleme'),
            meta: cloudBackup
                ? tr('Açık · değişiklikler buluta otomatik eşitlenir')
                : tr('Kapalı · verin yalnız bu cihazda. Premium ile yedekle'),
            trailing: cloudBackup
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.growthBg,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(tr('Açık'),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF349970))),
                  )
                : const AdProBadge(withChevron: true),
            onTap: cloudBackup ? null : () => context.push('/premium'),
          ),
          // Topluluk hesap gerektirir → anonimlik ayarı yalnız oturum açıkken.
          if (loggedIn) ...[
            adSec(tr('Topluluk'),
                info: tr('Ebeveyn topluluğunda soru/cevap paylaşırken nasıl '
                    'görüneceğini belirler. Anonim açıkken adın yerine "Anonim" '
                    'görünür; bebek bilgilerin paylaşılmaz.')),
            AdMenuItem(
              icon: 'user',
              color: AppColors.sleep,
              bg: AppColors.sleepBg,
              title: tr('Toplulukta anonim görün'),
              meta: _anon
                  ? tr('Gönderilerin "Anonim" olarak görünür')
                  : tr('Gönderilerin gerçek adınla görünür'),
              trailing: _savingAnon
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.sleep))
                  : Switch.adaptive(
                      value: _anon,
                      activeThumbColor: AppColors.coral,
                      onChanged: _setAnon,
                    ),
              onTap: () => _setAnon(!_anon),
            ),
            _Note(
              tr('Not: Anonimlik her gönderi için o anki ayarına göre belirlenir; '
                  'sonradan değiştirsen eski gönderiler aynı kalır.'),
            ),
          ],
          adSec(tr('Şeffaflık')),
          _Note(
            tr('Verilerini satmıyoruz. Hizmeti sunmak için kullandığımız üçüncü '
                'taraflar (analitik, ödeme, reklam) Gizlilik Politikası\'nda '
                'açıklanır. Aile üyeleri yalnızca paylaştığın bebeği görür.'),
          ),
          AdMenuItem(
            icon: 'compass',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: tr('Kullanım analitiği'),
            meta: analyticsOn
                ? tr('Açık · isimsiz kullanım verisiyle uygulamayı geliştiriyoruz')
                : tr('Kapalı · kullanım verisi toplanmaz'),
            trailing: Switch.adaptive(
              value: analyticsOn,
              activeThumbColor: AppColors.coral,
              onChanged: (v) =>
                  ref.read(localAnalyticsConsentProvider.notifier).set(v),
            ),
            onTap: () => ref
                .read(localAnalyticsConsentProvider.notifier)
                .set(!analyticsOn),
          ),
          adSec(tr('Yasal')),
          AdMenuItem(
            icon: 'shield',
            color: AppColors.pump,
            bg: AppColors.pumpBg,
            title: tr('Gizlilik Politikası'),
            meta: tr('Web sayfasını açar'),
            onTap: () => openLegalDoc(context, LegalDoc.privacy),
          ),
          AdMenuItem(
            icon: 'check',
            color: AppColors.growth,
            bg: AppColors.growthBg,
            title: tr('Kullanım Şartları'),
            meta: tr('Web sayfasını açar'),
            onTap: () => openLegalDoc(context, LegalDoc.terms),
          ),
          AdMenuItem(
            icon: 'user',
            color: AppColors.sleep,
            bg: AppColors.sleepBg,
            title: tr('KVKK Aydınlatma Metni'),
            meta: tr('Web sayfasını açar'),
            onTap: () => openLegalDoc(context, LegalDoc.kvkk),
          ),
          AdMenuItem(
            icon: 'link',
            color: AppColors.feed,
            bg: AppColors.feedBg,
            title: tr('Çerez Politikası'),
            meta: tr('Web sayfasını açar'),
            onTap: () => openLegalDoc(context, LegalDoc.cookies),
          ),
          adSec(tr('Tehlikeli bölge'), color: AppColors.coralDd),
          if (loggedIn)
            AdMenuItem(
              icon: 'trash',
              color: AppColors.fever,
              bg: AppColors.feverBg,
              title: tr('Hesabı & verileri sil'),
              meta: tr('GDPR · 30 gün içinde geri yüklenebilir'),
              titleColor: AppColors.fever,
              onTap: _deleteAccount,
            )
          else
            // Hesapsız (local-first): silinecek hesap yok; yerel veriler silinir.
            AdMenuItem(
              icon: 'trash',
              color: AppColors.fever,
              bg: AppColors.feverBg,
              title: tr('Yerel verileri sil'),
              meta: tr('Bu cihazdaki tüm kayıt ve bilgiler · geri alınamaz'),
              titleColor: AppColors.fever,
              onTap: _deleteLocalData,
            ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    await exportUserData(context, ref);
    if (mounted) setState(() => _exporting = false);
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(tr('Hesabı & verileri sil')),
        content: Text(tr(
            'Hesabın devre dışı bırakılacak ve oturumun her cihazda kapanacak. '
            '30 gün içinde tekrar giriş yapmazsan hesabın ve tüm bebek verilerin '
            'kalıcı olarak silinir. Bu süre içinde giriş yaparsan silme iptal olur.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(tr('Vazgeç'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.fever),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(tr('Sil')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(authControllerProvider.notifier).deleteAccount();
      // Router, oturum null olunca otomatik /login'e yönlendirir.
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }

  /// Hesapsız (local-first) kullanıcıda yerel veriyi tamamen siler ve uygulamayı
  /// sıfırdan başlatır (rıza korunur → tanışma ekranına döner).
  Future<void> _deleteLocalData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(tr('Yerel verileri sil')),
        content: Text(tr(
            'Bu cihazdaki tüm bebek profilleri, kayıtlar, anılar ve ayarlar '
            'kalıcı olarak silinecek. Bu işlem geri alınamaz. Önce '
            '"Verilerimi indir" ile yedek alabilirsin.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text(tr('Vazgeç'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.fever),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(tr('Sil')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      SyncService.wiping = true; // silme sırasında sync re-insert etmesin (yarış)
      await ref.read(databaseProvider).wipeAllData();
      await LocalSession.clearLocalProfile();
      if (mounted) RestartWidget.restartApp(context);
    } catch (e) {
      if (mounted) showAdError(context, apiErrorText(e));
    }
  }
}

/// Bilgi notu (design .ad-note). tip=true → sıcak şeftali zemin; aksi nötr.
class _Note extends StatelessWidget {
  final String text;
  final bool tip;
  const _Note(this.text, {this.tip = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 2),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tip ? AppColors.feedBg : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: tip ? null : AppColors.softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tip) ...[
            const AdenaIcon('shield', size: 18, color: AppColors.coralDd),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                    color: tip ? AppColors.ink2 : AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
