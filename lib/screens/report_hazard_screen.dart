import 'package:flutter/material.dart';

import '../models/hazard_report.dart';
import '../utils/app_theme.dart';

class ReportHazardScreen extends StatefulWidget {
  const ReportHazardScreen({super.key});
  @override
  State<ReportHazardScreen> createState() => _ReportHazardScreenState();
}

class _ReportHazardScreenState extends State<ReportHazardScreen> {
  HazardType _type = HazardType.floodedRoad;
  String _severity = 'Moderate';
  final _description = TextEditingController();
  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Report Hazard')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '1. Select Hazard Type',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: HazardType.values
              .map(
                (type) => ChoiceChip(
                  label: Text(_label(type)),
                  selected: _type == type,
                  avatar: Icon(_icon(type), color: AppTheme.blue),
                  onSelected: (_) => setState(() => _type = type),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        const Text(
          '2. Add Photo (Optional)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Photo upload will be added with device permissions.',
              ),
            ),
          ),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Tap to upload a photo\nPNG or JPG up to 10 MB',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          '3. Location (Auto-detected)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.location_on, color: AppTheme.blue),
            title: const Text('Baliwag, Bulacan, PH'),
            subtitle: const Text('14.95860° N, 120.88670° E'),
            trailing: TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Current location applied to report.'),
                ),
              ),
              child: const Text('Use Current'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '4. Severity Level',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        Wrap(
          spacing: 7,
          children: ['Low', 'Moderate', 'High', 'Critical']
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: _severity == value,
                  onSelected: (_) => setState(() => _severity = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        const Text(
          '5. Description (Optional)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Provide more details about the hazard...',
          ),
        ),
        const Card(
          color: AppTheme.paleBlue,
          child: ListTile(
            leading: Icon(Icons.info_outline, color: AppTheme.blue),
            title: Text(
              'Your report helps improve local flood awareness and response.',
            ),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Submit Report'),
        ),
      ],
    ),
  );
  void _submit() {
    final report = HazardReport(
      type: _type,
      severity: _severity,
      location: 'Baliwag, Bulacan, PH',
      description: _description.text,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_label(report.type)} report saved as a placeholder.'),
      ),
    );
  }

  String _label(HazardType type) => switch (type) {
    HazardType.floodedRoad => 'Flooded Road',
    HazardType.cloggedDrainage => 'Clogged Drainage',
    HazardType.blockedWaterway => 'Blocked Waterway',
    HazardType.overflowingCanal => 'Overflowing Canal',
  };
  IconData _icon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.directions_car_outlined,
    HazardType.cloggedDrainage => Icons.water_damage_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.water_outlined,
  };
}
