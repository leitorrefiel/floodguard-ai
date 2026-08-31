import 'package:flutter/material.dart';

import '../services/device_location_service.dart';
import '../services/risk_service.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';

class RiskDetailsScreen extends StatefulWidget {
  const RiskDetailsScreen({super.key});

  @override
  State<RiskDetailsScreen> createState() => _RiskDetailsScreenState();
}

class _RiskDetailsScreenState extends State<RiskDetailsScreen> {
  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  final _riskService = const RiskService();

  RiskAssessment? _assessment;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRisk();
  }

  Future<void> _loadRisk() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final location = await _locationService.getSavedLocation();
      if (location == null) {
        throw const LocationAccessException(
          'Set your location from Home first.',
        );
      }
      final forecast = await _weatherService.getForecast(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted) return;
      setState(() {
        _assessment = _riskService.assess(
          forecast,
          locationLabel: location.label,
        );
      });
    } on LocationAccessException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on WeatherException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load live flood risk.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Flood Risk Details'),
      actions: [
        IconButton(
          onPressed: _isLoading ? null : _loadRisk,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh risk',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_error != null)
          Card(
            color: const Color(0xFFFFF4F4),
            child: ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: const Text('Live risk unavailable'),
              subtitle: Text(_error!),
            ),
          )
        else if (!_isLoading)
          const SizedBox.shrink(),
        if (_isLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Loading live flood risk...')),
                ],
              ),
            ),
          )
        else if (_assessment != null)
          ..._riskContent(_assessment!),
      ],
    ),
  );

  List<Widget> _riskContent(RiskAssessment assessment) => [
    Card(
      color: _riskCardColor(assessment.level),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FLOOD RISK',
              style: TextStyle(
                color: AppTheme.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              assessment.level,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w800,
                color: _riskColor(assessment.level),
              ),
            ),
            Text(assessment.summary),
            const SizedBox(height: 18),
            LinearProgressIndicator(
              value: assessment.score / 100,
              minHeight: 11,
              color: _riskColor(assessment.level),
              borderRadius: const BorderRadius.all(Radius.circular(8)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Info(
                    label: 'Rain now',
                    value: assessment.currentRainLabel,
                    icon: Icons.thunderstorm,
                    color: _riskColor(assessment.level),
                  ),
                ),
                Expanded(
                  child: _Info(
                    label: 'Forecast rain',
                    value: assessment.forecastRainLabel,
                    icon: Icons.water,
                    color: _riskColor(assessment.level),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              assessment.observedAt.isEmpty
                  ? 'Source: Open-Meteo live forecast'
                  : 'Updated: ${assessment.observedAt}',
              style: const TextStyle(fontSize: 12, color: AppTheme.muted),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 12),
    Card(
      child: ListTile(
        leading: Icon(
          Icons.warning_rounded,
          color: _riskColor(assessment.level),
        ),
        title: Text('${assessment.level} Advisory'),
        subtitle: Text(assessment.summary),
      ),
    ),
    const SizedBox(height: 20),
    Text(
      'AI Analysis',
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(assessment.aiExplanation),
            const SizedBox(height: 12),
            for (final factor in assessment.riskFactors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 17,
                      color: AppTheme.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(factor)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 20),
    Text(
      'AI-Generated Actions',
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
    const SizedBox(height: 8),
    Card(
      child: Column(
        children: [
          for (var index = 0; index < assessment.actions.length; index++) ...[
            _ActionTile(action: assessment.actions[index]),
            if (index != assessment.actions.length - 1)
              const Divider(height: 1),
          ],
        ],
      ),
    ),
  ];

  Color _riskColor(String level) {
    if (level == 'High Risk') return const Color(0xFFDC2626);
    if (level == 'Moderate Risk') return const Color(0xFFF59E0B);
    if (level == 'Low Risk') return const Color(0xFF2563EB);
    return const Color(0xFF16A34A);
  }

  Color _riskCardColor(String level) {
    if (level == 'High Risk') return const Color(0xFFFFF4F4);
    if (level == 'Moderate Risk') return const Color(0xFFFFF8E6);
    if (level == 'Low Risk') return const Color(0xFFF0F6FF);
    return const Color(0xFFF0FDF4);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final RiskAction action;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(_iconFor(action.iconKey), color: AppTheme.blue),
    title: Text(action.title),
    subtitle: Text(action.description),
  );

  IconData _iconFor(String key) {
    switch (key) {
      case 'move_up':
        return Icons.upload_file_outlined;
      case 'route':
        return Icons.alt_route_outlined;
      case 'evacuate':
        return Icons.home_work_outlined;
      case 'bag':
        return Icons.backpack_outlined;
      case 'drainage':
        return Icons.water_drop_outlined;
      case 'phone':
        return Icons.phone_in_talk_outlined;
      case 'monitor':
      default:
        return Icons.notifications_active_outlined;
    }
  }
}

class _Info extends StatelessWidget {
  const _Info({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: color),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    ],
  );
}
