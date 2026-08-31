import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/alerts_screen.dart';
import 'screens/evacuation_centers_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'services/notification_service.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  ml.MapLibreMap.useHybridComposition = true;
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

  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'FloodGuard AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const AppScrollBehavior(),
      home: const _NotificationTapHandler(child: AuthGate()),
    );
  }
}

class _NotificationTapHandler extends StatefulWidget {
  const _NotificationTapHandler({required this.child});

  final Widget child;

  @override
  State<_NotificationTapHandler> createState() =>
      _NotificationTapHandlerState();
}

class _NotificationTapHandlerState extends State<_NotificationTapHandler> {
  StreamSubscription<Map<String, dynamic>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = NotificationService.instance.notificationTaps.listen(
      _openNotificationTarget,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _openNotificationTarget(Map<String, dynamic> data) {
    final navigator = FloodGuardApp.navigatorKey.currentState;
    if (navigator == null) return;
    final reportId = data['report_id']?.toString();
    if (reportId != null && reportId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => EvacuationCentersScreen(focusReportId: reportId),
        ),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isOpeningPasswordRecovery = false;

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          _openPasswordRecovery();
        }
        return auth.currentSession == null
            ? const LoginScreen()
            : const HomeScreen();
      },
    );
  }

  void _openPasswordRecovery() {
    if (_isOpeningPasswordRecovery) return;
    _isOpeningPasswordRecovery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ResetPasswordScreen()),
      );
      if (mounted) _isOpeningPasswordRecovery = false;
    });
  }
}
