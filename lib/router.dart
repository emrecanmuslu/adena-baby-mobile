import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/ad_service.dart';
import 'core/i18n.dart';
import 'core/tour.dart';
import 'data/local_session.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/consent_gate_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/babies/baby_controller.dart';
import 'features/babies/baby_edit_screen.dart';
import 'features/babies/born_flow_screen.dart';
import 'features/babies/caregiver_screen.dart';
import 'features/babies/members_screen.dart';
import 'features/community/community_feed_screen.dart';
import 'features/community/community_profile_screen.dart';
import 'features/community/question_detail_screen.dart';
import 'features/content/article_detail_screen.dart';
import 'features/content/article_list_screen.dart';
import 'features/content/content_hub_screen.dart';
import 'features/cycle/cycle_calendar_screen.dart';
import 'features/cycle/cycle_settings_screen.dart';
import 'features/cycle/cycle_shell.dart';
import 'features/cycle/cycle_stats_screen.dart';
import 'features/discover/discover_screen.dart';
import 'features/health/health_screen.dart';
import 'features/health/reminders_screen.dart';
import 'features/health/vaccines_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/mom_tracking_screen.dart';
import 'features/development/milestones_screen.dart';
import 'features/development/teeth_screen.dart';
import 'features/memories/memories_screen.dart';
import 'features/onboarding/baby_setup_screen.dart';
import 'features/onboarding/welcome_choice_screen.dart';
import 'models/baby.dart';
import 'features/settings/appearance_screen.dart';
import 'features/settings/dev_settings_screen.dart';
import 'features/settings/feedback_screen.dart';
import 'features/settings/premium_screen.dart';
import 'features/settings/privacy_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';

/// Bebeksiz "adet & gebelik takibi" dalında (cycleFirst) hangi rotalara izin var.
/// Bu dalda kullanıcının bebeği yoktur; ana bebek ekranları (home/health/timeline
/// vb.) bebek gerektirdiği için erişilmez, ara ekranlar /cycle'a yönlenir. Yalnız
/// Adet Takvimi + bebek/gebelik ekleme + premium/gizlilik + auth sayfaları açık.
bool _cycleFirstAllows(String loc) =>
    loc.startsWith('/cycle') ||
    loc == '/baby-add' ||
    loc == '/premium' ||
    loc == '/privacy' ||
    loc == '/feedback' ||
    loc == '/dev';

