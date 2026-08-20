import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class SafetyTipsScreen extends StatefulWidget {
  const SafetyTipsScreen({super.key});
  @override
  State<SafetyTipsScreen> createState() => _SafetyTipsScreenState();
}

class _SafetyTipsScreenState extends State<SafetyTipsScreen> {
  final _items = <String, bool>{
    'Flashlight': false,
    'Drinking Water': false,
    'Non-Perishable Food': false,
    'Power Bank': false,
    'First Aid Kit': false,
    'Important Documents': false,
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Safety Tips')),
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.fact_check_outlined, color: AppTheme.blue),
                    SizedBox(width: 8),
                    Text(
                      'Emergency Preparedness Checklist',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const Text('Check off essential items you have ready.'),
                const SizedBox(height: 8),
                ..._items.entries.map(
                  (entry) => CheckboxListTile(
                    value: entry.value,
                    onChanged: (value) =>
                        setState(() => _items[entry.key] = value ?? false),
                    title: Text(entry.key),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Checklist saved for this session.'),
                    ),
                  ),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Checklist'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before a Flood',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: AppTheme.blue,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '- Stay informed and monitor local alerts.\n- Secure important items and move to higher ground.\n- Turn off electrical appliances and utilities if needed.\n- Prepare an evacuation plan and safe meeting place.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.phone, color: Color(0xFFF97316)),
            title: Text('Emergency Hotlines'),
            subtitle: Text(
              '911 National Emergency\nNDRRMC: (02) 8911-1406\nPhilippine Red Cross: 143 / (02) 8790-2300',
            ),
            isThreeLine: true,
          ),
        ),
      ],
    ),
  );
}
