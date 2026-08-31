import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> floodGuardFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase config is supplied per environment; keep background delivery safe.
  }
}

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();

  static const _channelId = 'floodguard_alerts_v2';
  static const _channelName = 'FloodGuard Alerts';
  static const _channelDescription = 'Flood and hazard safety notifications';
  static const _notificationIcon = 'ic_floodguard_notification';
  static const _largeNotificationIcon = 'ic_floodguard_app_icon';
  static final _vibrationPattern = Int64List.fromList([0, 350, 160, 350]);

  final _notifications = FlutterLocalNotificationsPlugin();
  final _tapController = StreamController<Map<String, dynamic>>.broadcast();
  bool _firebaseReady = false;

  Stream<Map<String, dynamic>> get notificationTaps => _tapController.stream;
  bool get remotePushAvailable => _firebaseReady;

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_notificationIcon),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            _tapController.add(decoded);
            return;
          }
        } catch (_) {
          // Older app versions used plain string payloads.
        }
        _tapController.add({'payload': payload});
      },
    );
    await _ensureAlertChannel();
    await _initializeFirebaseMessaging();
  }

  Future<bool> requestPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final localPermitted =
        await android?.requestNotificationsPermission() ?? true;
    if (_firebaseReady) {
      await FirebaseMessaging.instance.requestPermission();
    }
    if (localPermitted) await registerPushDevice();
    return localPermitted;
  }

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.areNotificationsEnabled() ?? true;
  }

  Future<void> showFloodAlert({
    required int id,
    required String title,
    required String body,
    String? expandedBody,
    Map<String, dynamic>? payload,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _ensureAlertChannel();
    final resolvedExpandedBody =
        expandedBody ?? payload?['expanded_body']?.toString() ?? body;
    await _notifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          icon: _notificationIcon,
          importance: Importance.max,
          priority: Priority.max,
          styleInformation: BigTextStyleInformation(
            resolvedExpandedBody,
            contentTitle: title,
            summaryText: 'FloodGuard',
          ),
          playSound: true,
          enableVibration: true,
          vibrationPattern: _vibrationPattern,
          channelShowBadge: true,
          showWhen: true,
          ticker: title,
          visibility: NotificationVisibility.public,
          category: AndroidNotificationCategory.alarm,
          largeIcon: const DrawableResourceAndroidBitmap(
            _largeNotificationIcon,
          ),
          audioAttributesUsage: AudioAttributesUsage.notificationEvent,
        ),
      ),
      payload: jsonEncode(payload ?? {'type': 'flood_warning'}),
    );
  }

  Future<void> showTemplateAlert({
    required FloodGuardAlertTemplate template,
    int? id,
    Map<String, dynamic>? payload,
  }) {
    final mergedPayload = <String, dynamic>{
      'type': template.type,
      'screen': template.screen,
      if (payload != null) ...payload,
    };
    return showFloodAlert(
      id: id ?? template.id,
      title: template.title,
      body: template.body,
      expandedBody: template.expandedBody,
      payload: mergedPayload,
    );
  }

  Future<void> showDemoFloodWatch() => showFloodAlert(
    id: DateTime.now().millisecondsSinceEpoch.remainder(1000000),
    title: _floodWatchTemplate.title,
    body: _floodWatchTemplate.body,
    expandedBody: _floodWatchTemplate.expandedBody,
    payload: const {'type': 'flood_watch', 'screen': 'alerts'},
  );

  Future<void> registerPushDevice() async {
    if (!_firebaseReady) return;
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await _upsertPushToken(token);
  }

  Future<void> saveNotificationPreferences({
    required bool floodWarnings,
    required bool nearbyHazards,
    required bool severeRainfall,
    required bool evacuationAdvisories,
    required bool communityUpdates,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    await client.from('notification_preferences').upsert({
      'user_id': userId,
      'flood_warnings': floodWarnings,
      'nearby_hazards': nearbyHazards,
      'severe_rainfall': severeRainfall,
      'evacuation_advisories': evacuationAdvisories,
      'community_updates': communityUpdates,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Map<String, bool>?> loadNotificationPreferences() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;
    final data = await client
        .from('notification_preferences')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return {
      'flood_warnings': data['flood_warnings'] as bool? ?? true,
      'nearby_hazards': data['nearby_hazards'] as bool? ?? true,
      'severe_rainfall': data['severe_rainfall'] as bool? ?? true,
      'evacuation_advisories': data['evacuation_advisories'] as bool? ?? true,
      'community_updates': data['community_updates'] as bool? ?? false,
    };
  }

  Future<void> sendRemoteDemoFloodAlert() async {
    final client = Supabase.instance.client;
    await registerPushDevice();
    await client.functions.invoke(
      'send-floodguard-notification',
      body: {
        'type': 'flood_warning',
        'severity': 'watch',
        'title': 'FloodGuard remote push test',
        'message':
            'Test only. This notification was sent through Supabase and FCM.',
        'area': 'Baliwag development area',
        'source': 'FloodGuard debug tool',
        'target': {'mode': 'current_user'},
        'data': {'screen': 'alerts'},
      },
    );
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      FirebaseMessaging.onBackgroundMessage(
        floodGuardFirebaseMessagingBackgroundHandler,
      );
      FirebaseMessaging.instance.onTokenRefresh.listen(_upsertPushToken);
      FirebaseMessaging.onMessage.listen(_handleForegroundRemoteMessage);
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _tapController.add(message.data);
      });
      final initialMessage = await FirebaseMessaging.instance
          .getInitialMessage();
      if (initialMessage != null) _tapController.add(initialMessage.data);
      await registerPushDevice();
    } catch (error) {
      debugPrint(
        '[Notifications] Firebase Messaging is not configured yet: $error',
      );
    }
  }

  Future<void> _ensureAlertChannel() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: _vibrationPattern,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.notificationEvent,
      ),
    );
    if (kDebugMode) {
      final channels = await android?.getNotificationChannels();
      final channel = channels
          ?.where((item) => item.id == _channelId)
          .firstOrNull;
      debugPrint(
        '[Notifications] channel=$_channelId importance=${channel?.importance.name} '
        'sound=${channel?.playSound} vibration=${channel?.enableVibration}',
      );
    }
  }

  Future<void> _handleForegroundRemoteMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ??
        message.data['title']?.toString() ??
        'FloodGuard';
    final body =
        notification?.body ??
        message.data['message']?.toString() ??
        'New FloodGuard alert received.';
    await showFloodAlert(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      payload: message.data,
    );
  }

  Future<void> _upsertPushToken(String token) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      await client.from('push_devices').upsert({
        'user_id': userId,
        'fcm_token': token,
        'platform': defaultTargetPlatform.name,
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fcm_token');
      debugPrint('[Notifications] FCM token registered.');
    } catch (error) {
      debugPrint('[Notifications] FCM token registration failed: $error');
    }
  }
}

