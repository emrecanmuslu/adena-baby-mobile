import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/babies/baby_controller.dart';
import 'features/babies/baby_edit_screen.dart';
import 'features/babies/born_flow_screen.dart';
import 'features/babies/caregiver_screen.dart';
import 'features/babies/members_screen.dart';
import 'features/health/health_screen.dart';
import 'features/health/reminders_screen.dart';
import 'features/health/vaccines_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/mom_tracking_screen.dart';
import 'features/development/milestones_screen.dart';
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
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const BabySetupScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(
          path: '/baby-add',
          builder: (_, _) => const BabySetupScreen(onboarding: false)),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/members', builder: (_, _) => const MembersScreen()),
      GoRoute(path: '/caregiver', builder: (_, _) => const CaregiverScreen()),
      GoRoute(path: '/baby-edit', builder: (_, _) => const BabyEditScreen()),
      GoRoute(path: '/health', builder: (_, _) => const HealthScreen()),
      GoRoute(path: '/vaccines', builder: (_, _) => const VaccinesScreen()),
      GoRoute(path: '/reminders', builder: (_, _) => const RemindersScreen()),
      GoRoute(path: '/appearance', builder: (_, _) => const AppearanceScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/premium', builder: (_, _) => const PremiumScreen()),
      GoRoute(path: '/ai-export', builder: (_, _) => const AIExportScreen()),
      GoRoute(path: '/mom', builder: (_, _) => const MomTrackingScreen()),
      GoRoute(path: '/memories', builder: (_, _) => const MemoriesScreen()),
      GoRoute(path: '/milestones', builder: (_, _) => const MilestonesScreen()),
      GoRoute(path: '/born-flow', builder: (_, _) => const BornFlowScreen()),
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
