import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import '../services/device_location_service.dart';
import '../services/hazard_map_service.dart';
import '../services/risk_service.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class SafetyTipsScreen extends StatefulWidget {
  const SafetyTipsScreen({super.key});

  @override
  State<SafetyTipsScreen> createState() => _SafetyTipsScreenState();
}

class _SafetyTipsScreenState extends State<SafetyTipsScreen> {
  static const _checklistStorageKey = 'safety_tips_checklist';
  static const _customItemsStorageKey = 'safety_tips_custom_items';
  static const _defaultItems = [
    'Flashlight',
    'Drinking Water',
    'Non-Perishable Food',
    'Power Bank',
    'First Aid Kit',
    'Important Documents',
    'Medicines',
    'Emergency Contacts',
  ];

  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  final _riskService = const RiskService();
  final _hazardMapService = HazardMapService();

  final Map<String, bool> _items = {
    for (final item in _defaultItems) item: false,
  };
  final List<String> _customItems = [];

  DeviceLocation? _location;
  RiskAssessment? _risk;
  HazardMapData? _mapData;
  String? _statusError;
  bool _loadingStatus = true;
  bool _checklistExpanded = false;
  String _selectedPhase = 'before';

  int get _readyCount => _items.values.where((ready) => ready).length;
  double get _progress => _items.isEmpty ? 0 : _readyCount / _items.length;

  @override
  void initState() {
    super.initState();
    _restoreChecklist();
    _loadSafetyStatus();
  }

