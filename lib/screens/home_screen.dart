import 'package:flutter/material.dart';

import '../services/risk_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/metric_tile.dart';
import 'alerts_screen.dart';
import 'evacuation_centers_screen.dart';
import 'report_hazard_screen.dart';
import 'risk_details_screen.dart';
import 'safety_tips_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const risk = RiskService();
    return Scaffold(
      bottomNavigationBar: const AppBottomNav(index: 0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppTheme.paleBlue,
                  child: Icon(Icons.shield_outlined, color: AppTheme.blue),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FloodGuard AI',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                      Text(
                        'AI-Powered Flood Prediction & Early Warning',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AlertsScreen(),
                    ),
                  ),
                  icon: const Icon(
                    Icons.notifications_none,
                    color: AppTheme.navy,
                  ),
                  tooltip: 'View alerts',
                ),
              ],
            ),
            const SizedBox(height: 20),
            _locationCard(context),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const RiskDetailsScreen(),
                ),
              ),
              child: Card(
                color: const Color(0xFFF0F6FF),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FLOOD RISK',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.blue,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        risk.currentRisk,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      const Text(
                        'Conditions could lead to flooding. Stay alert and monitor updates.',
                      ),
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(
                        value: .58,
                        minHeight: 8,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          MetricTile(
                            icon: Icons.cloudy_snowing,
                            label: 'Rainfall (24h)',
                            value: '36 mm',
                            caption: 'Moderate',
                          ),
                          MetricTile(
                            icon: Icons.cloud,
                            label: 'Weather',
                            value: '26°C',
                            caption: 'Light Rain',
                          ),
                          MetricTile(
                            icon: Icons.water,
                            label: 'Water level',
                            value: '1.2 m',
                            caption: 'Rising',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFF59E0B),
                ),
                title: Text('Flood Watch'),
                subtitle: Text(
                  'Moderate to heavy rainfall expected within the next 24 hours.',
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AlertsScreen()),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Quick Actions',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _quickAction(
                  context,
                  Icons.map_outlined,
                  'Flood\nMap',
                  const EvacuationCentersScreen(),
                ),
                _quickAction(
                  context,
                  Icons.home_work_outlined,
                  'Evacuation\nCenters',
                  const EvacuationCentersScreen(),
                ),
                _quickAction(
                  context,
                  Icons.report_outlined,
                  'Report\nHazard',
                  const ReportHazardScreen(),
                ),
                _quickAction(
                  context,
                  Icons.health_and_safety_outlined,
                  'Safety\nTips',
                  const SafetyTipsScreen(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Community Reports',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AlertsScreen(),
                    ),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(Icons.directions_car_filled_outlined),
                ),
                title: Text('Flooded Road'),
                subtitle: Text('Lapasan, Cagayan de Oro City • Today, 8:45 AM'),
                trailing: Chip(label: Text('Verified')),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ReportHazardScreen(),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(Icons.water_damage_outlined)),
                title: Text('Blocked Drainage'),
                subtitle: Text(
                  'Kauswagan, Cagayan de Oro City • Today, 7:30 AM',
                ),
                trailing: Chip(label: Text('Verified')),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ReportHazardScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationCard(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.location_on, color: AppTheme.blue),
      title: const Text('Current Location', style: TextStyle(fontSize: 12)),
      subtitle: const Text(
        'Cagayan de Oro City, PH',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      trailing: const Icon(Icons.my_location, color: AppTheme.blue),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location selected: Cagayan de Oro City, PH.'),
        ),
      ),
    ),
  );

  Widget _quickAction(
    BuildContext context,
    IconData icon,
    String label,
    Widget page,
  ) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => page),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE3EAF4)),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppTheme.blue),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
