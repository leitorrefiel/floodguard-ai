import 'package:flutter/material.dart';

import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class ForecastScreen extends StatefulWidget {
  const ForecastScreen({super.key});

  @override
  State<ForecastScreen> createState() => _ForecastScreenState();
}

class _ForecastScreenState extends State<ForecastScreen> {
  static const _baliwagLatitude = 14.9547;
  static const _baliwagLongitude = 120.8969;

  final _weatherService = WeatherService();
  WeatherForecastResponse? _forecast;
  String? _error;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadForecast();
  }

  Future<void> _loadForecast() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final forecast = await _weatherService.getForecast(
        latitude: _baliwagLatitude,
        longitude: _baliwagLongitude,
      );
      if (!mounted) return;
      setState(() => _forecast = forecast);
    } on WeatherException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Forecast is temporarily unavailable.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Forecast'),
      actions: [
        IconButton(
          onPressed: _isLoading ? null : _loadForecast,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh forecast',
        ),
      ],
    ),
    bottomNavigationBar: const AppBottomNav(index: 2),
    body: RefreshIndicator(
      onRefresh: _loadForecast,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_isLoading)
            const _LoadingCard()
          else if (_error != null)
            _ErrorCard(onRetry: _loadForecast)
          else if (_forecast != null) ...[
            _SectionTitle('Current Conditions'),
            const SizedBox(height: 8),
            _CurrentWeatherCard(forecast: _forecast!),
            const SizedBox(height: 16),
            _RainOutlookCard(forecast: _forecast!),
            const SizedBox(height: 16),
            _SectionTitle('3-Day Forecast'),
            const SizedBox(height: 8),
            ..._forecast!.days.map(_ForecastCard.new),
            const SizedBox(height: 12),
            _WeatherSourceFooter(forecast: _forecast!),
          ],
        ],
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
  );
}

class _CurrentWeatherCard extends StatelessWidget {
  const _CurrentWeatherCard({required this.forecast});

  final WeatherForecastResponse forecast;

  @override
  Widget build(BuildContext context) {
    final current = forecast.current;
    final conditionCode = forecast.days.isEmpty
        ? 0
        : forecast.days.first.weatherCode;
    return Card(
      color: AppTheme.paleBlue,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  child: Icon(
                    _icon(conditionCode),
                    color: AppTheme.blue,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Baliwag, Bulacan',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${current.temperatureCelsius.toStringAsFixed(1)} C',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        _weatherLabel(conditionCode),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricBlock(
                    label: 'Rain now',
                    value: '${current.precipitationMm.toStringAsFixed(1)} mm',
                  ),
                ),
                Expanded(
                  child: _MetricBlock(
                    label: 'Monitoring priority',
                    value: _monitoringPriority(current.precipitationMm),
                    valueColor: _concernColor(current.precipitationMm),
                  ),
                ),
              ],
            ),
            if (current.observedAt.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Updated ${_timeLabel(current.observedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.black54),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: TextStyle(fontWeight: FontWeight.w800, color: valueColor),
      ),
    ],
  );
}

class _RainOutlookCard extends StatelessWidget {
  const _RainOutlookCard({required this.forecast});

  final WeatherForecastResponse forecast;

  @override
  Widget build(BuildContext context) {
    final wettest = forecast.days.reduce(
      (value, element) =>
          element.precipitationMm > value.precipitationMm ? element : value,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop_outlined, color: AppTheme.blue),
                const SizedBox(width: 8),
                Text(
                  'Rain Outlook',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricBlock(
                    label: 'Highest expected rainfall',
                    value: '${wettest.precipitationMm.toStringAsFixed(1)} mm',
                  ),
                ),
                Expanded(
                  child: _MetricBlock(
                    label: _dateLabel(wettest.date),
                    value: _weatherLabel(wettest.weatherCode),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Monitor FloodGuard alerts and reported flooded areas if conditions worsen.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard(this.day);

  final WeatherForecastDay day;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.paleBlue,
            child: Icon(_icon(day.weatherCode), color: AppTheme.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dateLabel(day.date),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(_weatherLabel(day.weatherCode)),
                const SizedBox(height: 4),
                Text(
                  '${day.precipitationMm.toStringAsFixed(1)} mm expected rainfall',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(_rainfallConcern(day.precipitationMm)),
                    if (day.precipitationProbabilityMax != null)
                      Text('Rain chance ${day.precipitationProbabilityMax}%'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${day.minTemperatureCelsius.toStringAsFixed(0)}-'
            '${day.maxTemperatureCelsius.toStringAsFixed(0)} C',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ],
      ),
    ),
  );
}

class _WeatherSourceFooter extends StatelessWidget {
  const _WeatherSourceFooter({required this.forecast});

  final WeatherForecastResponse forecast;

  @override
  Widget build(BuildContext context) {
    final observedAt = forecast.current.observedAt;
    final updated = observedAt.isEmpty
        ? ''
        : ' - Updated ${_timeLabel(observedAt)}';
    return Text(
      'Weather data: Open-Meteo$updated',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Colors.black54,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Updating forecast...')),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF5F5),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.warning_amber_rounded, color: Colors.red),
            title: Text('Forecast is temporarily unavailable.'),
          ),
          const Text('Please check your connection and try again.'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
          ),
        ],
      ),
    ),
  );
}

String _dateLabel(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final today = DateTime.now();
  final localToday = DateTime(today.year, today.month, today.day);
  final localDate = DateTime(date.year, date.month, date.day);
  final difference = localDate.difference(localToday).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Tomorrow';
  return '${_weekdayName(date.weekday)}, ${_monthName(date.month)} ${date.day}';
}

String _timeLabel(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
}

String _weatherLabel(int code) {
  if (code == 0) return 'Clear';
  if ([1, 2, 3].contains(code)) return 'Cloudy';
  if ([45, 48].contains(code)) return 'Fog';
  if ([51, 53, 55, 56, 57].contains(code)) return 'Drizzle';
  if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) return 'Rain';
  if ([95, 96, 99].contains(code)) return 'Thunderstorm';
  return 'Changing weather';
}

String _monitoringPriority(double precipitation) {
  if (precipitation >= 20) return 'High flood monitoring priority';
  if (precipitation >= 5) return 'Moderate flood monitoring priority';
  return 'Low flood monitoring priority';
}

String _rainfallConcern(double precipitation) {
  if (precipitation >= 20) return 'Heavy rainfall expected';
  if (precipitation >= 5) return 'Moderate rainfall concern';
  return 'Low rainfall concern';
}

Color _concernColor(double precipitation) {
  if (precipitation >= 20) return Colors.red;
  if (precipitation >= 5) return const Color(0xFFF59E0B);
  return Colors.green;
}

IconData _icon(int code) {
  if (code == 0) return Icons.wb_sunny_outlined;
  if ([95, 96, 99].contains(code)) return Icons.thunderstorm_outlined;
  if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) {
    return Icons.water_drop_outlined;
  }
  if ([51, 53, 55, 56, 57].contains(code)) return Icons.grain_outlined;
  return Icons.cloud_outlined;
}

String _weekdayName(int weekday) {
  const names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return names[weekday - 1];
}

String _monthName(int month) {
  const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return names[month - 1];
}
