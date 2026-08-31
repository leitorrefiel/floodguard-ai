import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import '../services/device_location_service.dart';
import '../services/hazard_map_service.dart';
import '../services/hazard_report_service.dart';
import '../services/risk_service.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/metric_tile.dart';
import 'alerts_screen.dart';
import 'community_reports_screen.dart';
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
  final _weatherService = WeatherService();
  final _riskService = const RiskService();
  final _hazardMapService = HazardMapService();
  final _reportService = HazardReportService();
  DeviceLocation? _currentLocation;
  String _locationLabel = 'Tap to set your location';
  String? _coordinates;
  RiskAssessment? _riskAssessment;
  _AreaStatus? _areaStatus;
  List<HazardReport> _recentCommunityReports = const [];
  String? _riskError;
  String? _areaStatusError;
  String? _recentReportsError;
  bool _isLoadingLocation = false;
  bool _isLoadingRisk = false;
  bool _isLoadingAreaStatus = false;
  bool _isLoadingRecentReports = true;

  @override
  void initState() {
    super.initState();
    _restoreLastLocation();
    _loadRecentCommunityReports();
  }

  Future<void> _restoreLastLocation() async {
    final location = await _locationService.getSavedLocation();
    if (!mounted || location == null) return;
    setState(() {
      _currentLocation = location;
      _locationLabel = location.label;
      _coordinates =
          '${location.latitude.toStringAsFixed(5)} deg N, ${location.longitude.toStringAsFixed(5)} deg E';
    });
    _loadRiskFor(location);
    _loadAreaStatusFor(location);
  }

  @override
  Widget build(BuildContext context) {
    final risk = _riskAssessment;
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
                color: _riskCardColor(risk?.level),
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
                      if (_isLoadingRisk)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(minHeight: 6),
                        )
                      else
                        Text(
                          risk?.level ?? 'Set Location First',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            color: _riskColor(risk?.level),
                          ),
                        ),
                      Text(
                        _riskError ??
                            risk?.summary ??
                            'Choose your location to load live rainfall-based flood risk.',
                      ),
                      const SizedBox(height: 14),
                      LinearProgressIndicator(
                        value: (risk?.score ?? 0) / 100,
                        minHeight: 8,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(6),
                        ),
                        color: _riskColor(risk?.level),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          MetricTile(
                            icon: Icons.cloudy_snowing,
                            label: 'Rain now',
                            value: risk?.currentRainLabel ?? '--',
                            caption: 'Live',
                          ),
                          MetricTile(
                            icon: Icons.cloud,
                            label: 'Weather',
                            value: risk?.temperatureLabel ?? '--',
                            caption: 'Open-Meteo',
                          ),
                          MetricTile(
                            icon: Icons.water,
                            label: 'Forecast rain',
                            value: risk?.forecastRainLabel ?? '--',
                            caption: 'Max daily',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _areaStatusCard(),
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
                  const EvacuationCentersScreen(
                    initialMode: HazardMapInitialMode.facilities,
                  ),
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
                      builder: (_) => const CommunityReportsScreen(),
                    ),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _recentCommunityReportsPreview(),
          ],
        ),
      ),
    );
  }

  Future<void> _loadRecentCommunityReports() async {
    setState(() {
      _isLoadingRecentReports = true;
      _recentReportsError = null;
    });
    try {
      final reports = await _reportService.getReports(
        includeCommunityReports: true,
      );
      final visibleReports = reports.where((report) => report.isActive).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted) return;
      setState(() => _recentCommunityReports = visibleReports.take(3).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _recentCommunityReports = const [];
        _recentReportsError = 'Recent community reports are unavailable.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingRecentReports = false);
    }
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
      _currentLocation = location;
      _locationLabel = location.label;
      _coordinates =
          '${location.latitude.toStringAsFixed(5)} deg N, ${location.longitude.toStringAsFixed(5)} deg E';
    });
    _loadRiskFor(location);
    _loadAreaStatusFor(location);
  }

  Future<void> _loadRiskFor(DeviceLocation location) async {
    setState(() {
      _isLoadingRisk = true;
      _riskError = null;
    });
    try {
      final forecast = await _weatherService.getForecast(
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted) return;
      setState(
        () => _riskAssessment = _riskService.assess(
          forecast,
          locationLabel: location.label,
        ),
      );
    } on WeatherException catch (error) {
      if (mounted) setState(() => _riskError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _riskError = 'Unable to load live flood risk right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRisk = false);
    }
  }

  Future<void> _loadAreaStatusFor(DeviceLocation location) async {
    setState(() {
      _isLoadingAreaStatus = true;
      _areaStatusError = null;
    });

    try {
      final data = await _hazardMapService.load();
      if (!mounted || _currentLocation != location) return;
      setState(() => _areaStatus = _buildAreaStatus(location, data));
    } catch (_) {
      if (!mounted || _currentLocation != location) return;
      setState(() {
        _areaStatus = null;
        _areaStatusError = 'No mapped reports currently available.';
      });
    } finally {
      if (mounted && _currentLocation == location) {
        setState(() => _isLoadingAreaStatus = false);
      }
    }
  }

  _AreaStatus _buildAreaStatus(DeviceLocation location, HazardMapData data) {
    const nearbyRadiusMeters = 5000.0;
    final origin = MapCoordinate(
      latitude: location.latitude,
      longitude: location.longitude,
    );
    final nearbyReports = data.reports.where((item) {
      return _distanceMeters(origin, item.coordinate) <= nearbyRadiusMeters;
    });
    final floodReports = nearbyReports.where(
      (item) => item.report.type == HazardType.floodedRoad,
    );
    final floodCount = floodReports.length;
    final hazardCount = nearbyReports.length - floodCount;

    EmergencyFacility? nearestFacility;
    var nearestDistance = double.infinity;
    for (final facility in data.facilities) {
      final distance = _distanceMeters(origin, facility.coordinate);
      if (distance < nearestDistance) {
        nearestFacility = facility;
        nearestDistance = distance;
      }
    }

    return _AreaStatus(
      floodReports: floodCount,
      hazardReports: hazardCount,
      nearestFacilityDistance: nearestFacility == null
          ? null
          : _formatDistance(nearestDistance),
      storageLabel: data.storageLabel,
    );
  }

  double _distanceMeters(MapCoordinate a, MapCoordinate b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final deltaLat = _radians(b.latitude - a.latitude);
    final deltaLng = _radians(b.longitude - a.longitude);
    final haversine =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Color _riskColor(String? level) {
    if (level == 'High Risk') return const Color(0xFFDC2626);
    if (level == 'Moderate Risk') return const Color(0xFFF59E0B);
    if (level == 'Low Risk') return const Color(0xFF2563EB);
    return const Color(0xFF16A34A);
  }

  Color _riskCardColor(String? level) {
    if (level == 'High Risk') return const Color(0xFFFFF4F4);
    if (level == 'Moderate Risk') return const Color(0xFFFFF8E6);
    if (level == 'Low Risk') return const Color(0xFFF0F6FF);
    return const Color(0xFFF0FDF4);
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

  Widget _areaStatusCard() {
    final status = _areaStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.radar_outlined, color: AppTheme.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Area Status',
                    style: TextStyle(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_currentLocation == null)
                    const Text('Set your location to summarize nearby reports.')
                  else if (_isLoadingAreaStatus)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, right: 32),
                      child: LinearProgressIndicator(minHeight: 3),
                    )
                  else if (_areaStatusError != null)
                    Text(_areaStatusError!)
                  else if (status != null) ...[
                    Text(status.floodLine),
                    const SizedBox(height: 2),
                    Text(status.hazardLine),
                    if (status.facilityLine != null) ...[
                      const SizedBox(height: 2),
                      Text(status.facilityLine!),
                    ],
                  ] else
                    const Text('No mapped reports currently available.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _recentCommunityReportsPreview() {
    if (_isLoadingRecentReports) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(minHeight: 4),
        ),
      );
    }
    if (_recentReportsError != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline, color: AppTheme.blue),
          title: Text(_recentReportsError!),
          subtitle: const Text('Try refreshing the Home screen later.'),
        ),
      );
    }
    if (_recentCommunityReports.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.map_outlined, color: AppTheme.blue),
          title: Text('No recent community reports'),
          subtitle: Text('Submitted hazard reports will appear here.'),
        ),
      );
    }
    return Column(
      children: _recentCommunityReports.map(_recentReportCard).toList(),
    );
  }

  Widget _recentReportCard(HazardReport report) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: _hazardColor(report.type).withValues(alpha: .12),
        child: Icon(_hazardIcon(report.type), color: _hazardColor(report.type)),
      ),
      title: Text(
        report.displayType,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_shortLocation(report.location)}\n${_formatReportTime(report.createdAt)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => EvacuationCentersScreen(focusReportId: report.id),
        ),
      ),
    ),
  );

  String _shortLocation(String location) {
    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'Pinned location';
    return parts.join(', ');
  }

  String _formatReportTime(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inHours < 24) return '${difference.inHours} hr ago';
    final hour = createdAt.hour % 12 == 0 ? 12 : createdAt.hour % 12;
    final minute = createdAt.minute.toString().padLeft(2, '0');
    final period = createdAt.hour >= 12 ? 'PM' : 'AM';
    return '${createdAt.month}/${createdAt.day}/${createdAt.year}, $hour:$minute $period';
  }

  IconData _hazardIcon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.water_damage_outlined,
    HazardType.cloggedDrainage => Icons.water_drop_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.flood_outlined,
    HazardType.roadObstruction => Icons.traffic_outlined,
    HazardType.damagedDrainage => Icons.construction_outlined,
    HazardType.other => Icons.warning_amber_outlined,
  };

  Color _hazardColor(HazardType type) => switch (type) {
    HazardType.floodedRoad || HazardType.overflowingCanal => AppTheme.blue,
    HazardType.cloggedDrainage ||
    HazardType.blockedWaterway ||
    HazardType.damagedDrainage => const Color(0xFFF97316),
    HazardType.roadObstruction || HazardType.other => const Color(0xFFDC2626),
  };
}

class _AreaStatus {
  const _AreaStatus({
    required this.floodReports,
    required this.hazardReports,
    required this.nearestFacilityDistance,
    required this.storageLabel,
  });

  final int floodReports;
  final int hazardReports;
  final String? nearestFacilityDistance;
  final String storageLabel;

  String get floodLine {
    if (floodReports == 0) return 'No active flood reports nearby.';
    final label = floodReports == 1 ? 'location' : 'locations';
    return '$floodReports reported flooded $label nearby.';
  }

  String get hazardLine {
    final label = hazardReports == 1 ? 'hazard' : 'hazards';
    return '$hazardReports community $label reported nearby.';
  }

  String? get facilityLine {
    final distance = nearestFacilityDistance;
    if (distance == null) return null;
    return 'Nearest safety facility: $distance.';
  }
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
