import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/flood_alert.dart';
import '../services/alert_service.dart';
import '../services/notification_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'risk_details_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _alertService = AlertService();
  final _knownAlertIds = <String>{};
  RealtimeChannel? _channel;
  List<FloodAlert> _alerts = const [];
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshAlerts(notifyNew: false);
    _channel = _alertService.subscribe(() => _refreshAlerts(notifyNew: true));
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _alertService.unsubscribe(channel);
    super.dispose();
  }

  Future<void> _refreshAlerts({required bool notifyNew}) async {
    try {
      final alerts = await _alertService.getActiveAlerts();
      if (!mounted) return;
      final newAlerts = alerts
          .where((alert) => !_knownAlertIds.contains(alert.id))
          .toList();
      setState(() {
        _alerts = alerts;
        _error = null;
        _isLoading = false;
        _knownAlertIds.addAll(alerts.map((alert) => alert.id));
      });
      if (notifyNew) {
        for (final alert in newAlerts) {
          await NotificationService.instance.showFloodAlert(
            id: alert.id.hashCode & 0x7fffffff,
            title: alert.title,
            body: alert.message,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Verified alerts are not available yet.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _enableNotifications() async {
    final permitted = await NotificationService.instance.requestPermission();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          permitted
              ? 'Flood notifications are enabled.'
              : 'Notifications are disabled. Enable them in Android Settings.',
        ),
      ),
    );
  }

  Future<void> _sendTestAlert() async {
    await NotificationService.instance.showDemoFloodWatch();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Demo flood alert sent.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alerts'),
      actions: [
        IconButton(
          onPressed: _isLoading ? null : () => _refreshAlerts(notifyNew: false),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh alerts',
        ),
      ],
    ),
    bottomNavigationBar: const AppBottomNav(index: 1),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Verified alerts update automatically while this screen is open.',
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card(
            color: const Color(0xFFFFF5F5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '$_error Run the Supabase alerts setup, then refresh.',
              ),
            ),
          )
        else if (_alerts.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified_outlined, color: AppTheme.blue),
              title: Text('No active verified alerts'),
              subtitle: Text(
                'You will be notified when an authorized alert is published.',
              ),
            ),
          )
        else
          ..._alerts.map(_AlertCard.new),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _enableNotifications,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Enable Flood Notifications'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _sendTestAlert,
          icon: const Icon(Icons.warning_amber_rounded),
          label: const Text('Send Demo Flood Alert'),
        ),
      ],
    ),
  );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard(this.alert);

  final FloodAlert alert;

  @override
  Widget build(BuildContext context) {
    final isHigh = alert.severity == 'critical' || alert.severity == 'warning';
    return Card(
      color: isHigh ? const Color(0xFFFFF5F5) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isHigh ? const Color(0xFFFFE3E3) : AppTheme.paleBlue,
          child: Icon(
            Icons.warning_amber_rounded,
            color: isHigh ? Colors.red : AppTheme.blue,
          ),
        ),
        title: Text(
          alert.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${alert.area == null ? '' : '${alert.area} - '}${alert.message}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const RiskDetailsScreen()),
          ),
        ),
      ),
    );
  }
}
