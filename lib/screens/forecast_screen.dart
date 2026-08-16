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
        setState(() => _error = 'Check your internet connection and retry.');
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
          tooltip: 'Refresh API data',
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
            _ErrorCard(message: _error!, onRetry: _loadForecast)
          else if (_forecast != null) ...[
            _CurrentWeatherCard(forecast: _forecast!),
            const SizedBox(height: 20),
            Text(
              '3-Day API Forecast',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._forecast!.days.map(_ForecastCard.new),
            const SizedBox(height: 20),
            _ApiDetailsCard(forecast: _forecast!),
          ],
        ],
      ),
    ),
  );
}

class _CurrentWeatherCard extends StatelessWidget {
  const _CurrentWeatherCard({required this.forecast});

  final WeatherForecastResponse forecast;

  @override
  Widget build(BuildContext context) {
    final current = forecast.current;
    return Card(
      color: AppTheme.paleBlue,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.cloudy_snowing, color: AppTheme.blue, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Baliwag, Bulacan',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${current.temperatureCelsius.toStringAsFixed(1)} C, '
                    'precipitation ${current.precipitationMm.toStringAsFixed(1)} mm',
                  ),
                  Text(
                    _riskLabel(current.precipitationMm),
                    style: TextStyle(
                      color: _riskColor(current.precipitationMm),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (current.observedAt.isNotEmpty)
                    Text(
                      'Observed: ${current.observedAt}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _riskLabel(double precipitation) {
    if (precipitation >= 20) return 'High flood monitoring priority';
    if (precipitation >= 5) return 'Moderate flood monitoring priority';
    return 'Low flood monitoring priority';
  }

  Color _riskColor(double precipitation) {
    if (precipitation >= 20) return Colors.red;
    if (precipitation >= 5) return const Color(0xFFF59E0B);
    return Colors.green;
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard(this.day);

  final WeatherForecastDay day;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.paleBlue,
        child: Icon(_icon(day.weatherCode), color: AppTheme.blue),
      ),
      title: Text(_dateLabel(day.date)),
      subtitle: Text(
        '${_weatherLabel(day.weatherCode)} - rainfall '
        '${day.precipitationMm.toStringAsFixed(1)} mm',
      ),
      trailing: Text(
        '${day.minTemperatureCelsius.toStringAsFixed(0)}-'
        '${day.maxTemperatureCelsius.toStringAsFixed(0)} C',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
    ),
  );

  String _dateLabel(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    final today = DateTime.now();
    final localToday = DateTime(today.year, today.month, today.day);
    final localDate = DateTime(date.year, date.month, date.day);
    final difference = localDate.difference(localToday).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    return value;
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

  IconData _icon(int code) {
    if (code == 0) return Icons.wb_sunny_outlined;
    if ([95, 96, 99].contains(code)) return Icons.thunderstorm_outlined;
    if ([61, 63, 65, 66, 67, 80, 81, 82].contains(code)) {
      return Icons.water_drop_outlined;
    }
    return Icons.cloud_outlined;
  }
}

class _ApiDetailsCard extends StatelessWidget {
  const _ApiDetailsCard({required this.forecast});

  final WeatherForecastResponse forecast;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.api_outlined, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(
                'API Request',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Method: GET'),
          Text('Endpoint: ${forecast.endpoint}'),
          const SizedBox(height: 12),
          const Text(
            'JSON Response Sample',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              forecast.jsonSample,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    ),
  );
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
          Expanded(child: Text('Loading live forecast from Open-Meteo...')),
        ],
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
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
            title: Text('Unable to load forecast'),
          ),
          Text(message),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
