import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/ad_service.dart';
import 'core/i18n.dart';
import 'core/tour.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/consent_gate_screen.dart';
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
import 'features/cycle/cycle_dashboard_screen.dart';
import 'features/cycle/cycle_settings_screen.dart';
import 'features/cycle/cycle_stats_screen.dart';
import 'features/dev/dev_tools_screen.dart';
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
import 'features/settings/ai_export_screen.dart';
import 'features/settings/appearance_screen.dart';
import 'features/settings/premium_screen.dart';
import 'features/settings/privacy_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/splash/splash_screen.dart';

/// Riverpod değişimlerini go_router'a köprüler (provider değişince redirect tetiklenir).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(babyControllerProvider, (_, _) => notifyListeners());
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
          path: '/consent-gate', builder: (_, _) => const ConsentGateScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const BabySetupScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
          path: '/baby-add',
          builder: (_, _) => const BabySetupScreen(onboarding: false)),
      GoRoute(
          path: '/settings',
          builder: (_, _) =>
              const TourMount(tourKey: 'settings', child: SettingsScreen())),
      // Yalnız debug derlemede: geliştirici/bildirim test ekranı.
      if (kDebugMode)
        GoRoute(path: '/dev', builder: (_, _) => const DevToolsScreen()),
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
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(
          path: '/premium',
          builder: (_, _) =>
              const TourMount(tourKey: 'premium', child: PremiumScreen())),
      GoRoute(path: '/ai-export', builder: (_, _) => const AIExportScreen()),
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
              const TourMount(tourKey: 'cycle', child: CycleScreen())),
      GoRoute(
          path: '/cycle/calendar',
          builder: (_, _) => const CycleCalendarScreen()),
      GoRoute(path: '/cycle/stats', builder: (_, _) => const CycleStatsScreen()),
      GoRoute(
          path: '/cycle/settings',
          builder: (_, _) => const CycleSettingsScreen()),
    ],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final onAuthPage = loc == '/login' || loc == '/register';

      // İlk açılışta oturum çözülürken splash'te bekle — ama login/register'da
      // DEĞİL (kendi yükleme/hata UI'larını yönetirler; yoksa kayıt/giriş hatası
      // gösterilemeden kullanıcı splash'e atılır).
      if ((auth.isLoading || !auth.hasValue) && !onAuthPage) {
        return loc == '/' ? null : '/';
      }

      final user = auth.asData?.value;
      if (user == null) {
        return onAuthPage ? null : '/login';
      }

      // Yasal rıza kapısı — sosyal giriş yapan / güncel sürümü kabul etmemiş
      // kullanıcı uygulamaya girmeden önce 18+ ve Gizlilik/Şartlar'ı kabul eder.
      if (user.consentRequired) {
        return loc == '/consent-gate' ? null : '/consent-gate';
      }
      if (loc == '/consent-gate') return '/home'; // rıza alındı → devam

      // Oturum açık — bebek listesini bekle.
      final babies = ref.read(babyControllerProvider);
      if (babies.isLoading || !babies.hasValue) {
        return loc == '/' ? null : '/';
      }
      final hasBaby = (babies.asData?.value ?? []).isNotEmpty;

      if (!hasBaby) return loc == '/onboarding' ? null : '/onboarding';

      // Bebek var → ana sayfa. Splash/auth/onboarding'te kalma.
      if (onAuthPage || loc == '/' || loc == '/onboarding') return '/home';
      return null;
    },
  );
});
