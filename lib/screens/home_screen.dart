import 'dart:async';

import 'package:flutter/material.dart';

import '../services/device_location_service.dart';
import '../services/risk_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/metric_tile.dart';
import 'alerts_screen.dart';
import 'evacuation_centers_screen.dart';
import 'report_hazard_screen.dart';
import 'risk_details_screen.dart';
import 'safety_tips_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _locationService = DeviceLocationService();
  String _locationLabel = 'Tap to set your location';
  String? _coordinates;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _restoreLastLocation();
  }

  Future<void> _restoreLastLocation() async {
    final location = await _locationService.getSavedLocation();
    if (!mounted || location == null) return;
    setState(() {
      _locationLabel = location.label;
      _coordinates =
          '${location.latitude.toStringAsFixed(5)} deg N, ${location.longitude.toStringAsFixed(5)} deg E';
    });
  }

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
                            value: '26 C',
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
                subtitle: Text('Baliwag, Bulacan - Today, 8:45 AM'),
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
                subtitle: Text('Baliwag, Bulacan - Today, 7:30 AM'),
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

  Future<void> _refreshLocation() async {
    setState(() => _isLoadingLocation = true);
    _showMessage('Updating your current location...');
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      _setLocation(location);
      _showMessage('Current location updated.');
    } on LocationAccessException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } on TimeoutException {
      if (mounted) {
        _showMessage(
          'Location request timed out. Please try again outdoors or with GPS enabled.',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Unable to read your location right now. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _setLocation(DeviceLocation location) {
    setState(() {
      _locationLabel = location.label;
      _coordinates =
          '${location.latitude.toStringAsFixed(5)} deg N, ${location.longitude.toStringAsFixed(5)} deg E';
    });
  }

  void _openLocationSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LocationPickerSheet(
        locationService: _locationService,
        onUseCurrentLocation: () {
          Navigator.pop(context);
          _refreshLocation();
        },
        onLocationSelected: (location) {
          _setLocation(location);
          Navigator.pop(context);
          _showMessage('Location set to ${location.label}.');
        },
      ),
    );
  }

  void _showMessage(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Widget _locationCard(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: const Icon(Icons.location_on, color: AppTheme.blue),
      title: const Text('Your Location', style: TextStyle(fontSize: 12)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _locationLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (_coordinates != null)
            Text(_coordinates!, style: const TextStyle(fontSize: 11)),
        ],
      ),
      trailing: _isLoadingLocation
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton.filledTonal(
              onPressed: _openLocationSheet,
              icon: const Icon(Icons.edit_location_alt_outlined),
              tooltip: 'Change location',
            ),
      onTap: _isLoadingLocation ? null : _openLocationSheet,
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

class _LocationPickerSheet extends StatefulWidget {
  const _LocationPickerSheet({
    required this.locationService,
    required this.onUseCurrentLocation,
    required this.onLocationSelected,
  });

  final DeviceLocationService locationService;
  final VoidCallback onUseCurrentLocation;
  final ValueChanged<DeviceLocation> onLocationSelected;

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late final TextEditingController _search;
  Timer? _debounce;
  List<LocationSuggestion> _suggestions = const [];
  String? _error;
  bool _isSearching = false;
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _queueSearch(String value, {bool immediate = false}) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = const [];
        _error = null;
        _isSearching = false;
      });
      return;
    }

    if (immediate) {
      _searchLocations(query);
    } else {
      setState(() => _isSearching = true);
      _debounce = Timer(const Duration(milliseconds: 350), () {
        _searchLocations(query);
      });
    }
  }

  Future<void> _searchLocations(String query) async {
    setState(() {
      _isSearching = true;
      _error = null;
    });
    try {
      final suggestions = await widget.locationService.searchSuggestions(query);
      if (!mounted || query != _search.text.trim()) return;
      setState(() {
        _suggestions = suggestions;
        _error = suggestions.isEmpty ? 'No matching locations found.' : null;
      });
    } on LocationAccessException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Location search failed.');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectSuggestion(LocationSuggestion suggestion) async {
    setState(() => _isSelecting = true);
    try {
      final location = await widget.locationService.selectSuggestion(
        suggestion,
      );
      if (mounted) widget.onLocationSelected(location);
    } on LocationAccessException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: bottomInset > 0 ? .74 : .56,
          minChildSize: .45,
          maxChildSize: .9,
          builder: (context, controller) => DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD5DEEC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Set Your Location',
                  style: TextStyle(
                    color: AppTheme.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0,
                  ),
                  leading: const Icon(
                    Icons.near_me_outlined,
                    color: AppTheme.navy,
                  ),
                  title: const Text(
                    'Use my current location',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('Detect from this device'),
                  onTap: _isSelecting ? null : widget.onUseCurrentLocation,
                ),
                const Divider(height: 18),
                TextField(
                  controller: _search,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: 'Search city, barangay, or address',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : _search.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _search.clear();
                                  _queueSearch('');
                                },
                                icon: const Icon(Icons.close),
                              ),
                  ),
                  onChanged: _queueSearch,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 12),
                if (_suggestions.isEmpty && !_isSearching)
                  const ListTile(
                    contentPadding: EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(Icons.search_outlined),
                    title: Text(
                      'Search for a location',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      'Type an address, street, barangay, city, or landmark.',
                    ),
                  )
                else
                  ..._suggestions.map(_suggestionTile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _suggestionTile(LocationSuggestion suggestion) => Column(
    children: [
      ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        leading: const Icon(
          Icons.location_on_outlined,
          color: AppTheme.ink,
          size: 24,
        ),
        title: Text(
          suggestion.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          suggestion.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        onTap: _isSelecting ? null : () => _selectSuggestion(suggestion),
      ),
      const Divider(height: 1, indent: 44),
    ],
  );
}
