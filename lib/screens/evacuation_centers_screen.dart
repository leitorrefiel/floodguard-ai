import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class EvacuationCentersScreen extends StatelessWidget {
  const EvacuationCentersScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Evacuation Centers')),
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 190,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Stack(
            children: [
              Center(
                child: Icon(Icons.map_outlined, size: 90, color: AppTheme.blue),
              ),
              Positioned(
                left: 35,
                top: 35,
                child: Icon(Icons.location_on, color: AppTheme.blue, size: 36),
              ),
              Positioned(
                right: 55,
                bottom: 35,
                child: Icon(Icons.home, color: Colors.green, size: 38),
              ),
              Positioned(
                bottom: 12,
                left: 16,
                child: Text(
                  'Safe route preview • Map integration in a future build',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Nearby Evacuation Centers',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const _CenterCard(
          name: 'Baliwag City Hall Evacuation Center',
          address: 'Baliwag, Bulacan',
          detail: '0.8 km away • Open • 350 / 500 capacity',
          recommended: true,
        ),
        const _CenterCard(
          name: 'Baliwag North Central School',
          address: 'Baliwag, Bulacan',
          detail: '1.6 km away • Open • 280 / 400 capacity',
        ),
        const _CenterCard(
          name: 'Baliwag Sports Complex',
          address: 'Baliwag, Bulacan',
          detail: '2.4 km away • Limited • 120 / 300 capacity',
        ),
        const SizedBox(height: 10),
        Card(
          color: const Color(0xFFF1FBF4),
          child: ListTile(
            leading: const Icon(Icons.shield_outlined, color: Colors.green),
            title: const Text('Safe Route'),
            subtitle: const Text('0.8 km • estimated travel time: 3–5 minutes'),
            trailing: FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Navigation will be connected to a map service.',
                  ),
                ),
              ),
              child: const Text('Navigate'),
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.phone, color: Colors.red),
            title: Text('Emergency Hotline'),
            subtitle: Text('Local DRRMO / Emergency Hotline'),
            trailing: Text('911', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    ),
  );
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({
    required this.name,
    required this.address,
    required this.detail,
    this.recommended = false,
  });
  final String name, address, detail;
  final bool recommended;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: recommended
            ? const Color(0xFFE8F8ED)
            : AppTheme.paleBlue,
        child: Icon(
          Icons.home_work_outlined,
          color: recommended ? Colors.green : AppTheme.blue,
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('$address\n$detail'),
      isThreeLine: true,
      trailing: OutlinedButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Directions to $name will open here.')),
        ),
        child: const Text('Navigate'),
      ),
    ),
  );
}
