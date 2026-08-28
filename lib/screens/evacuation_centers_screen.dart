import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String _scenario = 'rare';
  WeatherSnapshot? _weather;
  String? _weatherError;
  bool _isRefreshing = false;
  bool _showFloodHazard = true;
  bool _showFacilities = true;

  String get _tileUrl => _geoapifyApiKey.isNotEmpty
      ? 'https://maps.geoapify.com/v1/tile/osm-bright/{z}/{x}/{y}.png?apiKey=$_geoapifyApiKey'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  String get _attribution => _geoapifyApiKey.isNotEmpty
      ? 'Geoapify | OpenStreetMap contributors'
      : 'OpenStreetMap contributors';

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
        if (mounted) _moveCamera(point, zoom: 15.2);
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
      _moveCamera(point, zoom: 15.2);
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
    _moveCamera(point, zoom: 15.2);
    _loadWeather();
  }

  void _focusFacility(_Facility facility) {
    setState(() {
      _showFacilities = true;
      _mapCenter = facility.point;
    });
    _moveCamera(facility.point, zoom: 16);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Showing ${facility.name} on the map.')),
    );
  }

  void _moveCamera(LatLng point, {double zoom = 15.2}) {
    _mapController.move(point, zoom);
  }

  void _toggleFloodZones() {
    setState(() => _showFloodHazard = !_showFloodHazard);
  }

  void _toggleFacilities() {
    setState(() => _showFacilities = !_showFacilities);
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

  Widget _mapView() => FlutterMap(
    mapController: _mapController,
    options: MapOptions(
      initialCenter: _mapCenter,
      initialZoom: 15.2,
      minZoom: 9,
      maxZoom: 19,
      interactionOptions: const InteractionOptions(
        flags:
            InteractiveFlag.drag |
            InteractiveFlag.pinchZoom |
            InteractiveFlag.doubleTapZoom |
            InteractiveFlag.flingAnimation,
      ),
      onTap: (_, point) => _moveAssessmentPoint(point),
    ),
    children: [
      TileLayer(urlTemplate: _tileUrl, userAgentPackageName: 'floodguard.ai'),
      if (_showFloodHazard)
        CircleLayer(circles: _hazardZones().map(_hazardCircle).toList()),
      if (_showFacilities)
        MarkerLayer(markers: _facilities.map(_facilityMarker).toList()),
      MarkerLayer(
        markers: [
          Marker(
            point: _assessmentPoint,
            width: 48,
            height: 48,
            child: const Icon(
              Icons.location_pin,
              color: AppTheme.navy,
              size: 44,
            ),
          ),
        ],
      ),
      RichAttributionWidget(
        attributions: [TextSourceAttribution(_attribution)],
      ),
    ],
  );

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
    top: 88,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MapActionButton(
          label: 'My location',
          icon: Icons.my_location,
          selected: true,
          onPressed: _isRefreshing ? null : _useMyLocation,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Flood zones',
          icon: Icons.flood_outlined,
          selected: _showFloodHazard,
          onPressed: _toggleFloodZones,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Facilities',
          icon: Icons.home_work_outlined,
          selected: _showFacilities,
          onPressed: _toggleFacilities,
        ),
      ],
    ),
  );

  Widget _bottomPanel(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .32,
    minChildSize: .15,
    maxChildSize: .78,
    builder: (context, controller) => DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
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
                'Flood Map',
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
              ButtonSegment(value: 'usual', label: Text('Usual')),
              ButtonSegment(value: 'heavy', label: Text('Heavy')),
              ButtonSegment(value: 'rare', label: Text('Rare')),
            ],
            selected: {_scenario},
            onSelectionChanged: (values) =>
                setState(() => _scenario = values.first),
          ),
          const SizedBox(height: 12),
          const _HazardLegend(),
          const SizedBox(height: 6),
          const Text(
            'Colored flood zones are demo hazard overlays. Tap the map to move the assessment pin.',
            style: TextStyle(color: Color(0xFF5B6677), fontSize: 12),
          ),
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
            'Tap a facility to move the map there. Verify availability with the LGU before emergency use.',
          ),
          const SizedBox(height: 8),
          ..._facilities.map(
            (facility) =>
                _CenterCard(facility, onTap: () => _focusFacility(facility)),
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
                  '${_scenarioLabel(_scenario)}. Streets and nearby facilities shown.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scenarioLabel(String scenario) => switch (scenario) {
    'usual' => 'Usual flood scenario',
    'heavy' => 'Heavy flood scenario',
    _ => 'Rare extreme flood scenario',
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
    radius: zone.radiusMeters * _scenarioMultiplier,
    useRadiusInMeter: true,
    color: zone.color.withValues(alpha: .14),
    borderStrokeWidth: 2,
    borderColor: zone.color.withValues(alpha: .68),
  );

  Marker _facilityMarker(_Facility facility) => Marker(
    point: facility.point,
    width: 44,
    height: 44,
    child: Tooltip(
      message: facility.name,
      child: GestureDetector(
        onTap: () => _focusFacility(facility),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 8),
            ],
            border: Border.all(color: _facilityColor(facility), width: 2),
          ),
          child: Icon(
            _facilityIcon(facility.type),
            color: _facilityColor(facility),
            size: 23,
          ),
        ),
      ),
    ),
  );

  _HazardZone _nearestHazardZone() {
    final distance = const Distance();
    final zones = _hazardZones().toList();
    zones.sort(
      (a, b) => distance(
        _assessmentPoint,
        a.point,
      ).compareTo(distance(_assessmentPoint, b.point)),
    );
    return zones.first;
  }

  List<_HazardZone> _hazardZones() => const [
    _HazardZone(
      level: 'High',
      point: LatLng(14.9526, 120.8912),
      radiusMeters: 620,
      color: Color(0xFFDC2626),
    ),
    _HazardZone(
      level: 'Medium',
      point: LatLng(14.9615, 120.9004),
      radiusMeters: 520,
      color: Color(0xFFF59E0B),
    ),
    _HazardZone(
      level: 'Low',
      point: LatLng(14.9468, 120.9044),
      radiusMeters: 430,
      color: Color(0xFF22C55E),
    ),
  ];

  double get _scenarioMultiplier => switch (_scenario) {
    'usual' => .72,
    'heavy' => .9,
    _ => 1.12,
  };

  IconData _facilityIcon(_FacilityType type) => switch (type) {
    _FacilityType.evacuation => Icons.home_work_outlined,
    _FacilityType.school => Icons.school_outlined,
    _FacilityType.hospital => Icons.local_hospital_outlined,
    _FacilityType.fireStation => Icons.local_fire_department_outlined,
  };

  Color _facilityColor(_Facility facility) {
    if (facility.recommended) return const Color(0xFF16A34A);
    return switch (facility.type) {
      _FacilityType.hospital => const Color(0xFFDC2626),
      _FacilityType.fireStation => const Color(0xFFF97316),
      _ => AppTheme.blue,
    };
  }
}

