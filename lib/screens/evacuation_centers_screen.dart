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
  double _overlayOpacity = .55;

  @override
  void initState() {
    super.initState();
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
    appBar: AppBar(title: const Text('FloodGuard Hazard Map')),
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _mapCard(),
        const SizedBox(height: 12),
        _layerControls(),
        const SizedBox(height: 12),
        _hazardSummaryCard(),
        const SizedBox(height: 12),
        _weatherCard(),
        const SizedBox(height: 20),
        Text(
          'Critical facilities',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Reference entries must be verified with the LGU before emergency use.',
        ),
        const SizedBox(height: 8),
        ..._facilities.map(_CenterCard.new),
        const SizedBox(height: 10),
        const Card(
          child: ListTile(
            leading: Icon(Icons.phone, color: Colors.red),
            title: Text('Emergency Hotline'),
            subtitle: Text(
              'For immediate emergencies, call 911 or your local DRRMO.',
            ),
            trailing: Text('911', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    ),
  );

  Widget _mapCard() => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: SizedBox(
      height: 340,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _mapCenter,
          initialZoom: 13,
          onTap: (_, point) => _moveAssessmentPoint(point),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors'),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _layerControls() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined, color: AppTheme.blue),
              const SizedBox(width: 8),
              Text(
                'Map layers',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '5-Year', label: Text('5-Year')),
              ButtonSegment(value: '25-Year', label: Text('25-Year')),
              ButtonSegment(value: '100-Year', label: Text('100-Year')),
            ],
            selected: {_returnPeriod},
            onSelectionChanged: (values) {
              setState(() => _returnPeriod = values.first);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showFloodHazard,
            onChanged: (value) => setState(() => _showFloodHazard = value),
            title: const Text('Flood hazard overlay'),
            subtitle: const Text('Low, medium, and high simulated zones'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _showFacilities,
            onChanged: (value) => setState(() => _showFacilities = value),
            title: const Text('Critical facilities'),
            subtitle: const Text('Evacuation, school, hospital, fire station'),
          ),
          Row(
            children: [
              const Text('Opacity'),
              Expanded(
                child: Slider(
                  value: _overlayOpacity,
                  min: .2,
                  max: .85,
                  divisions: 13,
                  label: '${(_overlayOpacity * 100).round()}%',
                  onChanged: (value) => setState(() => _overlayOpacity = value),
                ),
              ),
            ],
          ),
          const _HazardLegend(),
          const SizedBox(height: 8),
          const Text(
            'Tap the map to move the assessment pin and refresh local weather.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );

  Widget _hazardSummaryCard() {
    final zone = _nearestHazardZone();
    return Card(
      color: zone.color.withValues(alpha: .1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: zone.color.withValues(alpha: .18),
          child: Icon(Icons.flood_outlined, color: zone.color),
        ),
        title: Text('Hazard level near $_locationLabel'),
        subtitle: Text(
          '${zone.level} flood hazard, $_returnPeriod return period. '
          'Use this as a planning reference only.',
        ),
        trailing: IconButton(
          onPressed: _isRefreshing ? null : _useMyLocation,
          icon: _isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          tooltip: 'Use my live location',
        ),
      ),
    );
  }

  Widget _weatherCard() => Card(
    color: const Color(0xFFF0F6FF),
    child: ListTile(
      leading: _isRefreshing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloudy_snowing, color: AppTheme.blue),
      title: Text('Live weather near $_locationLabel'),
      subtitle: _weather != null
          ? Text(
              '${_weather!.temperatureCelsius.toStringAsFixed(1)} C, '
              'precipitation ${_weather!.precipitationMm.toStringAsFixed(1)} mm',
            )
          : Text(_weatherError ?? 'Loading current weather...'),
      trailing: IconButton(
        onPressed: _isRefreshing ? null : _loadWeather,
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh live weather',
      ),
    ),
  );

  CircleMarker _hazardCircle(_HazardZone zone) => CircleMarker(
    point: zone.point,
    radius: zone.radiusMeters * _returnPeriodMultiplier,
    useRadiusInMeter: true,
    color: zone.color.withValues(alpha: _overlayOpacity),
    borderStrokeWidth: 1.5,
    borderColor: zone.color,
  );

  Marker _facilityMarker(_Facility facility) => Marker(
    point: facility.point,
    width: 44,
    height: 44,
    child: Tooltip(
      message: facility.name,
      child: CircleAvatar(
        backgroundColor: Colors.white,
        child: Icon(
          _facilityIcon(facility.type),
          color: _facilityColor(facility),
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
  const _CenterCard(this.facility);

  final _Facility facility;

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
