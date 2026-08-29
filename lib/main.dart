import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://folbvzmvxqjmfzzssshm.supabase.co',
    publishableKey: 'sb_publishable_QGecyaWlzS4qVYmjOpralA_gYFyzPAh',
  );
  await NotificationService.instance.initialize();
  runApp(const FloodGuardApp());
}

class FloodGuardApp extends StatelessWidget {
  const FloodGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FloodGuard AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const AppScrollBehavior(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        return auth.currentSession == null
            ? const LoginScreen()
            : const HomeScreen();
      },
    );
  }
}