class _HazardLegend extends StatelessWidget {
  const _HazardLegend();

  @override
  Widget build(BuildContext context) => const Wrap(
    spacing: 12,
    runSpacing: 6,
    children: [
      _LegendItem(color: Color(0xFF22C55E), label: 'Low risk'),
      _LegendItem(color: Color(0xFFF59E0B), label: 'Medium risk'),
      _LegendItem(color: Color(0xFFDC2626), label: 'High risk'),
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

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppTheme.blue : Colors.white,
    elevation: 3,
    shadowColor: const Color(0x30000000),
    borderRadius: BorderRadius.circular(22),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppTheme.navy,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
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

  static const _numbers = [
    _EmergencyNumber(
      label: 'National Emergency Hotline',
      number: '911',
      detail: 'Police, fire, rescue, or medical emergency',
    ),
    _EmergencyNumber(
      label: 'Philippine Red Cross',
      number: '143',
      detail: 'Rescue and disaster assistance',
    ),
    _EmergencyNumber(
      label: 'NDRRMC Operations Center',
      number: '0289111406',
      displayNumber: '(02) 8911-1406',
      detail: 'Disaster response coordination',
    ),
  ];

  static Future<void> _call(BuildContext context, String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone dialer is not available.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emergency_outlined, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Emergency Contacts',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a number to open the phone dialer. Confirm local DRRMO numbers with your LGU.',
            style: TextStyle(color: Color(0xFF5B6677)),
          ),
          const SizedBox(height: 8),
          ..._numbers.map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFE8E8),
                child: Icon(Icons.phone_in_talk_outlined, color: Colors.red),
              ),
              title: Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${item.displayNumber}\n${item.detail}'),
              isThreeLine: true,
              trailing: FilledButton(
                onPressed: () => _call(context, item.number),
                child: const Text('Call'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmergencyNumber {
  const _EmergencyNumber({
    required this.label,
    required this.number,
    required this.detail,
    String? displayNumber,
  }) : displayNumber = displayNumber ?? number;

  final String label;
  final String number;
  final String displayNumber;
  final String detail;
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
