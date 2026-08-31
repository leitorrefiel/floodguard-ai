import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/flood_alert.dart';
import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import '../services/alert_service.dart';
import '../services/device_location_service.dart';
import '../services/hazard_map_service.dart';
import '../services/notification_service.dart';
import '../services/risk_service.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import 'evacuation_centers_screen.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  static const _readAlertsKey = 'floodguard_read_alert_ids';
  static const _prefsPrefix = 'floodguard_alert_pref';

  final _alertService = AlertService();
  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  final _riskService = const RiskService();
  final _hazardMapService = HazardMapService();

  final _knownAlertIds = <String>{};
  final _readAlertIds = <String>{};
  final Map<_AlertPreference, bool> _preferences = {
    _AlertPreference.floodWarnings: true,
    _AlertPreference.nearbyHazards: true,
    _AlertPreference.severeRainfall: true,
    _AlertPreference.evacuationAdvisories: true,
    _AlertPreference.communityUpdates: false,
  };

  RealtimeChannel? _channel;
  List<_AppAlert> _alerts = const [];
  _AppAlert? _statusAlert;
  String? _statusMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _restoreState();
    _channel = _alertService.subscribe(() => _refreshAlerts(notifyNew: true));
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _alertService.unsubscribe(channel);
    super.dispose();
  }

  Future<void> _restoreState() async {
    final preferences = await SharedPreferences.getInstance();
    final remotePreferences = await _loadRemotePreferences();
    if (!mounted) return;
    setState(() {
      _readAlertIds
        ..clear()
        ..addAll(preferences.getStringList(_readAlertsKey) ?? const []);
      for (final preference in _AlertPreference.values) {
        final localValue = preferences.getBool(
          '$_prefsPrefix.${preference.name}',
        );
        _preferences[preference] =
            remotePreferences?[preference] ??
            localValue ??
            _preferences[preference]!;
      }
    });
    await _refreshAlerts(notifyNew: false);
  }

  Future<Map<_AlertPreference, bool>?> _loadRemotePreferences() async {
    try {
      final values = await NotificationService.instance
          .loadNotificationPreferences();
      if (values == null) return null;
      return {
        _AlertPreference.floodWarnings: values['flood_warnings'] ?? true,
        _AlertPreference.nearbyHazards: values['nearby_hazards'] ?? true,
        _AlertPreference.severeRainfall: values['severe_rainfall'] ?? true,
        _AlertPreference.evacuationAdvisories:
            values['evacuation_advisories'] ?? true,
        _AlertPreference.communityUpdates: values['community_updates'] ?? false,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshAlerts({required bool notifyNew}) async {
    setState(() => _isLoading = true);

    final generated = <_AppAlert>[];
    var statusMessage = 'No active critical alerts nearby.';
    try {
      final contextAlerts = await _generatedContextAlerts();
      generated.addAll(contextAlerts.alerts);
      statusMessage = contextAlerts.statusMessage;
    } catch (_) {
      statusMessage = 'Alert status is limited while live data loads.';
    }

    try {
      final officialAlerts = await _alertService.getActiveAlerts();
      generated.addAll(officialAlerts.map(_AppAlert.fromFloodAlert));
    } catch (_) {
      // The screen still works without an alerts table; generated alerts remain available.
    }

    final uniqueAlerts = _dedupeAlerts(generated)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final preferredAlerts = uniqueAlerts.where(_preferenceAllows).toList();
    final statusAlert = _highestPriorityAlert(preferredAlerts);
    final newAlerts = preferredAlerts
        .where((alert) => !_knownAlertIds.contains(alert.id))
        .toList();

    if (!mounted) return;
    setState(() {
      _alerts = preferredAlerts;
      _statusAlert = statusAlert;
      _statusMessage = statusAlert?.message ?? statusMessage;
      _knownAlertIds.addAll(preferredAlerts.map((alert) => alert.id));
      _isLoading = false;
    });

    if (notifyNew) {
      for (final alert in newAlerts.where((alert) => alert.shouldNotify)) {
        await NotificationService.instance.showFloodAlert(
          id: alert.id.hashCode & 0x7fffffff,
          title: alert.title,
          body: alert.message,
        );
      }
    }
  }

  Future<_GeneratedAlertContext> _generatedContextAlerts() async {
    final alerts = <_AppAlert>[];
    final location = await _locationService.getSavedLocation();
    RiskAssessment? risk;
    HazardMapData? mapData;

    if (location != null) {
      try {
        final forecast = await _weatherService.getForecast(
          latitude: location.latitude,
          longitude: location.longitude,
        );
        risk = _riskService.assess(forecast, locationLabel: location.label);
        alerts.addAll(_weatherAlerts(risk, location));
      } catch (_) {
        // Weather is an input signal, not a hard dependency for community alerts.
      }
    }

    try {
      mapData = await _hazardMapService.load();
      alerts.addAll(_communityReportAlerts(mapData, location));
    } catch (_) {
      // Keep existing alerts usable even if community reports are unavailable.
    }

    return _GeneratedAlertContext(
      alerts: alerts,
      statusMessage: _statusMessageFor(risk, mapData, location),
    );
  }

  List<_AppAlert> _weatherAlerts(RiskAssessment risk, DeviceLocation location) {
    final alerts = <_AppAlert>[];
    if (risk.level == 'High Risk') {
      alerts.add(
        _AppAlert(
          id: 'risk-high-${_dayKey(DateTime.now())}',
          type: _AlertType.flood,
          level: _AlertLevel.warning,
          title: 'High flood risk nearby',
          message: risk.summary,
          location: location.label,
          createdAt: DateTime.now(),
          source: 'FloodGuard risk logic and Open-Meteo rainfall data',
          recommendedAction:
              'Avoid low-lying roads, monitor the Flood Map, and prepare to move to a safer area if local officials advise evacuation.',
          mapReportId: null,
          shouldNotify: true,
        ),
      );
    } else if (risk.level == 'Moderate Risk') {
      alerts.add(
        _AppAlert(
          id: 'risk-watch-${_dayKey(DateTime.now())}',
          type: _AlertType.weather,
          level: _AlertLevel.watch,
          title: 'Flood watch conditions',
          message: risk.summary,
          location: location.label,
          createdAt: DateTime.now(),
          source: 'FloodGuard risk logic and Open-Meteo rainfall data',
          recommendedAction:
              'Watch rain intensity and check reports before traveling through flood-prone roads.',
          mapReportId: null,
          shouldNotify: true,
        ),
      );
    }

    if (risk.forecastRainMm >= 25) {
      alerts.add(
        _AppAlert(
          id: 'rain-${risk.forecastRainMm.round()}-${_dayKey(DateTime.now())}',
          type: _AlertType.weather,
          level: risk.forecastRainMm >= 50
              ? _AlertLevel.warning
              : _AlertLevel.watch,
          title: 'Severe rainfall advisory',
          message:
              'Forecast rainfall may reach ${risk.forecastRainLabel} in your selected area.',
          location: location.label,
          createdAt: DateTime.now(),
          source: 'Open-Meteo rainfall forecast',
          recommendedAction:
              'Charge devices, secure important documents, and monitor official weather advisories.',
          mapReportId: null,
          shouldNotify: true,
        ),
      );
    }
    return alerts;
  }

  List<_AppAlert> _communityReportAlerts(
    HazardMapData mapData,
    DeviceLocation? location,
  ) {
    final reports =
        mapData.reports.where((item) => item.report.isActive).toList()
          ..sort((a, b) => b.report.createdAt.compareTo(a.report.createdAt));
    final floodReports = reports.where(
      (item) => _isFloodReport(item.report.type),
    );
    final hazardReports = reports.where(
      (item) => !_isFloodReport(item.report.type),
    );
    final alerts = <_AppAlert>[];

    if (floodReports.length >= 2) {
      alerts.add(
        _AppAlert(
          id: 'flood-cluster-${floodReports.length}-${_hourKey(DateTime.now())}',
          type: _AlertType.flood,
          level: _AlertLevel.warning,
          title: 'Multiple flood reports detected',
          message:
              '${floodReports.length} active flooded-location reports are visible on the Flood Map.',
          location: location?.label ?? 'Community map area',
          createdAt: floodReports.first.report.createdAt,
          source: 'FloodGuard community reports',
          recommendedAction:
              'Avoid affected roads and open the Flood Map before traveling.',
          mapReportId: floodReports.first.report.id,
          shouldNotify: true,
        ),
      );
    } else if (floodReports.length == 1) {
      final report = floodReports.first.report;
      alerts.add(
        _AppAlert(
          id: 'flood-report-${report.id}',
          type: _AlertType.flood,
          level: _levelForReport(report),
          title: 'Flood report nearby',
          message: '${report.displayType} reported at ${report.location}.',
          location: _shortLocation(report.location),
          createdAt: report.createdAt,
          source: report.source,
          recommendedAction:
              'Open the Flood Map to inspect the report before passing nearby roads.',
          mapReportId: report.id,
          shouldNotify: report.contributesToRisk,
        ),
      );
    }

    if (hazardReports.isNotEmpty) {
      final report = hazardReports.first.report;
      alerts.add(
        _AppAlert(
          id: 'hazard-report-${report.id}',
          type: _AlertType.hazard,
          level: _levelForReport(report),
          title: 'Community hazard update',
          message: '${report.displayType} reported at ${report.location}.',
          location: _shortLocation(report.location),
          createdAt: report.createdAt,
          source: report.source,
          recommendedAction:
              'Review the mapped hazard and avoid the affected area if conditions look unsafe.',
          mapReportId: report.id,
          shouldNotify: report.contributesToRisk,
        ),
      );
    }

    if (mapData.facilities.isNotEmpty &&
        (floodReports.isNotEmpty || hazardReports.length >= 2)) {
      alerts.add(
        _AppAlert(
          id: 'evacuation-context-${_dayKey(DateTime.now())}',
          type: _AlertType.evacuation,
          level: _AlertLevel.info,
          title: 'Safety facilities available',
          message:
              '${mapData.facilities.length} mapped safety facilit${mapData.facilities.length == 1 ? 'y is' : 'ies are'} available for reference.',
          location: location?.label ?? 'Community map area',
          createdAt: DateTime.now(),
          source: 'FloodGuard safety facility data',
          recommendedAction:
              'Use evacuation centers only when travel is safe and follow LGU instructions.',
          mapReportId: null,
          shouldNotify: false,
        ),
      );
    }

    return alerts;
  }

  String _statusMessageFor(
    RiskAssessment? risk,
    HazardMapData? mapData,
    DeviceLocation? location,
  ) {
    if (risk?.level == 'High Risk') {
      final floodCount =
          mapData?.reports
              .where(
                (item) =>
                    item.report.isActive && _isFloodReport(item.report.type),
              )
              .length ??
          0;
      return floodCount > 0
          ? 'High flood risk and $floodCount flood report${floodCount == 1 ? '' : 's'} detected.'
          : 'High flood risk detected near ${location?.label ?? 'your selected area'}.';
    }
    final reportCount =
        mapData?.reports.where((item) => item.report.isActive).length ?? 0;
    if (reportCount > 0) {
      return '$reportCount active community report${reportCount == 1 ? '' : 's'} visible on the map.';
    }
    return 'No active critical alerts nearby.';
  }

  List<_AppAlert> _dedupeAlerts(List<_AppAlert> alerts) {
    final seen = <String>{};
    return alerts.where((alert) => seen.add(alert.id)).toList();
  }

  _AppAlert? _highestPriorityAlert(List<_AppAlert> alerts) {
    if (alerts.isEmpty) return null;
    final sorted = [...alerts]
      ..sort((a, b) {
        final level = b.level.index.compareTo(a.level.index);
        if (level != 0) return level;
        return b.createdAt.compareTo(a.createdAt);
      });
    return sorted.first;
  }

  bool _preferenceAllows(_AppAlert alert) {
    return switch (alert.type) {
      _AlertType.flood => _preferences[_AlertPreference.floodWarnings] ?? true,
      _AlertType.hazard => _preferences[_AlertPreference.nearbyHazards] ?? true,
      _AlertType.weather =>
        _preferences[_AlertPreference.severeRainfall] ?? true,
      _AlertType.evacuation =>
        _preferences[_AlertPreference.evacuationAdvisories] ?? true,
      _AlertType.community =>
        _preferences[_AlertPreference.communityUpdates] ?? false,
    };
  }

  Future<void> _setPreference(_AlertPreference preference, bool enabled) async {
    setState(() => _preferences[preference] = enabled);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_prefsPrefix.${preference.name}', enabled);
    await _saveRemotePreferences();
    await _refreshAlerts(notifyNew: false);
  }

  Future<void> _saveRemotePreferences() async {
    try {
      await NotificationService.instance.saveNotificationPreferences(
        floodWarnings: _preferences[_AlertPreference.floodWarnings] ?? true,
        nearbyHazards: _preferences[_AlertPreference.nearbyHazards] ?? true,
        severeRainfall: _preferences[_AlertPreference.severeRainfall] ?? true,
        evacuationAdvisories:
            _preferences[_AlertPreference.evacuationAdvisories] ?? true,
        communityUpdates:
            _preferences[_AlertPreference.communityUpdates] ?? false,
      );
    } catch (_) {
      // Device preferences still work when account sync is unavailable.
    }
  }

  Future<void> _markAllAsRead() async {
    setState(() {
      _readAlertIds.addAll(_alerts.map((alert) => alert.id));
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_readAlertsKey, _readAlertIds.toList());
  }

  Future<void> _markRead(String alertId) async {
    if (!_readAlertIds.add(alertId)) return;
    setState(() {});
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_readAlertsKey, _readAlertIds.toList());
  }

  Future<void> _sendTestAlert() async {
    final permitted = await NotificationService.instance.requestPermission();
    final enabled = await NotificationService.instance
        .areNotificationsEnabled();
    if (!permitted || !enabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notifications are disabled. Enable them in system settings to receive alerts.',
          ),
        ),
      );
      return;
    }
    await NotificationService.instance.showDemoFloodWatch();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Test alert sent.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alerts'),
      actions: [
        if (_alerts.any((alert) => !_readAlertIds.contains(alert.id)))
          TextButton(onPressed: _markAllAsRead, child: const Text('Read all')),
        IconButton(
          onPressed: _isLoading ? null : () => _refreshAlerts(notifyNew: false),
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh alerts',
        ),
      ],
    ),
    bottomNavigationBar: const AppBottomNav(index: 1),
    body: RefreshIndicator(
      onRefresh: () => _refreshAlerts(notifyNew: false),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _currentStatusCard(),
          const SizedBox(height: 18),
          _recentAlertsSection(),
          const SizedBox(height: 18),
          _notificationPreferencesCard(),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _sendTestAlert,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Send Test Alert'),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _currentStatusCard() {
    final alert = _statusAlert;
    return Card(
      color: alert == null
          ? const Color(0xFFF0FDF4)
          : _levelColor(alert.level).withValues(alpha: .08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor:
                  (alert == null
                          ? const Color(0xFF16A34A)
                          : _levelColor(alert.level))
                      .withValues(alpha: .14),
              child: Icon(
                alert == null
                    ? Icons.check_circle_outline
                    : _typeIcon(alert.type),
                color: alert == null
                    ? const Color(0xFF16A34A)
                    : _levelColor(alert.level),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Alert Status',
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alert?.title ?? 'No active critical alerts nearby',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 36),
                      child: LinearProgressIndicator(minHeight: 4),
                    )
                  else
                    Text(_statusMessage ?? 'You are all caught up.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentAlertsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            'Recent Alerts',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (!_isLoading)
            Text(
              '${_alerts.length}',
              style: const TextStyle(
                color: AppTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (_isLoading)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (_alerts.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.notifications_none, color: AppTheme.blue),
            title: Text('No recent alerts'),
            subtitle: Text(
              'You are all caught up. FloodGuard will notify you when important flood or hazard updates are detected.',
            ),
          ),
        )
      else
        ..._alerts.map(_alertCard),
    ],
  );

  Widget _alertCard(_AppAlert alert) {
    final unread = !_readAlertIds.contains(alert.id);
    return Card(
      color: unread ? _levelColor(alert.level).withValues(alpha: .06) : null,
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: _levelColor(alert.level).withValues(alpha: .14),
              child: Icon(
                _typeIcon(alert.type),
                color: _levelColor(alert.level),
              ),
            ),
            if (unread)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _levelColor(alert.level),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          alert.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_typeLabel(alert.type)} - ${_levelLabel(alert.level)}\n'
          '${alert.message}\n'
          '${alert.location} - ${_formatAlertTime(alert.createdAt)}',
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showAlertDetails(alert),
      ),
    );
  }

  Widget _notificationPreferencesCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                color: AppTheme.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Notification Preferences',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final preference in _AlertPreference.values)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(_preferenceTitle(preference)),
              value: _preferences[preference] ?? false,
              onChanged: (value) => _setPreference(preference, value),
            ),
        ],
      ),
    ),
  );

  void _showAlertDetails(_AppAlert alert) {
    _markRead(alert.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .55,
        minChildSize: .35,
        maxChildSize: .9,
        builder: (context, controller) => SafeArea(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5DEEC),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: _levelColor(
                      alert.level,
                    ).withValues(alpha: .14),
                    child: Icon(
                      _typeIcon(alert.type),
                      color: _levelColor(alert.level),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _pill(_typeLabel(alert.type), AppTheme.blue),
                            _pill(
                              _levelLabel(alert.level),
                              _levelColor(alert.level),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _detail('Description', alert.message),
              _detail('Affected Location', alert.location),
              _detail('Time', _formatAlertTime(alert.createdAt)),
              _detail('Source', alert.source),
              _detail('Recommended', alert.recommendedAction),
              const SizedBox(height: 10),
              if (alert.mapReportId != null ||
                  alert.type != _AlertType.community)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      this.context,
                      MaterialPageRoute<void>(
                        builder: (_) => EvacuationCentersScreen(
                          focusReportId: alert.mapReportId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View on Map'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.muted,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .2)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
    ),
  );

  bool _isFloodReport(HazardType type) =>
      type == HazardType.floodedRoad || type == HazardType.overflowingCanal;

  _AlertLevel _levelForReport(HazardReport report) {
    if (report.severity == 'Critical') return _AlertLevel.critical;
    if (report.severity == 'High') return _AlertLevel.warning;
    if (report.severity == 'Moderate') return _AlertLevel.watch;
    return _AlertLevel.info;
  }

  String _shortLocation(String location) {
    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'Mapped location';
    return parts.join(', ');
  }

  String _formatAlertTime(DateTime createdAt) {
    final difference = DateTime.now().difference(createdAt);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} hr ago';
    final hour = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}, $hour:$minute $period';
  }

  String _dayKey(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

  String _hourKey(DateTime time) => '${_dayKey(time)}-${time.hour}';

  Color _levelColor(_AlertLevel level) => switch (level) {
    _AlertLevel.info => AppTheme.blue,
    _AlertLevel.watch => const Color(0xFFCA8A04),
    _AlertLevel.warning => const Color(0xFFF97316),
    _AlertLevel.critical => const Color(0xFFDC2626),
  };

  IconData _typeIcon(_AlertType type) => switch (type) {
    _AlertType.flood => Icons.water_damage_outlined,
    _AlertType.hazard => Icons.warning_amber_outlined,
    _AlertType.weather => Icons.thunderstorm_outlined,
    _AlertType.evacuation => Icons.home_work_outlined,
    _AlertType.community => Icons.campaign_outlined,
  };

  String _typeLabel(_AlertType type) => switch (type) {
    _AlertType.flood => 'Flood Alert',
    _AlertType.hazard => 'Hazard Alert',
    _AlertType.weather => 'Weather Advisory',
    _AlertType.evacuation => 'Evacuation Advisory',
    _AlertType.community => 'Community Report Update',
  };

  String _levelLabel(_AlertLevel level) => switch (level) {
    _AlertLevel.info => 'Info',
    _AlertLevel.watch => 'Watch',
    _AlertLevel.warning => 'Warning',
    _AlertLevel.critical => 'Critical',
  };

  String _preferenceTitle(_AlertPreference preference) => switch (preference) {
    _AlertPreference.floodWarnings => 'Flood warnings',
    _AlertPreference.nearbyHazards => 'Nearby hazard reports',
    _AlertPreference.severeRainfall => 'Severe rainfall alerts',
    _AlertPreference.evacuationAdvisories => 'Evacuation advisories',
    _AlertPreference.communityUpdates => 'Community report updates',
  };
}

enum _AlertType { flood, hazard, weather, evacuation, community }

enum _AlertLevel { info, watch, warning, critical }

enum _AlertPreference {
  floodWarnings,
  nearbyHazards,
  severeRainfall,
  evacuationAdvisories,
  communityUpdates,
}

class _GeneratedAlertContext {
  const _GeneratedAlertContext({
    required this.alerts,
    required this.statusMessage,
  });

  final List<_AppAlert> alerts;
  final String statusMessage;
}

class _AppAlert {
  const _AppAlert({
    required this.id,
    required this.type,
    required this.level,
    required this.title,
    required this.message,
    required this.location,
    required this.createdAt,
    required this.source,
    required this.recommendedAction,
    required this.mapReportId,
    required this.shouldNotify,
  });

  factory _AppAlert.fromFloodAlert(FloodAlert alert) => _AppAlert(
    id: 'official-${alert.id}',
    type: _AlertType.flood,
    level: _levelFromSeverity(alert.severity),
    title: alert.title,
    message: alert.message,
    location: alert.area ?? 'Affected area',
    createdAt: alert.createdAt,
    source: 'FloodGuard alert feed',
    recommendedAction:
        'Review the alert details and follow local authority instructions for your area.',
    mapReportId: null,
    shouldNotify: true,
  );

  final String id;
  final _AlertType type;
  final _AlertLevel level;
  final String title;
  final String message;
  final String location;
  final DateTime createdAt;
  final String source;
  final String recommendedAction;
  final String? mapReportId;
  final bool shouldNotify;

  static _AlertLevel _levelFromSeverity(String severity) {
    final normalized = severity.toLowerCase();
    if (normalized.contains('critical')) return _AlertLevel.critical;
    if (normalized.contains('warning') || normalized.contains('high')) {
      return _AlertLevel.warning;
    }
    if (normalized.contains('watch') || normalized.contains('moderate')) {
      return _AlertLevel.watch;
    }
    return _AlertLevel.info;
  }
}
