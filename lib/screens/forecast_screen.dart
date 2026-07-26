import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class ForecastScreen extends StatelessWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Forecast')),
    bottomNavigationBar: const AppBottomNav(index: 2),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          color: AppTheme.paleBlue,
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.cloudy_snowing, color: AppTheme.blue, size: 48),
                SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cagayan de Oro City',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text('26°C • Light Rain'),
                    Text(
                      'Moderate flood risk',
                      style: TextStyle(color: Color(0xFFF59E0B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '3-Day Outlook',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const _ForecastCard(
          day: 'Today',
          weather: 'Light Rain',
          temp: '26°C',
          rain: '36 mm',
          icon: Icons.cloudy_snowing,
        ),
        const _ForecastCard(
          day: 'Tomorrow',
          weather: 'Rain Showers',
          temp: '27°C',
          rain: '48 mm',
          icon: Icons.thunderstorm,
        ),
        const _ForecastCard(
          day: 'Monday',
          weather: 'Cloudy',
          temp: '28°C',
          rain: '12 mm',
          icon: Icons.cloud,
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Forecast data refresh requested.')),
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh Forecast'),
        ),
      ],
    ),
  );
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({
    required this.day,
    required this.weather,
    required this.temp,
    required this.rain,
    required this.icon,
  });
  final String day;
  final String weather;
  final String temp;
  final String rain;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: AppTheme.paleBlue,
        child: Icon(icon, color: AppTheme.blue),
      ),
      title: Text(day, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('$weather • Rainfall: $rain'),
      trailing: Text(
        temp,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
    ),
  );
}