/// Riverpod değişimlerini go_router'a köprüler (provider değişince redirect tetiklenir).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(babyControllerProvider, (_, _) => notifyListeners());
    ref.listen(localConsentProvider, (_, _) => notifyListeners());
    ref.listen(localNameProvider, (_, _) => notifyListeners());
    ref.listen(guestModeProvider, (_, _) => notifyListeners());
    ref.listen(cycleFirstProvider, (_, _) => notifyListeners());
    // Çeviri bundle'ı (EN) açılışta async gelir; go_router mevcut sayfayı
    // refresh olmadan yeniden çizmez → ilk ekran (rıza/welcome) gezinmeye kadar
    // kaynak (TR) dilde kalırdı. I18n değişince router'ı tazele → anında EN.
    I18n.instance.addListener(_onI18n);
  }

  void _onI18n() => notifyListeners();

  @override
  void dispose() {
    I18n.instance.removeListener(_onI18n);
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavigatorKey, // reklam/placeholder overlay'i için kök navigator
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
          path: '/consent-gate', builder: (_, _) => const ConsentGateScreen()),
      // Onboarding iki adım: (1) hedef seçimi (bebek doğdu / hamile / adet
      // takvimi / davet-giriş), (2) seçime göre bebek formu.
      GoRoute(
          path: '/onboarding', builder: (_, _) => const WelcomeChoiceScreen()),
      GoRoute(
        path: '/onboarding/baby',
        builder: (_, state) =>
            BabySetupScreen(initialStatus: state.extra as BabyStatus?),
      ),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
          path: '/baby-add',
          builder: (_, _) => const BabySetupScreen(onboarding: false)),
      GoRoute(
          path: '/settings',
          builder: (_, _) =>
              const TourMount(tourKey: 'settings', child: SettingsScreen())),
      GoRoute(
          path: '/members',
          builder: (_, _) =>
              const TourMount(tourKey: 'members', child: MembersScreen())),
      GoRoute(
          path: '/caregiver',
          builder: (_, _) =>
              const TourMount(tourKey: 'caregiver', child: CaregiverScreen())),
      GoRoute(
          path: '/baby-edit',
          builder: (_, _) =>
              const TourMount(tourKey: 'babyedit', child: BabyEditScreen())),
      GoRoute(
          path: '/health',
          builder: (_, _) =>
              const TourMount(tourKey: 'health', child: HealthScreen())),
      GoRoute(
          path: '/vaccines',
          builder: (_, _) =>
              const TourMount(tourKey: 'vaccines', child: VaccinesScreen())),
      GoRoute(
          path: '/reminders',
          builder: (_, _) =>
              const TourMount(tourKey: 'reminders', child: RemindersScreen())),
      GoRoute(path: '/appearance', builder: (_, _) => const AppearanceScreen()),
      // Yalnız debug: Geliştirici ayarları (API ortamı vb.). Release'te menü
      // öğesi gizli olduğundan buraya gidilmez.
      GoRoute(path: '/dev', builder: (_, _) => const DevSettingsScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/feedback', builder: (_, _) => const FeedbackScreen()),
      GoRoute(
          path: '/premium',
          builder: (_, _) =>
              const TourMount(tourKey: 'premium', child: PremiumScreen())),
      GoRoute(
          path: '/mom',
          builder: (_, _) =>
              const TourMount(tourKey: 'mom', child: MomTrackingScreen())),
      GoRoute(
          path: '/memories',
          builder: (_, _) =>
              const TourMount(tourKey: 'memories', child: MemoriesScreen())),
      GoRoute(
          path: '/content',
          builder: (_, _) =>
              const TourMount(tourKey: 'content', child: ContentHubScreen())),
      GoRoute(
        path: '/content/articles',
        builder: (_, state) => ArticleListScreen(
          args: state.extra as ArticleListArgs? ??
              ArticleListArgs(title: tr('Rehberler')),
        ),
      ),
      GoRoute(
        path: '/content/article/:slug',
        builder: (_, state) =>
            ArticleDetailScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
          path: '/discover',
          builder: (_, _) =>
              const TourMount(tourKey: 'discover', child: DiscoverScreen())),
      GoRoute(
          path: '/community',
          builder: (_, _) => const TourMount(
              tourKey: 'community', child: CommunityFeedScreen())),
      GoRoute(
        path: '/community/question/:id',
        builder: (_, state) =>
            QuestionDetailScreen(questionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/community/user/:id',
        builder: (_, state) =>
            CommunityProfileScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(
          path: '/milestones',
          builder: (_, _) =>
              const TourMount(tourKey: 'milestones', child: MilestonesScreen())),
      GoRoute(
          path: '/teeth',
          builder: (_, _) =>
              const TourMount(tourKey: 'teeth', child: TeethScreen())),
      GoRoute(path: '/born-flow', builder: (_, _) => const BornFlowScreen()),
      // Adet Takvimi (doğum sonrası anne — kişisel). Keşfet'ten açılır.
      GoRoute(
          path: '/cycle',
          builder: (_, _) =>
              const TourMount(tourKey: 'cycle', child: CycleShell())),
      GoRoute(
          path: '/cycle/calendar',
          builder: (_, _) => const CycleCalendarScreen()),
      GoRoute(path: '/cycle/stats', builder: (_, _) => const CycleStatsScreen()),
      GoRoute(
          path: '/cycle/settings',
          builder: (_, _) => const CycleSettingsScreen()),
    ],
    redirect: (context, state) {
      // İki yol: (a) GERÇEK HESAP → giriş/kayıt → rıza (sunucu) → bebek → ana sayfa;
      // (b) MİSAFİR ("kayıt olmadan devam et") → yerel rıza → bebek → ana sayfa.
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      // Geliştirici sayfası (yalnız debug) her oturum durumunda erişilebilir —
      // çıkışken bile ortam değiştirilebilsin (login ekranından açılır).
      if (kDebugMode && loc == '/dev') return null;
      final onAuthPage = loc == '/login' ||
          loc == '/register' ||
          loc == '/forgot-password';

      // Oturum çözülürken splash'te bekle — auth/rıza sayfaları kendi UI'larını
      // yönetir.
      if ((auth.isLoading || !auth.hasValue) &&
          !onAuthPage &&
          loc != '/consent-gate') {
        return loc == '/' ? null : '/';
      }
      final user = auth.asData?.value;

      // 1) Gerçek oturum yok.
      if (user == null) {
        final guest = ref.read(guestModeProvider);
        // Misafir değil → giriş ekranı (misafir girişi login ekranından yapılır).
        if (!guest) {
          return onAuthPage ? null : '/login';
        }
        // MİSAFİR akışı:
        // Sonradan hesap açmak/giriş yapmak isterse auth sayfalarına izin ver.
        if (onAuthPage) return null;
        // a) Yerel rıza (18+/şartlar) — hesapsız, yerelde alınır.
        if (!ref.read(localConsentProvider)) {
          return loc == '/consent-gate' ? null : '/consent-gate';
        }
        // b) Bebek (yerel) — yüklenmesini bekle.
        final gBabies = ref.read(babyControllerProvider);
        if (gBabies.isLoading || !gBabies.hasValue) {
          return (loc == '/' || loc == '/consent-gate') ? null : '/';
        }
        if ((gBabies.asData?.value ?? const []).isEmpty) {
          // Bebeksiz "adet & gebelik takibi" dalı: bebek zorunlu değil → doğrudan
          // Adet Takvimi. Ara ekranları (splash/rıza/onboarding) /cycle'a yönlt.
          if (ref.read(cycleFirstProvider)) {
            return _cycleFirstAllows(loc) ? null : '/cycle';
          }
          return loc.startsWith('/onboarding') ? null : '/onboarding';
        }
        // c) Her şey tamam → ana sayfa (ara ekranlardan çık).
        if (loc == '/' ||
            loc == '/consent-gate' ||
            loc.startsWith('/onboarding')) {
          return '/home';
        }
        return null;
      }

      // 2) Rıza (hesaba bağlı) — kayıt/giriş sonrası alınır.
      if (user.consentRequired) {
        return loc == '/consent-gate' ? null : '/consent-gate';
      }

      // 3) Bebek (yerel) — yüklenmesini bekle.
      final babies = ref.read(babyControllerProvider);
      if (babies.isLoading || !babies.hasValue) {
        return (loc == '/' || onAuthPage || loc == '/consent-gate') ? null : '/';
      }
      final hasBaby = (babies.asData?.value ?? []).isNotEmpty;
      if (!hasBaby) {
        // Bebeksiz "adet & gebelik takibi" dalı (hesaplı kullanıcı da seçebilir).
        if (ref.read(cycleFirstProvider)) {
          return _cycleFirstAllows(loc) ? null : '/cycle';
        }
        return loc.startsWith('/onboarding') ? null : '/onboarding';
      }

      // 4) Her şey tamam → ara ekranlardan (splash/rıza/onboarding/auth) ana
      //    sayfaya.
      if (loc == '/' ||
          onAuthPage ||
          loc == '/consent-gate' ||
          loc.startsWith('/onboarding')) {
        return '/home';
      }
      return null;
    },
  );
});