  Future<void> _restoreChecklist() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final customItems =
        preferences
            .getStringList(_customItemsStorageKey)
            ?.where((item) => item.trim().isNotEmpty)
            .map((item) => item.trim())
            .toSet()
            .toList() ??
        const <String>[];
    setState(() {
      _customItems
        ..clear()
        ..addAll(customItems);
      for (final item in customItems) {
        _items.putIfAbsent(item, () => false);
      }
      for (final item in _items.keys) {
        _items[item] =
            preferences.getBool('$_checklistStorageKey.$item') ?? _items[item]!;
      }
    });
  }

  Future<void> _setChecklistItem(String item, bool value) async {
    setState(() => _items[item] = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('$_checklistStorageKey.$item', value);
  }

  Future<void> _addCustomItem(String item) async {
    final trimmedItem = item.trim();
    if (trimmedItem.isEmpty) return;
    final exists = _items.keys.any(
      (existing) => existing.toLowerCase() == trimmedItem.toLowerCase(),
    );
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This checklist item already exists.')),
      );
      return;
    }

    setState(() {
      _customItems.add(trimmedItem);
      _items[trimmedItem] = false;
      _checklistExpanded = true;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_customItemsStorageKey, _customItems);
    await preferences.setBool('$_checklistStorageKey.$trimmedItem', false);
  }

  Future<void> _editCustomItem(String oldItem, String newItem) async {
    final trimmedItem = newItem.trim();
    if (trimmedItem.isEmpty || trimmedItem == oldItem) return;
    final exists = _items.keys.any(
      (existing) =>
          existing != oldItem &&
          existing.toLowerCase() == trimmedItem.toLowerCase(),
    );
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This checklist item already exists.')),
      );
      return;
    }

    final oldValue = _items[oldItem] ?? false;
    setState(() {
      final index = _customItems.indexOf(oldItem);
      if (index != -1) _customItems[index] = trimmedItem;
      _items
        ..remove(oldItem)
        ..[trimmedItem] = oldValue;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_customItemsStorageKey, _customItems);
    await preferences.remove('$_checklistStorageKey.$oldItem');
    await preferences.setBool('$_checklistStorageKey.$trimmedItem', oldValue);
  }

  Future<void> _deleteCustomItem(String item) async {
    setState(() {
      _customItems.remove(item);
      _items.remove(item);
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_customItemsStorageKey, _customItems);
    await preferences.remove('$_checklistStorageKey.$item');
  }

  Future<void> _loadSafetyStatus() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });

    DeviceLocation? savedLocation;
    RiskAssessment? risk;
    HazardMapData? mapData;
    String? statusError;

    try {
      savedLocation = await _locationService.getSavedLocation();
      if (savedLocation != null) {
        final forecast = await _weatherService.getForecast(
          latitude: savedLocation.latitude,
          longitude: savedLocation.longitude,
        );
        risk = _riskService.assess(
          forecast,
          locationLabel: savedLocation.label,
        );
      }
    } catch (_) {
      statusError = 'Live rainfall risk is temporarily unavailable.';
    }

    try {
      mapData = await _hazardMapService.load();
    } catch (_) {
      statusError ??= 'Community report status is temporarily unavailable.';
    }

    if (!mounted) return;
    setState(() {
      _location = savedLocation;
      _risk = risk;
      _mapData = mapData;
      _statusError = statusError;
      _loadingStatus = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Safety Tips'),
      actions: [
        IconButton(
          onPressed: _loadSafetyStatus,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh safety status',
        ),
      ],
    ),
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _currentStatusCard(),
        const SizedBox(height: 12),
        _checklistCard(),
        const SizedBox(height: 12),
        _recommendationsCard(),
        const SizedBox(height: 12),
        _floodTipsCard(),
        const SizedBox(height: 12),
        _hotlinesCard(),
      ],
    ),
  );

  Widget _currentStatusCard() {
    final reportCounts = _reportCounts();
    final risk = _risk;
    final hasReports =
        reportCounts.floodReports > 0 || reportCounts.communityHazards > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              icon: Icons.health_and_safety_outlined,
              title: 'Current Safety Status',
            ),
            const SizedBox(height: 10),
            if (_loadingStatus)
              const LinearProgressIndicator(minHeight: 5)
            else ...[
              Text(
                risk?.level ?? 'Safety status unavailable',
                style: TextStyle(
                  color: _riskColor(risk?.level),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _statusError ??
                    risk?.summary ??
                    (hasReports
                        ? 'Community reports are mapped nearby. Check the flood map before travel.'
                        : 'No mapped reports currently available.'),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusChip(
                    Icons.water_damage_outlined,
                    '${reportCounts.floodReports} flood reports',
                  ),
                  _statusChip(
                    Icons.warning_amber_outlined,
                    '${reportCounts.communityHazards} hazards',
                  ),
                  if (_nearestFacilityLabel() != null)
                    _statusChip(
                      Icons.home_work_outlined,
                      'Nearest safety facility: ${_nearestFacilityLabel()}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _checklistCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.fact_check_outlined,
            title: 'Emergency Preparedness Checklist',
            trailing: Text(
              '$_readyCount of ${_items.length}',
              style: const TextStyle(
                color: AppTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(_progress * 100).round()}% complete',
            style: const TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress,
            minHeight: 8,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            color: AppTheme.blue,
            backgroundColor: AppTheme.paleBlue,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  setState(() => _checklistExpanded = !_checklistExpanded),
              icon: AnimatedRotation(
                turns: _checklistExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down),
              ),
              label: Text(
                _checklistExpanded ? 'Hide Checklist' : 'Show Checklist',
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _checklistItems(),
            crossFadeState: _checklistExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    ),
  );

  Widget _checklistItems() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(height: 16),
      const Text(
        'Essential Items',
        style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.navy),
      ),
      const SizedBox(height: 4),
      for (final item in _defaultItems) _checklistTile(item),
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Custom Items',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppTheme.navy,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _showCustomItemDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Add Custom Item'),
          ),
        ],
      ),
      if (_customItems.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 2, bottom: 4),
          child: Text(
            'Add personal supplies you want to prepare.',
            style: TextStyle(color: AppTheme.muted),
          ),
        )
      else
        for (final item in _customItems) _checklistTile(item, custom: true),
    ],
  );

  Widget _checklistTile(String item, {bool custom = false}) => CheckboxListTile(
    value: _items[item] ?? false,
    onChanged: (value) => _setChecklistItem(item, value ?? false),
    title: Text(item),
    dense: true,
    contentPadding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    controlAffinity: ListTileControlAffinity.leading,
    secondary: custom
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _showCustomItemDialog(existingItem: item),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit item',
              ),
              IconButton(
                onPressed: () => _deleteCustomItem(item),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete item',
              ),
            ],
          )
        : null,
  );

  Future<void> _showCustomItemDialog({String? existingItem}) async {
    final controller = TextEditingController(text: existingItem ?? '');
    final itemName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existingItem == null
              ? 'Add preparedness item'
              : 'Edit preparedness item',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Item name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(existingItem == null ? 'Add Item' : 'Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (itemName == null) return;
    if (existingItem == null) {
      await _addCustomItem(itemName);
    } else {
      await _editCustomItem(existingItem, itemName);
    }
  }

  Widget _recommendationsCard() {
    final recommendations = _recommendations();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              icon: Icons.auto_awesome_outlined,
              title: 'AI Safety Recommendations',
            ),
            const SizedBox(height: 4),
            const Text(
              'Based on current FloodGuard information.',
              style: TextStyle(color: AppTheme.muted),
            ),
            const SizedBox(height: 10),
            for (final item in recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _priorityColor(
                        item.priority,
                      ).withValues(alpha: 0.12),
                      child: Icon(
                        item.icon,
                        color: _priorityColor(item.priority),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            item.reason,
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _floodTipsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.menu_book_outlined,
            title: 'Flood Safety Guide',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _phaseChip('before', 'Before Flood'),
              _phaseChip('during', 'During Flood'),
              _phaseChip('after', 'After Flood'),
            ],
          ),
          const SizedBox(height: 12),
          ..._phaseTips(_selectedPhase).map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppTheme.blue,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tip)),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _hotlinesCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            icon: Icons.phone_in_talk_outlined,
            title: 'Emergency Hotlines',
          ),
          const SizedBox(height: 8),
          _hotlineTile('Emergency', '911', '911'),
          _hotlineTile('Philippine Red Cross', '143', '143'),
          _hotlineTile('NDRRMC', '(02) 8911-1406', '0289111406'),
        ],
      ),
    ),
  );

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppTheme.blue, size: 22),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing],
    ],
  );

  Widget _statusChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: AppTheme.paleBlue,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppTheme.blue),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.navy,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _phaseChip(String value, String label) => ChoiceChip(
    selected: _selectedPhase == value,
    label: Text(label),
    onSelected: (_) => setState(() => _selectedPhase = value),
    labelStyle: TextStyle(
      color: _selectedPhase == value ? Colors.white : AppTheme.navy,
      fontWeight: FontWeight.w700,
    ),
    selectedColor: AppTheme.deepBlue,
    backgroundColor: Colors.white,
    side: const BorderSide(color: AppTheme.border),
  );

  Widget _hotlineTile(String label, String displayNumber, String number) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        leading: const CircleAvatar(
          backgroundColor: AppTheme.paleBlue,
          child: Icon(Icons.call_outlined, color: AppTheme.blue),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(displayNumber),
        trailing: IconButton(
          onPressed: () => _call(number),
          icon: const Icon(Icons.phone, color: AppTheme.deepBlue),
          tooltip: 'Call $label',
        ),
      );

  Future<void> _call(String number) async {
    final launched = await launchUrl(Uri(scheme: 'tel', path: number));
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to call $number on this device.')),
      );
    }
  }

  _ReportCounts _reportCounts() {
    final reports = _mapData?.reports.map((mapped) => mapped.report) ?? [];
    var floodReports = 0;
    var communityHazards = 0;
    for (final report in reports.where((report) => report.isActive)) {
      if (_isFloodReport(report.type)) {
        floodReports++;
      } else {
        communityHazards++;
      }
    }
    return _ReportCounts(floodReports, communityHazards);
  }

  bool _isFloodReport(HazardType type) =>
      type == HazardType.floodedRoad || type == HazardType.overflowingCanal;

  List<_SafetyRecommendation> _recommendations() {
    final items = <_SafetyRecommendation>[];
    final risk = _risk;
    final counts = _reportCounts();

    if (risk?.level == 'High Risk') {
      items.add(
        const _SafetyRecommendation(
          title: 'Prepare to move to safer ground',
          reason:
              'High flood risk is indicated. Follow official alerts and check evacuation options.',
          priority: _RecommendationPriority.high,
          icon: Icons.directions_walk_outlined,
        ),
      );
    } else if (risk != null && risk.forecastRainMm >= 25) {
      items.add(
        const _SafetyRecommendation(
          title: 'Prepare flood essentials early',
          reason:
              'Forecast rainfall may affect low-lying roads and drainage areas.',
          priority: _RecommendationPriority.high,
          icon: Icons.backpack_outlined,
        ),
      );
    }

    if (counts.floodReports > 0) {
      items.add(
        _SafetyRecommendation(
          title: 'Check reported flooded roads',
          reason:
              '${counts.floodReports} active flood report${counts.floodReports == 1 ? '' : 's'} mapped nearby.',
          priority: _RecommendationPriority.high,
          icon: Icons.water_damage_outlined,
        ),
      );
    }

    if (counts.communityHazards > 0) {
      items.add(
        _SafetyRecommendation(
          title: 'Avoid mapped community hazards',
          reason:
              '${counts.communityHazards} drainage, waterway, or road hazard${counts.communityHazards == 1 ? '' : 's'} reported nearby.',
          priority: _RecommendationPriority.medium,
          icon: Icons.warning_amber_outlined,
        ),
      );
    }

    final missingCritical = _firstMissing([
      'Power Bank',
      'Important Documents',
      'Drinking Water',
      'Medicines',
    ]);
    if (missingCritical != null) {
      items.add(
        _SafetyRecommendation(
          title: _recommendationTitleForMissing(missingCritical),
          reason: 'Your emergency checklist shows this item is not ready yet.',
          priority: _RecommendationPriority.medium,
          icon: _recommendationIconForMissing(missingCritical),
        ),
      );
    }

    final customMedicine = _customItems.where((item) {
      final normalized = item.toLowerCase();
      return (_items[item] == false) &&
          (normalized.contains('medicine') ||
              normalized.contains('medication') ||
              normalized.contains('maintenance'));
    }).firstOrNull;
    if (customMedicine != null && missingCritical != 'Medicines') {
      items.add(
        _SafetyRecommendation(
          title: 'Prepare your $customMedicine',
          reason:
              'This custom checklist item looks health-related and is not ready yet.',
          priority: _RecommendationPriority.medium,
          icon: Icons.medication_outlined,
        ),
      );
    }

    if (items.isEmpty) {
      items.addAll(const [
        _SafetyRecommendation(
          title: 'Keep alerts enabled',
          reason:
              'No urgent flood signal is available here, but local conditions can change.',
          priority: _RecommendationPriority.low,
          icon: Icons.notifications_none,
        ),
        _SafetyRecommendation(
          title: 'Review your emergency kit',
          reason:
              'Prepared supplies reduce delays if rainfall or flooding worsens.',
          priority: _RecommendationPriority.low,
          icon: Icons.fact_check_outlined,
        ),
      ]);
    }

    final seen = <String>{};
    return items
        .where((item) => seen.add(item.title.toLowerCase()))
        .take(4)
        .toList();
  }

  String? _firstMissing(List<String> priorityItems) {
    for (final item in priorityItems) {
      if (_items[item] == false) return item;
    }
    return null;
  }

  String _recommendationTitleForMissing(String item) => switch (item) {
    'Power Bank' => 'Charge your phone and power bank',
    'Important Documents' => 'Secure IDs and important documents',
    'Drinking Water' => 'Prepare drinking water',
    'Medicines' => 'Keep medicines ready',
    _ => 'Prepare $item',
  };

  IconData _recommendationIconForMissing(String item) => switch (item) {
    'Power Bank' => Icons.battery_charging_full_outlined,
    'Important Documents' => Icons.folder_copy_outlined,
    'Drinking Water' => Icons.water_drop_outlined,
    'Medicines' => Icons.medication_outlined,
    _ => Icons.checklist_outlined,
  };

  List<String> _phaseTips(String phase) => switch (phase) {
    'during' => const [
      'Move to higher ground when necessary.',
      'Do not walk or drive through floodwater.',
      'Keep away from electrical equipment in flooded areas.',
      'Follow official evacuation instructions.',
    ],
    'after' => const [
      'Avoid floodwater and damaged structures.',
      'Check official updates before returning.',
      'Inspect electrical systems safely before use.',
      'Report remaining hazards in your area.',
    ],
    _ => const [
      'Monitor official alerts and FloodGuard updates.',
      'Prepare emergency supplies and medicines.',
      'Move valuables and documents to higher areas.',
      'Know your evacuation route and nearest safe facility.',
    ],
  };

  String? _nearestFacilityLabel() {
    final location = _location;
    final facilities = _mapData?.facilities;
    if (location == null || facilities == null || facilities.isEmpty) {
      return null;
    }

    var nearestMeters = double.infinity;
    for (final facility in facilities) {
      final distance = _distanceMeters(
        location.latitude,
        location.longitude,
        facility.coordinate.latitude,
        facility.coordinate.longitude,
      );
      if (distance < nearestMeters) nearestMeters = distance;
    }
    if (!nearestMeters.isFinite) return null;
    if (nearestMeters < 1000) return '${nearestMeters.round()} m';
    return '${(nearestMeters / 1000).toStringAsFixed(1)} km';
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(lat1)) *
            math.cos(_radians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  Color _riskColor(String? level) => switch (level) {
    'High Risk' => const Color(0xFFB42318),
    'Moderate Risk' => const Color(0xFFF97316),
    'Low Risk' => const Color(0xFFCA8A04),
    'Minimal Risk' => const Color(0xFF15803D),
    _ => AppTheme.navy,
  };

  Color _priorityColor(_RecommendationPriority priority) => switch (priority) {
    _RecommendationPriority.high => const Color(0xFFDC2626),
    _RecommendationPriority.medium => const Color(0xFFF97316),
    _RecommendationPriority.low => AppTheme.blue,
  };
}

class _ReportCounts {
  const _ReportCounts(this.floodReports, this.communityHazards);

  final int floodReports;
  final int communityHazards;
}

enum _RecommendationPriority { high, medium, low }

class _SafetyRecommendation {
  const _SafetyRecommendation({
    required this.title,
    required this.reason,
    required this.priority,
    required this.icon,
  });

  final String title;
  final String reason;
  final _RecommendationPriority priority;
  final IconData icon;
}
