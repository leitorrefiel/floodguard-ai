import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:supabase_flutter/supabase_flutter.dart';
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
  static const _mapStyle = 'https://tiles.openfreemap.org/styles/bright';
  static const _baliwag = ml.LatLng(14.9547, 120.8969);
  static const _facilities = [
    _Facility(
      name: 'Baliwag City Hall Evacuation Center',
      address: 'Baliwag, Bulacan',
      point: ml.LatLng(14.9547, 120.8969),
      type: _FacilityType.evacuation,
      recommended: true,
    ),
    _Facility(
      name: 'Baliwag North Central School',
      address: 'Baliwag, Bulacan',
      point: ml.LatLng(14.9636, 120.8996),
      type: _FacilityType.school,
    ),
    _Facility(
      name: 'Baliwag District Hospital',
      address: 'Baliwag, Bulacan',
      point: ml.LatLng(14.9506, 120.9018),
      type: _FacilityType.hospital,
    ),
    _Facility(
      name: 'Baliwag Fire Station',
      address: 'Baliwag, Bulacan',
      point: ml.LatLng(14.9584, 120.8912),
      type: _FacilityType.fireStation,
    ),
  ];

  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  ml.MapLibreMapController? _mapController;
  ml.LatLng _mapCenter = _baliwag;
  ml.LatLng _assessmentPoint = _baliwag;
  String _locationLabel = 'Baliwag, Bulacan';
  String _scenario = 'rare';
  DateTime? _locationUpdatedAt;
  WeatherSnapshot? _weather;
  String? _weatherError;
  bool _isRefreshing = false;
  bool _showFloodHazard = true;
  bool _showFacilities = false;
  bool _styleReady = false;
  bool _mapImagesReady = false;

  @override
  void initState() {
    super.initState();
    _restoreSavedLocation();
  }

  Future<void> _restoreSavedLocation() async {
    final location = await _locationService.getSavedLocation();
    if (location != null && mounted) {
      final point = ml.LatLng(location.latitude, location.longitude);
      setState(() {
        _mapCenter = point;
        _assessmentPoint = point;
        _locationLabel = location.label;
        _locationUpdatedAt = DateTime.now();
      });
      await _moveCamera(point, zoom: 15.4);
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
      final point = ml.LatLng(location.latitude, location.longitude);
      setState(() {
        _mapCenter = point;
        _assessmentPoint = point;
        _locationLabel = location.label;
        _locationUpdatedAt = DateTime.now();
      });
      await _moveCamera(point, zoom: 15.4);
      await _refreshMapAnnotations();
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

  Future<void> _moveAssessmentPoint(ml.LatLng point) async {
    setState(() {
      _assessmentPoint = point;
      _mapCenter = point;
      _locationLabel = 'Selected map area';
      _locationUpdatedAt = DateTime.now();
    });
    await _moveCamera(point, zoom: 15.4);
    await _refreshMapAnnotations();
    await _loadWeather();
  }

  Future<void> _focusFacility(_Facility facility) async {
    setState(() {
      _showFacilities = true;
      _mapCenter = facility.point;
    });
    await _moveCamera(facility.point, zoom: 16);
    await _refreshMapAnnotations();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Showing ${facility.name} on the map.')),
    );
  }

  Future<void> _moveCamera(ml.LatLng point, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      ml.CameraUpdate.newLatLngZoom(point, zoom ?? 15.4),
      duration: const Duration(milliseconds: 420),
    );
  }

  Future<void> _registerMapImages() async {
    final controller = _mapController;
    if (controller == null || _mapImagesReady) return;
    final markerBytes = await _buildPersonMarkerBytes(
      _currentPerson().initials,
    );
    await controller.addImage('fg-current-person', markerBytes);
    _mapImagesReady = true;
  }

  Future<Uint8List> _buildPersonMarkerBytes(String initials) async {
    const size = 112.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: .18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center + const Offset(0, 5), 43, shadowPaint);

    canvas.drawCircle(center, 44, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      39,
      Paint()
        ..color = AppTheme.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6,
    );
    canvas.drawCircle(center, 30, Paint()..color = AppTheme.paleBlue);

    final textPainter = TextPainter(
      text: TextSpan(
        text: initials,
        style: const TextStyle(
          color: AppTheme.navy,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<void> _refreshMapAnnotations() async {
    final controller = _mapController;
    if (controller == null || !_styleReady) return;
    await controller.clearCircles();
    await controller.clearSymbols();
    await _registerMapImages();

    if (_showFloodHazard) {
      await controller.addCircle(_hazardHaloCircle(_nearestHazardZone()));
    }
    if (_showFacilities) {
      await controller.addCircles(_facilities.map(_facilityCircle).toList());
    }
    await controller.addCircle(
      ml.CircleOptions(
        geometry: _assessmentPoint,
        circleRadius: 14,
        circleColor: '#2563EB',
        circleOpacity: 1,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 5,
      ),
    );
    await controller.addCircle(
      ml.CircleOptions(
        geometry: _assessmentPoint,
        circleRadius: 22,
        circleColor: '#2563EB',
        circleOpacity: .12,
        circleStrokeColor: '#2563EB',
        circleStrokeOpacity: .24,
        circleStrokeWidth: 1,
      ),
    );
    await controller.addSymbol(
      ml.SymbolOptions(
        geometry: _assessmentPoint,
        iconImage: 'fg-current-person',
        iconSize: .9,
        iconAnchor: 'center',
        zIndex: 10,
      ),
    );
    await controller.setSymbolIconAllowOverlap(true);
    await controller.setSymbolIconIgnorePlacement(true);
  }

  void _toggleFloodZones() {
    setState(() => _showFloodHazard = !_showFloodHazard);
    _refreshMapAnnotations();
  }

  void _toggleFacilities() {
    setState(() => _showFacilities = !_showFacilities);
    _refreshMapAnnotations();
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
          _bottomSheet(context),
        ],
      ),
    ),
  );

  Widget _mapView() => ml.MapLibreMap(
    initialCameraPosition: ml.CameraPosition(target: _mapCenter, zoom: 15.4),
    styleString: _mapStyle,
    compassEnabled: false,
    rotateGesturesEnabled: false,
    myLocationEnabled: false,
    attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
    onMapCreated: (controller) {
      _mapController = controller;
      _moveCamera(_assessmentPoint, zoom: 15.4);
    },
    onStyleLoadedCallback: () {
      _styleReady = true;
      _mapImagesReady = false;
      _moveCamera(_assessmentPoint, zoom: 15.4);
      _refreshMapAnnotations();
    },
    onMapClick: (_, point) => _moveAssessmentPoint(point),
    annotationOrder: const [ml.AnnotationType.circle, ml.AnnotationType.symbol],
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
          label: 'Locate',
          icon: Icons.my_location,
          selected: true,
          onPressed: _isRefreshing ? null : _useMyLocation,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Flood layer',
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

  Widget _bottomSheet(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .36,
    minChildSize: .26,
    maxChildSize: .78,
    snap: true,
    snapSizes: const [.36, .78],
    builder: (context, scrollController) => DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
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
          _selectedUserCard(context),
          const SizedBox(height: 10),
          _peopleSelector(),
          const SizedBox(height: 12),
          _hazardSummaryCard(),
          const SizedBox(height: 8),
          _scenarioSelector(),
          const SizedBox(height: 8),
          const _HazardLegend(),
          const SizedBox(height: 6),
          const Text(
            'The colored halo marks the assessed flood-prone area. Tap the map to check another spot.',
            style: TextStyle(color: Color(0xFF5B6677), fontSize: 12),
          ),
          const SizedBox(height: 10),
          const _EmergencyHelpCard(),
          const SizedBox(height: 10),
          _weatherCard(),
          const SizedBox(height: 10),
          Text(
            'Critical Facilities',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ..._facilities.map(
            (facility) =>
                _CenterCard(facility, onTap: () => _focusFacility(facility)),
          ),
        ],
      ),
    ),
  );

  Widget _selectedUserCard(BuildContext context) {
    final person = _currentPerson();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _PersonAvatar(person: person, selected: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  person.locationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEAFBF1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  person.updatedLabel,
                  style: const TextStyle(
                    color: Color(0xFF166534),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _peopleSelector() {
    final person = _currentPerson();
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _PersonChip(
            person: person,
            selected: true,
            onTap: () => _moveCamera(_assessmentPoint, zoom: 15.8),
          ),
        ],
      ),
    );
  }

  Widget _scenarioSelector() => Row(
    children: [
      _ScenarioChip(
        label: 'Usual',
        selected: _scenario == 'usual',
        onTap: () => _setScenario('usual'),
      ),
      const SizedBox(width: 8),
      _ScenarioChip(
        label: 'Heavy',
        selected: _scenario == 'heavy',
        onTap: () => _setScenario('heavy'),
      ),
      const SizedBox(width: 8),
      _ScenarioChip(
        label: 'Rare',
        selected: _scenario == 'rare',
        onTap: () => _setScenario('rare'),
      ),
    ],
  );

  void _setScenario(String scenario) {
    setState(() => _scenario = scenario);
    _refreshMapAnnotations();
  }

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

  _TrackedMapPerson _currentPerson() {
    final user = Supabase.instance.client.auth.currentUser;
    final metadataName =
        user?.userMetadata?['name'] as String? ??
        user?.userMetadata?['full_name'] as String?;
    final fallbackName = user?.email?.split('@').first;
    final name = _cleanName(metadataName ?? fallbackName ?? 'You');
    return _TrackedMapPerson(
      name: name,
      initials: _initials(name),
      locationLabel: _locationLabel,
      updatedLabel: _locationUpdatedLabel,
    );
  }

  String get _locationUpdatedLabel {
    final updatedAt = _locationUpdatedAt;
    if (updatedAt == null) return 'Live';
    final elapsed = DateTime.now().difference(updatedAt);
    if (elapsed.inMinutes < 1) return 'Live';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h';
    return '${elapsed.inDays}d';
  }

  String _cleanName(String value) {
    final trimmed = value.trim().replaceAll(RegExp(r'[._-]+'), ' ');
    if (trimmed.isEmpty) return 'You';
    return trimmed
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) return part;
          return '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Y';
    final first = parts.first[0];
    final second = parts.length > 1 ? parts.last[0] : '';
    return '$first$second'.toUpperCase();
  }

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

  ml.CircleOptions _hazardHaloCircle(_HazardZone zone) => ml.CircleOptions(
    geometry: _assessmentPoint,
    circleRadius: zone.radiusPixels * _scenarioMultiplier,
    circleColor: _hex(zone.color),
    circleOpacity: .2,
    circleBlur: .18,
    circleStrokeWidth: 2.5,
    circleStrokeColor: _hex(zone.color),
    circleStrokeOpacity: .52,
  );

  ml.CircleOptions _facilityCircle(_Facility facility) => ml.CircleOptions(
    geometry: facility.point,
    circleRadius: facility.recommended ? 9 : 8,
    circleColor: _facilityHexColor(facility),
    circleOpacity: .95,
    circleStrokeColor: '#FFFFFF',
    circleStrokeWidth: 3,
  );

  _HazardZone _nearestHazardZone() {
    final zones = _hazardZones().toList();
    zones.sort(
      (a, b) => _distanceMeters(
        _assessmentPoint,
        a.point,
      ).compareTo(_distanceMeters(_assessmentPoint, b.point)),
    );
    return zones.first;
  }

  List<_HazardZone> _hazardZones() => const [
    _HazardZone(
      level: 'High',
      point: ml.LatLng(14.9526, 120.8912),
      radiusPixels: 56,
      color: Color(0xFFDC2626),
    ),
    _HazardZone(
      level: 'Medium',
      point: ml.LatLng(14.9615, 120.9004),
      radiusPixels: 48,
      color: Color(0xFFF59E0B),
    ),
    _HazardZone(
      level: 'Low',
      point: ml.LatLng(14.9468, 120.9044),
      radiusPixels: 40,
      color: Color(0xFF22C55E),
    ),
  ];

  double get _scenarioMultiplier => switch (_scenario) {
    'usual' => .72,
    'heavy' => .9,
    _ => 1.12,
  };

  String _facilityHexColor(_Facility facility) {
    if (facility.recommended) return '#16A34A';
    return switch (facility.type) {
      _FacilityType.hospital => '#DC2626',
      _FacilityType.fireStation => '#F97316',
      _ => '#2563EB',
    };
  }

  double _distanceMeters(ml.LatLng a, ml.LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final deltaLat = _radians(b.latitude - a.latitude);
    final deltaLng = _radians(b.longitude - a.longitude);
    final h =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  double _radians(double degrees) => degrees * math.pi / 180;

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
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

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.person, required this.selected});

  final _TrackedMapPerson person;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: selected ? 54 : 48,
    height: selected ? 54 : 48,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? AppTheme.blue : const Color(0xFFD8E1EE),
        width: selected ? 3 : 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18000000),
          blurRadius: 12,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Center(
      child: CircleAvatar(
        radius: selected ? 21 : 18,
        backgroundColor: AppTheme.paleBlue,
        foregroundColor: AppTheme.navy,
        child: Text(
          person.initials,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({
    required this.person,
    required this.selected,
    required this.onTap,
  });

  final _TrackedMapPerson person;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: 'Focus ${person.name}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 82,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF3FF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppTheme.blue : const Color(0xFFE3EAF4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PersonAvatar(person: person, selected: false),
            const SizedBox(height: 5),
            Text(
              person.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppTheme.navy : AppTheme.ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
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
    elevation: 5,
    shadowColor: const Color(0x24000000),
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ScenarioChip extends StatelessWidget {
  const _ScenarioChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: selected ? const Color(0xFFE7EEFF) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppTheme.blue : const Color(0xFFD8E1EE),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.blue : AppTheme.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
      padding: const EdgeInsets.all(14),
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
            'Tap Call to open the phone dialer.',
            style: TextStyle(color: Color(0xFF5B6677), fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _numbers
                .map(
                  (item) => FilledButton.icon(
                    onPressed: () => _call(context, item.number),
                    icon: const Icon(Icons.phone, size: 16),
                    label: Text(item.displayNumber),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Text(
            _numbers.map((item) => item.label).join(' / '),
            style: const TextStyle(color: Color(0xFF5B6677), fontSize: 12),
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

class _TrackedMapPerson {
  const _TrackedMapPerson({
    required this.name,
    required this.initials,
    required this.locationLabel,
    required this.updatedLabel,
  });

  final String name;
  final String initials;
  final String locationLabel;
  final String updatedLabel;
}

class _HazardZone {
  const _HazardZone({
    required this.level,
    required this.point,
    required this.radiusPixels,
    required this.color,
  });

  final String level;
  final ml.LatLng point;
  final double radiusPixels;
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
  final ml.LatLng point;
  final _FacilityType type;
  final bool recommended;
}

enum _FacilityType { evacuation, school, hospital, fireStation }
