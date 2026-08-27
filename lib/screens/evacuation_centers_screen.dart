import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/device_location_service.dart';
import '../services/weather_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

class EvacuationCentersScreen extends StatefulWidget {
  const EvacuationCentersScreen({super.key});

  @override
  State<EvacuationCentersScreen> createState() =>
      _EvacuationCentersScreenState();
}

class _EvacuationCentersScreenState extends State<EvacuationCentersScreen> {
  static const _mapboxAccessToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
  );
  static const _geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');
  static const _baliwag = LatLng(14.9547, 120.8969);
  static const _facilities = [
    _Facility(
      name: 'Baliwag City Hall Evacuation Center',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9547, 120.8969),
      type: _FacilityType.evacuation,
      recommended: true,
    ),
    _Facility(
      name: 'Baliwag North Central School',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9636, 120.8996),
      type: _FacilityType.school,
    ),
    _Facility(
      name: 'Baliwag District Hospital',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9506, 120.9018),
      type: _FacilityType.hospital,
    ),
    _Facility(
      name: 'Baliwag Fire Station',
      address: 'Baliwag, Bulacan',
      point: LatLng(14.9584, 120.8912),
      type: _FacilityType.fireStation,
    ),
  ];

  final _mapController = MapController();
  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  LatLng _mapCenter = _baliwag;
  LatLng _assessmentPoint = _baliwag;
  String _locationLabel = 'Baliwag, Bulacan';
  String _returnPeriod = '100-Year';
  WeatherSnapshot? _weather;
  String? _weatherError;
  bool _isRefreshing = false;
  bool _showFloodHazard = true;
  bool _showFacilities = true;

  @override
  void initState() {
    super.initState();
    _restoreSavedLocation();
  }

  Future<void> _restoreSavedLocation() async {
    final location = await _locationService.getSavedLocation();
    if (location != null && mounted) {
      final point = LatLng(location.latitude, location.longitude);
      setState(() {
        _mapCenter = point;
        _assessmentPoint = point;
        _locationLabel = location.label;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(point, 14);
      });
    }
    _loadWeather();
  }

  Future<void> _loadWeather() async {
    setState(() {
      _isRefreshing = true;
      _weatherError = null;
    });
    try {
      final weather = await _weatherService.getCurrentWeather(
        latitude: _assessmentPoint.latitude,
        longitude: _assessmentPoint.longitude,
      );
      if (mounted) setState(() => _weather = weather);
    } on WeatherException catch (error) {
      if (mounted) setState(() => _weatherError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _weatherError = 'Check your internet connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _isRefreshing = true);
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      final point = LatLng(location.latitude, location.longitude);
      setState(() {
        _mapCenter = point;
        _assessmentPoint = point;
        _locationLabel = location.label;
      });
      _mapController.move(point, 14);
      await _loadWeather();
    } on LocationAccessException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _moveAssessmentPoint(LatLng point) {
    setState(() {
      _assessmentPoint = point;
      _mapCenter = point;
      _locationLabel =
          '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
    });
    _mapController.move(point, _mapController.camera.zoom);
    _loadWeather();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: _mapView()),
          _topBar(context),
          _mapQuickActions(),
          _bottomPanel(context),
        ],
      ),
    ),
  );

  void _focusFacility(_Facility facility) {
    setState(() {
      _showFacilities = true;
      _mapCenter = facility.point;
    });
    _mapController.move(facility.point, 16);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Showing ${facility.name} on the map.')),
    );
  }

  Widget _mapView() => FlutterMap(
    mapController: _mapController,
    options: MapOptions(
      initialCenter: _mapCenter,
      initialZoom: 13,
      maxZoom: 18,
      minZoom: 8,
      onTap: (_, point) => _moveAssessmentPoint(point),
    ),
    children: [
      TileLayer(
        urlTemplate: _tileUrl,
        userAgentPackageName: 'com.example.floodguard',
      ),
      if (_showFloodHazard)
        CircleLayer(circles: _hazardZones().map(_hazardCircle).toList()),
      if (_showFacilities)
        MarkerLayer(markers: _facilities.map(_facilityMarker).toList()),
      MarkerLayer(
        markers: [
          Marker(
            point: _assessmentPoint,
            width: 54,
            height: 54,
            child: const Icon(
              Icons.location_pin,
              color: AppTheme.navy,
              size: 48,
            ),
          ),
        ],
      ),
      RichAttributionWidget(
        attributions: [
          TextSourceAttribution(
            _mapAttribution,
          ),
        ],
      ),
    ],
  );

  String get _tileUrl {
    if (_mapboxAccessToken.isNotEmpty) {
      return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}?access_token=$_mapboxAccessToken';
    }
    if (_geoapifyApiKey.isNotEmpty) {
      return 'https://maps.geoapify.com/v1/tile/osm-bright/{z}/{x}/{y}.png?apiKey=$_geoapifyApiKey';
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  String get _mapAttribution {
    if (_mapboxAccessToken.isNotEmpty) {
      return 'Mapbox | OpenStreetMap contributors';
    }
    if (_geoapifyApiKey.isNotEmpty) {
      return 'Geoapify | OpenStreetMap contributors';
    }
    return 'OpenStreetMap contributors';
  }

  Widget _topBar(BuildContext context) => Positioned(
    top: 12,
    left: 16,
    right: 16,
    child: Row(
      children: [
        IconButton.filledTonal(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Hazard Map',
            style: TextStyle(
              color: AppTheme.navy,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ),
        IconButton.filledTonal(
          onPressed: _isRefreshing ? null : _loadWeather,
          icon: _isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
  );

  Widget _mapQuickActions() => Positioned(
    right: 16,
    top: 86,
    child: Column(
      children: [
        IconButton.filled(
          onPressed: _isRefreshing ? null : _useMyLocation,
          icon: const Icon(Icons.my_location),
          tooltip: 'Use my location',
        ),
        const SizedBox(height: 8),
        IconButton.filledTonal(
          onPressed: () => setState(() => _showFloodHazard = !_showFloodHazard),
          icon: Icon(
            _showFloodHazard ? Icons.flood_outlined : Icons.flood,
          ),
          tooltip: 'Flood zones',
        ),
        const SizedBox(height: 8),
        IconButton.filledTonal(
          onPressed: () => setState(() => _showFacilities = !_showFacilities),
          icon: const Icon(Icons.home_work_outlined),
          tooltip: 'Facilities',
        ),
      ],
    ),
  );

  Widget _bottomPanel(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .38,
    minChildSize: .2,
    maxChildSize: .78,
    builder: (context, controller) => DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD5DEEC),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.layers_outlined, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(
                'Map View',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _hazardSummaryCard(),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '5-Year', label: Text('Usual')),
              ButtonSegment(value: '25-Year', label: Text('Heavy')),
              ButtonSegment(value: '100-Year', label: Text('Rare')),
            ],
            selected: {_returnPeriod},
            onSelectionChanged: (values) {
              setState(() => _returnPeriod = values.first);
            },
          ),
          const SizedBox(height: 12),
          const _HazardLegend(),
          const SizedBox(height: 12),
          _weatherCard(),
          const SizedBox(height: 18),
          Text(
            'Critical Facilities',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a facility to center it on the map. Verify availability with the LGU before emergency use.',
          ),
          const SizedBox(height: 8),
          ..._facilities.map(
            (facility) => _CenterCard(
              facility,
              onTap: () => _focusFacility(facility),
            ),
          ),
          const SizedBox(height: 8),
          const _EmergencyHelpCard(),
        ],
      ),
    ),
  );

  Widget _hazardSummaryCard() {
    final zone = _nearestHazardZone();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: zone.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: zone.color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: zone.color.withValues(alpha: .18),
            child: Icon(Icons.flood_outlined, color: zone.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${zone.level} hazard near $_locationLabel',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${_scenarioLabel(_returnPeriod)} scenario. Planning reference only.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scenarioLabel(String returnPeriod) => switch (returnPeriod) {
    '5-Year' => 'Usual flood',
    '25-Year' => 'Heavy flood',
    _ => 'Rare extreme flood',
  };

  Widget _weatherCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3EAF4)),
    ),
    child: Row(
      children: [
        _isRefreshing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloudy_snowing, color: AppTheme.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live weather',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _weather != null
                    ? '${_weather!.temperatureCelsius.toStringAsFixed(1)} C, precipitation ${_weather!.precipitationMm.toStringAsFixed(1)} mm'
                    : _weatherError ?? 'Loading current weather...',
              ),
            ],
          ),
        ),
      ],
    ),
  );

  CircleMarker _hazardCircle(_HazardZone zone) => CircleMarker(
    point: zone.point,
    radius: zone.radiusMeters * _returnPeriodMultiplier,
    useRadiusInMeter: true,
    color: zone.color.withValues(alpha: .36),
    borderStrokeWidth: 1.5,
    borderColor: zone.color,
  );

  Marker _facilityMarker(_Facility facility) => Marker(
    point: facility.point,
    width: 44,
    height: 44,
    child: Tooltip(
      message: facility.name,
      child: GestureDetector(
        onTap: () => _focusFacility(facility),
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(
            _facilityIcon(facility.type),
            color: _facilityColor(facility),
          ),
        ),
      ),
    ),
  );

  _HazardZone _nearestHazardZone() {
    final distance = const Distance();
    final zones = _hazardZones().toList();
    zones.sort(
      (a, b) => distance(_assessmentPoint, a.point).compareTo(
        distance(_assessmentPoint, b.point),
      ),
    );
    return zones.first;
  }

  List<_HazardZone> _hazardZones() => const [
    _HazardZone(
      level: 'High',
      point: LatLng(14.9526, 120.8912),
      radiusMeters: 900,
      color: Color(0xFFDC2626),
    ),
    _HazardZone(
      level: 'Medium',
      point: LatLng(14.9615, 120.9004),
      radiusMeters: 760,
      color: Color(0xFFF59E0B),
    ),
    _HazardZone(
      level: 'Low',
      point: LatLng(14.9468, 120.9044),
      radiusMeters: 640,
      color: Color(0xFF22C55E),
    ),
  ];

  double get _returnPeriodMultiplier => switch (_returnPeriod) {
    '5-Year' => .72,
    '25-Year' => .9,
    _ => 1.12,
  };

  IconData _facilityIcon(_FacilityType type) => switch (type) {
    _FacilityType.evacuation => Icons.home_work_outlined,
    _FacilityType.school => Icons.school_outlined,
    _FacilityType.hospital => Icons.local_hospital_outlined,
    _FacilityType.fireStation => Icons.local_fire_department_outlined,
  };

  Color _facilityColor(_Facility facility) {
    if (facility.recommended) return Colors.green;
    return switch (facility.type) {
      _FacilityType.hospital => Colors.red,
      _FacilityType.fireStation => Colors.deepOrange,
      _ => AppTheme.blue,
    };
  }
}

