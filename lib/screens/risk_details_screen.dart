import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import 'evacuation_centers_screen.dart';

class RiskDetailsScreen extends StatelessWidget {
  const RiskDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flood Risk Details')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.location_on, color: AppTheme.blue),
            title: Text('Current Location', style: TextStyle(fontSize: 12)),
            subtitle: Text(
              'Baliwag, Bulacan, PH',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFFFF4F4),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'FLOOD RISK',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'High Risk',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFDC2626),
                  ),
                ),
                const Text(
                  'Heavy rainfall and rising water levels increase the likelihood of flooding. Take action now and stay safe.',
                ),
                const SizedBox(height: 18),
                const LinearProgressIndicator(
                  value: .85,
                  minHeight: 11,
                  color: Colors.red,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(
                      child: _Info(
                        label: 'Rainfall (24h)',
                        value: '78 mm',
                        icon: Icons.thunderstorm,
                      ),
                    ),
                    Expanded(
                      child: _Info(
                        label: 'Water level',
                        value: '2.3 m',
                        icon: Icons.water,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: Icon(Icons.warning_rounded, color: Colors.red),
            title: Text('Flood Alert'),
            subtitle: Text(
              'Possible flooding within the next 6 hours. Seek higher ground and follow local advisories.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Recommended Actions',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.backpack_outlined, color: AppTheme.blue),
                title: Text('Prepare Your Go-Bag'),
                subtitle: Text(
                  'Include water, clothes, medicines, and documents.',
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.battery_charging_full,
                  color: AppTheme.blue,
                ),
                title: Text('Charge Your Devices'),
                subtitle: Text(
                  'Keep your phone charged and bring a power bank.',
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.directions_walk, color: AppTheme.blue),
                title: Text('Avoid Low-Lying Areas'),
                subtitle: Text('Do not walk or drive through floodwater.'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const EvacuationCentersScreen(),
            ),
          ),
          icon: const Icon(Icons.home_work_outlined),
          label: const Text('View Evacuation Centers'),
        ),
      ],
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Colors.red),
      const SizedBox(width: 7),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    ],
  );
}