class FloodGuardAlertTemplate {
  const FloodGuardAlertTemplate({
    required this.id,
    required this.type,
    required this.screen,
    required this.title,
    required this.body,
    required this.expandedBody,
  });

  final int id;
  final String type;
  final String screen;
  final String title;
  final String body;
  final String expandedBody;
}

const _floodWatchTemplate = FloodGuardAlertTemplate(
  id: 1001,
  type: 'flood_watch',
  screen: 'alerts',
  title: 'FloodGuard — Flood Watch',
  body:
      'Heavy rainfall and a nearby flood report were detected in Baliwag. Check the Flood Map for updates.',
  expandedBody:
      'Heavy rainfall and a nearby flood report were detected in Baliwag.\n'
      'Avoid low-lying roads and flooded routes.\n'
      'Open FloodGuard to view the affected area and nearby safety facilities.',
);

const floodWarningAlertTemplate = FloodGuardAlertTemplate(
  id: 1101,
  type: 'flood_warning',
  screen: 'alerts',
  title: 'FloodGuard — Flood Warning',
  body:
      'Multiple flood reports were detected near your area. Check the Flood Map and avoid affected roads.',
  expandedBody:
      'Multiple flood reports were detected near your area.\n'
      'Check the Flood Map and avoid affected roads.',
);

const nearbyHazardAlertTemplate = FloodGuardAlertTemplate(
  id: 1102,
  type: 'nearby_hazard',
  screen: 'alerts',
  title: 'FloodGuard — Hazard Nearby',
  body:
      'A new drainage or waterway hazard was reported near your area. View the map for details.',
  expandedBody:
      'A new drainage or waterway hazard was reported near your area.\n'
      'Open FloodGuard to view the map and report details.',
);

const severeRainfallAlertTemplate = FloodGuardAlertTemplate(
  id: 1103,
  type: 'severe_rainfall',
  screen: 'alerts',
  title: 'FloodGuard — Heavy Rainfall Alert',
  body:
      'Heavy rainfall is expected in your area. Monitor flood conditions and prepare emergency supplies.',
  expandedBody:
      'Heavy rainfall is expected in your area.\n'
      'Monitor flood conditions and prepare emergency supplies.',
);

const evacuationAdvisoryAlertTemplate = FloodGuardAlertTemplate(
  id: 1104,
  type: 'evacuation_advisory',
  screen: 'alerts',
  title: 'FloodGuard — Safety Advisory',
  body:
      'Flood conditions may require evacuation. Check nearby safety facilities and official advisories.',
  expandedBody:
      'Flood conditions may require evacuation.\n'
      'Check nearby safety facilities and official advisories.',
);

const communityReportUpdateAlertTemplate = FloodGuardAlertTemplate(
  id: 1105,
  type: 'community_report_update',
  screen: 'alerts',
  title: 'FloodGuard — Report Update',
  body: 'A community hazard report near your area has been updated.',
  expandedBody:
      'A community hazard report near your area has been updated.\n'
      'Open FloodGuard to review the latest status.',
);