class _HazardLegend extends StatelessWidget {
  const _HazardLegend();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _LegendItem(color: Color(0xFF22C55E), label: 'Low'),
      SizedBox(width: 12),
      _LegendItem(color: Color(0xFFF59E0B), label: 'Medium'),
      SizedBox(width: 12),
      _LegendItem(color: Color(0xFFDC2626), label: 'High'),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _CenterCard extends StatelessWidget {
  const _CenterCard(this.facility, {required this.onTap});

  final _Facility facility;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: facility.recommended
            ? const Color(0xFFE8F8ED)
            : AppTheme.paleBlue,
        child: Icon(
          _icon(facility.type),
          color: facility.recommended ? Colors.green : AppTheme.blue,
        ),
      ),
      title: Text(
        facility.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${facility.address}\n${_detail(facility)}'),
      isThreeLine: true,
      trailing: const Icon(Icons.map_outlined),
      onTap: onTap,
    ),
  );

  String _detail(_Facility facility) {
    if (facility.recommended) {
      return 'Recommended reference site, verify opening status with the LGU.';
    }
    return 'Reference facility, verify status before emergency use.';
  }

  IconData _icon(_FacilityType type) => switch (type) {
    _FacilityType.evacuation => Icons.home_work_outlined,
    _FacilityType.school => Icons.school_outlined,
    _FacilityType.hospital => Icons.local_hospital_outlined,
    _FacilityType.fireStation => Icons.local_fire_department_outlined,
  };
}

class _EmergencyHelpCard extends StatelessWidget {
  const _EmergencyHelpCard();

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.emergency_outlined, color: Colors.red),
      title: const Text('Emergency Help'),
      subtitle: const Text(
        'For urgent rescue, medical, or fire emergencies, use your phone emergency dialer and confirm local DRRMO numbers with your LGU.',
      ),
      trailing: IconButton(
        onPressed: null,
        icon: const Icon(Icons.phone_disabled_outlined),
        tooltip: 'Dialing is not configured',
      ),
    ),
  );
}

class _HazardZone {
  const _HazardZone({
    required this.level,
    required this.point,
    required this.radiusMeters,
    required this.color,
  });

  final String level;
  final LatLng point;
  final double radiusMeters;
  final Color color;
}

class _Facility {
  const _Facility({
    required this.name,
    required this.address,
    required this.point,
    required this.type,
    this.recommended = false,
  });

  final String name;
  final String address;
  final LatLng point;
  final _FacilityType type;
  final bool recommended;
}

enum _FacilityType { evacuation, school, hospital, fireStation }
