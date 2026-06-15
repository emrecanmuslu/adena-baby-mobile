import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ad_widgets.dart';
import '../../core/adena_icons.dart';
import '../../core/api_error.dart';
import '../../core/i18n.dart';
import '../../core/legal_links.dart';
import '../../core/theme.dart';
import '../../data/auth_repository.dart';
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
          AdMenuItem(
            icon: 'shield',
            color: AppColors.pump,
            bg: AppColors.pumpBg,
            title: tr('Yedekleme'),
            meta: tr('Çevrimiçi olunca buluta otomatik eşitlenir'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.growthBg, borderRadius: BorderRadius.circular(999)),
              child: Text(tr('Açık'),
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF349970))),
            ),
          ),
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
          adSec(tr('Şeffaflık')),
          _Note(
            tr('Verilerini asla satmıyor veya reklam için kullanmıyoruz. '
                'Aile üyeleri yalnızca paylaştığın bebeği görür.'),
          ),
          adSec(tr('Yasal'),
              info: tr('Belgeler çevrimiçi yayınlanır ve tarayıcıda açılır. '
                  'Diline göre Türkçe ya da İngilizce gösterilir.')),
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
          AdMenuItem(
            icon: 'trash',
            color: AppColors.fever,
            bg: AppColors.feverBg,
            title: tr('Hesabı & verileri sil'),
            meta: tr('GDPR · geri alınamaz'),
            titleColor: AppColors.fever,
            onTap: _deleteAccount,
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
        content: Text(
            tr('Hesabın ve tüm bebek verilerin kalıcı olarak silinecek. Bu geri alınamaz.')),
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
