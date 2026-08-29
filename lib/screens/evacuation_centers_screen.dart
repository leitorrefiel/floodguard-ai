import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:url_launcher/url_launcher.dart';

import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import '../services/device_location_service.dart';
import '../services/hazard_map_service.dart';
import '../services/risk_service.dart';
import '../services/weather_layer_service.dart';
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
  static const _assessmentSourceId = 'fg-assessment-source';
  static const _assessmentRadiusLayerId = 'fg-assessment-radius-layer';
  static const _assessmentDotLayerId = 'fg-assessment-dot-layer';
  static const _floodSourceId = 'fg-flood-source';
  static const _floodLayerId = 'fg-flood-layer';
  static const _hazardSourceId = 'fg-hazard-report-source';
  static const _hazardLayerId = 'fg-hazard-report-layer';
  static const _hazardLabelLayerId = 'fg-hazard-label-layer';
  static const _facilitySourceId = 'fg-facility-source';
  static const _facilityLayerId = 'fg-facility-layer';
  static const _facilityLabelLayerId = 'fg-facility-label-layer';

  final _locationService = DeviceLocationService();
  final _weatherService = WeatherService();
  final _riskService = const RiskService();
  final _hazardMapService = HazardMapService();
  final _weatherLayerService = WeatherLayerService();

  ml.MapLibreMapController? _mapController;
  ml.LatLng _mapCenter = _baliwag;
  ml.LatLng _assessmentPoint = _baliwag;
  String _locationLabel = 'Baliwag, Bulacan';
  String _scenario = 'heavy';
  DateTime? _locationUpdatedAt;
  WeatherSnapshot? _weather;
  RiskAssessment? _riskAssessment;
  HazardMapData? _mapData;
  String? _weatherError;
  String? _mapDataError;
  bool _isRefreshing = false;
  bool _isLoadingMapData = true;
  bool _showWeatherRadar = false;
  bool _showFloodHazard = true;
  bool _showHazards = true;
  bool _showFacilities = true;
  bool _styleReady = false;
  bool _layersInstalled = false;
  bool _isSheetExpanded = false;

  @override
  void initState() {
    super.initState();
    _restoreSavedLocation();
    _loadHazardMapData();
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
    await _loadWeatherAndRisk();
  }

  Future<void> _loadHazardMapData() async {
    setState(() {
      _isLoadingMapData = true;
      _mapDataError = null;
    });
    try {
      final data = await _hazardMapService.load();
      if (!mounted) return;
      setState(() => _mapData = data);
      await _updateMapSources();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mapDataError = 'Hazards are unavailable. The map is still usable.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingMapData = false);
    }
  }

  Future<void> _loadWeatherAndRisk() async {
    setState(() {
      _isRefreshing = true;
      _weatherError = null;
    });
    try {
      final forecast = await _weatherService.getForecast(
        latitude: _assessmentPoint.latitude,
        longitude: _assessmentPoint.longitude,
      );
      final assessment = _riskService.assess(
        forecast,
        locationLabel: _locationLabel,
      );
      if (!mounted) return;
      setState(() {
        _weather = forecast.current;
        _riskAssessment = assessment;
      });
      await _updateMapSources();
    } on WeatherException catch (error) {
      if (!mounted) return;
      setState(() => _weatherError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _weatherError = 'Check your internet connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadWeatherAndRisk(), _loadHazardMapData()]);
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
      await _moveCamera(point, zoom: 15.6);
      await _updateMapSources();
      await _loadWeatherAndRisk();
    } on LocationAccessException catch (error) {
      if (mounted) _message(error.message);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _handleMapTap(
    math.Point<double> screenPoint,
    ml.LatLng coordinate,
  ) async {
    final feature = await _featureAt(screenPoint);
    if (feature != null) {
      _showFeatureDetails(_propertiesOf(feature));
      return;
    }
    await _moveAssessmentPoint(coordinate);
  }

  Future<Map<dynamic, dynamic>?> _featureAt(math.Point<double> point) async {
    final controller = _mapController;
    if (controller == null || !_layersInstalled) return null;
    try {
      final features = await controller.queryRenderedFeatures(point, [
        _hazardLayerId,
        _facilityLayerId,
      ], null);
      if (features.isEmpty || features.first is! Map) return null;
      return features.first as Map<dynamic, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _propertiesOf(Map<dynamic, dynamic> feature) {
    final properties = feature['properties'];
    if (properties is Map) return Map<String, dynamic>.from(properties);
    return const {};
  }

  Future<void> _moveAssessmentPoint(ml.LatLng point) async {
    setState(() {
      _assessmentPoint = point;
      _mapCenter = point;
      _locationLabel = 'Selected map area';
      _locationUpdatedAt = DateTime.now();
    });
    await _updateMapSources();
    await _loadWeatherAndRisk();
  }

  Future<void> _focusFacility(EmergencyFacility facility) async {
    final point = _latLng(facility.coordinate);
    setState(() {
      _showFacilities = true;
      _mapCenter = point;
    });
    await _moveCamera(point, zoom: 16.3);
    await _updateMapSources();
    if (mounted) _message('Showing ${facility.name} on the map.');
  }

  Future<void> _moveCamera(ml.LatLng point, {double? zoom}) async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.animateCamera(
      ml.CameraUpdate.newLatLngZoom(point, zoom ?? 15.4),
      duration: const Duration(milliseconds: 420),
    );
  }

  Future<void> _installMapLayers() async {
    final controller = _mapController;
    if (controller == null || !_styleReady || _layersInstalled) return;

    await controller.addGeoJsonSource(_floodSourceId, _emptyCollection());
    await controller.addGeoJsonSource(_assessmentSourceId, _emptyCollection());
    await controller.addGeoJsonSource(_hazardSourceId, _emptyCollection());
    await controller.addGeoJsonSource(_facilitySourceId, _emptyCollection());

    await controller.addFillLayer(
      _floodSourceId,
      _floodLayerId,
      const ml.FillLayerProperties(
        fillColor: ['get', 'color'],
        fillOpacity: .2,
        fillOutlineColor: ['get', 'stroke'],
      ),
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _assessmentSourceId,
      _assessmentRadiusLayerId,
      const ml.CircleLayerProperties(
        circleRadius: 34,
        circleColor: '#2563EB',
        circleOpacity: .14,
        circleStrokeColor: '#2563EB',
        circleStrokeOpacity: .25,
        circleStrokeWidth: 1,
      ),
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _assessmentSourceId,
      _assessmentDotLayerId,
      const ml.CircleLayerProperties(
        circleRadius: 13,
        circleColor: '#2563EB',
        circleOpacity: 1,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 5,
      ),
      enableInteraction: false,
    );
    await controller.addCircleLayer(
      _hazardSourceId,
      _hazardLayerId,
      const ml.CircleLayerProperties(
        circleRadius: ['get', 'radius'],
        circleColor: ['get', 'color'],
        circleOpacity: .96,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );
    await controller.addSymbolLayer(
      _hazardSourceId,
      _hazardLabelLayerId,
      const ml.SymbolLayerProperties(
        textField: ['get', 'code'],
        textSize: 11,
        textColor: '#0F172A',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.2,
        textOffset: [0, 1.25],
        textAllowOverlap: false,
      ),
      minzoom: 13,
    );
    await controller.addCircleLayer(
      _facilitySourceId,
      _facilityLayerId,
      const ml.CircleLayerProperties(
        circleRadius: 10,
        circleColor: ['get', 'color'],
        circleOpacity: .96,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );
    await controller.addSymbolLayer(
      _facilitySourceId,
      _facilityLabelLayerId,
      const ml.SymbolLayerProperties(
        textField: ['get', 'code'],
        textSize: 11,
        textColor: '#0F172A',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.2,
        textOffset: [0, 1.25],
        textAllowOverlap: false,
      ),
      minzoom: 13,
    );

    await _weatherLayerService.installIfConfigured(controller);
    _layersInstalled = true;
    await _updateMapSources();
  }

  Future<void> _updateMapSources() async {
    final controller = _mapController;
    if (controller == null || !_layersInstalled) return;
    try {
      await controller.setGeoJsonSource(
        _assessmentSourceId,
        _pointCollection(_assessmentPoint, {
          'kind': 'assessment',
          'title': 'Assessment location',
        }),
      );
      await controller.setGeoJsonSource(
        _floodSourceId,
        _showFloodHazard ? _floodGeoJson() : _emptyCollection(),
      );
      await controller.setGeoJsonSource(
        _hazardSourceId,
        _showHazards ? _hazardReportsGeoJson() : _emptyCollection(),
      );
      await controller.setGeoJsonSource(
        _facilitySourceId,
        _showFacilities ? _facilitiesGeoJson() : _emptyCollection(),
      );
      await _weatherLayerService.setVisible(
        controller,
        visible: _showWeatherRadar,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mapDataError = 'Map layers could not refresh. Try again.';
      });
    }
  }

  void _toggleWeatherRadar() {
    if (!_weatherLayerService.hasConfiguredRadar) {
      _message('Rain radar layer is ready, but no live radar tile API is set.');
      return;
    }
    setState(() => _showWeatherRadar = !_showWeatherRadar);
    _updateMapSources();
  }

  void _toggleFloodZones() {
    setState(() => _showFloodHazard = !_showFloodHazard);
    _updateMapSources();
  }

  void _toggleHazards() {
    setState(() => _showHazards = !_showHazards);
    _updateMapSources();
  }

  void _toggleFacilities() {
    setState(() => _showFacilities = !_showFacilities);
    _updateMapSources();
  }

  void _setScenario(String scenario) {
    setState(() => _scenario = scenario);
    _updateMapSources();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: Column(
      mainAxisSize: MainAxisSize.min,
      children: [_bottomSheet(context), const AppBottomNav(index: 0)],
    ),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: ClipRect(child: _mapView())),
          _topBar(context),
          _mapQuickActions(),
          if (_isLoadingMapData || _mapDataError != null) _mapStateChip(),
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
    translucentTextureSurface: true,
    attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
    onMapCreated: (controller) {
      _mapController = controller;
      _moveCamera(_assessmentPoint, zoom: 15.4);
    },
    onStyleLoadedCallback: () {
      _styleReady = true;
      _layersInstalled = false;
      _weatherLayerService.reset();
      _installMapLayers();
    },
    onMapClick: _handleMapTap,
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
          onPressed: _isRefreshing ? null : _refreshAll,
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
    right: 14,
    top: 88,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _MapActionButton(
          label: 'Locate',
          icon: Icons.my_location,
          selected: false,
          onPressed: _isRefreshing ? null : _useMyLocation,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Weather',
          icon: Icons.radar_outlined,
          selected: _showWeatherRadar,
          onPressed: _toggleWeatherRadar,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Flood',
          icon: Icons.flood_outlined,
          selected: _showFloodHazard,
          onPressed: _toggleFloodZones,
        ),
        const SizedBox(height: 8),
        _MapActionButton(
          label: 'Hazards',
          icon: Icons.report_problem_outlined,
          selected: _showHazards,
          onPressed: _toggleHazards,
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

  Widget _mapStateChip() => Positioned(
    top: 72,
    left: 18,
    right: 150,
    child: Material(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoadingMapData)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.info_outline, size: 16, color: AppTheme.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _isLoadingMapData ? 'Loading map layers...' : _mapDataError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _bottomSheet(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * (_isSheetExpanded ? .68 : .34),
    child: Material(
      color: const Color(0xFFF8FBFF),
      elevation: 12,
      shadowColor: const Color(0x26000000),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) {
            setState(() => _isSheetExpanded = true);
          } else if (velocity > 120) {
            setState(() => _isSheetExpanded = false);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _isSheetExpanded = !_isSheetExpanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
                  child: Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5DEEC),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
              _statusHeaderCard(),
              const SizedBox(height: 10),
              if (_isSheetExpanded) ...[
                _scenarioSelector(),
                const SizedBox(height: 8),
                const _HazardLegend(),
                const SizedBox(height: 8),
                _layerNote(),
                const SizedBox(height: 10),
              ],
              const _EmergencyQuickButtons(),
              if (_isSheetExpanded) ...[
                const SizedBox(height: 10),
                _weatherCard(),
                const SizedBox(height: 10),
                _facilitySummaryCard(),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _statusHeaderCard() {
    final level = _riskShortLevel;
    final color = _riskColor(level);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: .14),
            child: Icon(Icons.flood_outlined, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$level flood risk',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _locationLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 8),
                Text(
                  _riskAssessment?.summary ??
                      'Waiting for live weather before final assessment.',
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _locationUpdatedLabel,
            style: const TextStyle(
              color: Color(0xFF166534),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
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
        label: 'Extreme',
        selected: _scenario == 'rare',
        onTap: () => _setScenario('rare'),
      ),
    ],
  );

  Widget _layerNote() {
    final mapped = _mapData?.reports.length ?? 0;
    final unmapped = _mapData?.unmappedReportCount ?? 0;
    final source = _mapData?.storageLabel ?? 'hazard service';
    final radar = _weatherLayerService.hasConfiguredRadar
        ? 'Weather radar overlay is available.'
        : 'Weather radar needs a real tile API before it can be shown.';
    return Text(
      'Tap the map to assess a spot. Hazard reports: $mapped mapped'
      '${unmapped > 0 ? ', $unmapped without coordinates' : ''} from $source. $radar',
      style: const TextStyle(color: Color(0xFF5B6677), fontSize: 12),
    );
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

  Widget _facilitySummaryCard() {
    final facilities = _mapData?.facilities ?? HazardMapService.facilities;
    final reports = _mapData?.reports ?? const <MappedHazardReport>[];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: AppTheme.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${facilities.length} facilities and ${reports.length} hazard reports on map',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(
            onPressed: _showMapDetailsSheet,
            child: const Text('Details'),
          ),
        ],
      ),
    );
  }

  void _showMapDetailsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              const _EmergencyHelpCard(),
              const SizedBox(height: 14),
              _nearbyHazardsSection(sheetContext),
              const SizedBox(height: 14),
              _facilitiesSection(sheetContext),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nearbyHazardsSection(BuildContext context) {
    final reports = _mapData?.reports ?? const <MappedHazardReport>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Community Hazards',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (reports.isEmpty)
          const _EmptyLayerCard(
            icon: Icons.report_problem_outlined,
            title: 'No mapped hazard reports',
            detail:
                'Submitted reports still appear after their location is resolved.',
          )
        else
          ...reports
              .take(4)
              .map(
                (item) => _HazardReportCard(
                  item,
                  onTap: () {
                    _moveCamera(_latLng(item.coordinate), zoom: 16.2);
                    _showFeatureDetails(_hazardProperties(item));
                  },
                ),
              ),
      ],
    );
  }

  Widget _facilitiesSection(BuildContext context) {
    final facilities = _mapData?.facilities ?? HazardMapService.facilities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Critical Facilities',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...facilities.map(
          (facility) =>
              _FacilityCard(facility, onTap: () => _focusFacility(facility)),
        ),
      ],
    );
  }

  Map<String, dynamic> _floodGeoJson() {
    final level = _riskShortLevel;
    final color = _riskColor(level);
    return _featureCollection([
      _circlePolygonFeature(
        center: _assessmentPoint,
        radiusMeters: _scenarioRadiusMeters(level),
        properties: {
          'kind': 'flood',
          'title': '$level flood risk',
          'location': _locationLabel,
          'color': _hex(color),
          'stroke': _hex(color.withValues(alpha: .9)),
        },
      ),
    ]);
  }

  Map<String, dynamic> _hazardReportsGeoJson() {
    final reports = _mapData?.reports ?? const <MappedHazardReport>[];
    return _featureCollection(
      reports.map((item) {
        final point = _latLng(item.coordinate);
        return _pointFeature(point, _hazardProperties(item));
      }).toList(),
    );
  }

  Map<String, dynamic> _facilitiesGeoJson() {
    final facilities = _mapData?.facilities ?? HazardMapService.facilities;
    return _featureCollection(
      facilities.map((facility) {
        final point = _latLng(facility.coordinate);
        return _pointFeature(point, _facilityProperties(facility));
      }).toList(),
    );
  }

  Map<String, dynamic> _hazardProperties(MappedHazardReport item) {
    final report = item.report;
    return {
      'kind': 'hazard',
      'id': 'hazard-${report.id}',
      'title': hazardTypeLabel(report.type),
      'severity': report.severity,
      'location': report.location,
      'description': report.description.isEmpty
          ? 'No description provided.'
          : report.description,
      'time': _formatDateTime(report.createdAt),
      'status': 'Submitted',
      'color': _hex(_severityColor(report.severity)),
      'radius': _severityRadius(report.severity),
      'code': _hazardCode(report.type),
    };
  }

  Map<String, dynamic> _facilityProperties(EmergencyFacility facility) => {
    'kind': 'facility',
    'id': facility.id,
    'title': facility.name,
    'severity': emergencyFacilityTypeLabel(facility.type),
    'location': facility.address,
    'description': facility.recommended
        ? 'Recommended reference site. Verify opening status with the LGU.'
        : 'Reference facility. Verify status before emergency use.',
    'time': 'Reference facility',
    'status': facility.recommended ? 'Recommended' : 'Reference',
    'color': _facilityHexColor(facility),
    'radius': facility.recommended ? 11 : 10,
    'code': _facilityCode(facility.type),
  };

  Map<String, dynamic> _pointCollection(
    ml.LatLng point,
    Map<String, dynamic> properties,
  ) => _featureCollection([_pointFeature(point, properties)]);

  Map<String, dynamic> _pointFeature(
    ml.LatLng point,
    Map<String, dynamic> properties,
  ) => {
    'type': 'Feature',
    'id': properties['id'] ?? properties['title'] ?? 'point',
    'properties': properties,
    'geometry': {
      'type': 'Point',
      'coordinates': [point.longitude, point.latitude],
    },
  };

  Map<String, dynamic> _circlePolygonFeature({
    required ml.LatLng center,
    required double radiusMeters,
    required Map<String, dynamic> properties,
  }) {
    final coordinates = <List<double>>[];
    final latRadians = _radians(center.latitude);
    final metersPerLat = 111320.0;
    final metersPerLng = 111320.0 * math.cos(latRadians);

    for (var i = 0; i <= 72; i++) {
      final angle = 2 * math.pi * i / 72;
      final lat =
          center.latitude + (math.sin(angle) * radiusMeters / metersPerLat);
      final lng =
          center.longitude + (math.cos(angle) * radiusMeters / metersPerLng);
      coordinates.add([lng, lat]);
    }

    return {
      'type': 'Feature',
      'id': 'current-flood-assessment',
      'properties': properties,
      'geometry': {
        'type': 'Polygon',
        'coordinates': [coordinates],
      },
    };
  }

  Map<String, dynamic> _featureCollection(
    List<Map<String, dynamic>> features,
  ) => {'type': 'FeatureCollection', 'features': features};

  Map<String, dynamic> _emptyCollection() => _featureCollection([]);

  void _showFeatureDetails(Map<String, dynamic> properties) {
    if (properties.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _FeatureDetailsSheet(properties: properties),
    );
  }

  String get _riskShortLevel {
    final value = _riskAssessment?.level.replaceAll(' Risk', '');
    return value == null || value.isEmpty ? 'Minimal' : value;
  }

  String get _locationUpdatedLabel {
    final updatedAt = _locationUpdatedAt;
    if (updatedAt == null) return 'Live';
    final elapsed = DateTime.now().difference(updatedAt);
    if (elapsed.inMinutes < 1) return 'Live';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  double _scenarioRadiusMeters(String level) {
    final base = switch (level) {
      'High' => 700.0,
      'Moderate' => 560.0,
      'Low' => 420.0,
      _ => 300.0,
    };
    final multiplier = switch (_scenario) {
      'usual' => .78,
      'heavy' => 1.0,
      _ => 1.22,
    };
    return base * multiplier;
  }

  Color _riskColor(String level) => switch (level) {
    'High' => const Color(0xFFDC2626),
    'Moderate' => const Color(0xFFF59E0B),
    'Low' => const Color(0xFF22C55E),
    _ => AppTheme.blue,
  };

  Color _severityColor(String severity) => switch (severity) {
    'Critical' => const Color(0xFF991B1B),
    'High' => const Color(0xFFDC2626),
    'Moderate' => const Color(0xFFF59E0B),
    'Low' => const Color(0xFF22C55E),
    _ => AppTheme.blue,
  };

  double _severityRadius(String severity) => switch (severity) {
    'Critical' => 13,
    'High' => 12,
    'Moderate' => 10,
    'Low' => 9,
    _ => 9,
  };

  String _facilityHexColor(EmergencyFacility facility) {
    if (facility.recommended) return '#16A34A';
    return switch (facility.type) {
      EmergencyFacilityType.hospital => '#DC2626',
      EmergencyFacilityType.fireStation => '#F97316',
      EmergencyFacilityType.evacuation => '#16A34A',
      EmergencyFacilityType.school => '#2563EB',
    };
  }

  String _hazardCode(HazardType type) => switch (type) {
    HazardType.floodedRoad => 'FR',
    HazardType.cloggedDrainage => 'CD',
    HazardType.blockedWaterway => 'BW',
    HazardType.overflowingCanal => 'OC',
  };

  String _facilityCode(EmergencyFacilityType type) => switch (type) {
    EmergencyFacilityType.evacuation => 'EC',
    EmergencyFacilityType.school => 'SC',
    EmergencyFacilityType.hospital => 'HP',
    EmergencyFacilityType.fireStation => 'FS',
  };

  ml.LatLng _latLng(MapCoordinate coordinate) =>
      ml.LatLng(coordinate.latitude, coordinate.longitude);

  double _radians(double degrees) => degrees * math.pi / 180;

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  String _formatDateTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.month}/${value.day}/${value.year}, $hour:$minute $meridiem';
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _HazardLegend extends StatelessWidget {
  const _HazardLegend();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      _LegendItem(color: Color(0xFF22C55E), label: 'Low'),
      SizedBox(width: 12),
      _LegendItem(color: Color(0xFFF59E0B), label: 'Moderate'),
      SizedBox(width: 12),
      _LegendItem(color: Color(0xFFDC2626), label: 'High'),
      SizedBox(width: 12),
      _LegendItem(color: Color(0xFF991B1B), label: 'Critical'),
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
        width: 12,
        height: 12,
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
    color: selected ? AppTheme.blue : Colors.white.withValues(alpha: .96),
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
                fontWeight: FontWeight.w800,
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
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _HazardReportCard extends StatelessWidget {
  const _HazardReportCard(this.item, {required this.onTap});

  final MappedHazardReport item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: _color(item.report.severity).withValues(alpha: .12),
        child: Icon(
          _icon(item.report.type),
          color: _color(item.report.severity),
        ),
      ),
      title: Text(
        hazardTypeLabel(item.report.type),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${item.report.location}\n${item.report.severity} severity',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.info_outline),
      onTap: onTap,
    ),
  );

  Color _color(String severity) => switch (severity) {
    'Critical' => const Color(0xFF991B1B),
    'High' => const Color(0xFFDC2626),
    'Moderate' => const Color(0xFFF59E0B),
    'Low' => const Color(0xFF22C55E),
    _ => AppTheme.blue,
  };

  IconData _icon(HazardType type) => switch (type) {
    HazardType.floodedRoad => Icons.directions_car_outlined,
    HazardType.cloggedDrainage => Icons.water_damage_outlined,
    HazardType.blockedWaterway => Icons.waves_outlined,
    HazardType.overflowingCanal => Icons.water_outlined,
  };
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard(this.facility, {required this.onTap});

  final EmergencyFacility facility;
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
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text('${facility.address}\n${_detail(facility)}'),
      isThreeLine: true,
      trailing: const Icon(Icons.map_outlined),
      onTap: onTap,
    ),
  );

  String _detail(EmergencyFacility facility) {
    if (facility.recommended) {
      return 'Recommended reference site, verify opening status with the LGU.';
    }
    return 'Reference facility, verify status before emergency use.';
  }

  IconData _icon(EmergencyFacilityType type) => switch (type) {
    EmergencyFacilityType.evacuation => Icons.home_work_outlined,
    EmergencyFacilityType.school => Icons.school_outlined,
    EmergencyFacilityType.hospital => Icons.local_hospital_outlined,
    EmergencyFacilityType.fireStation => Icons.local_fire_department_outlined,
  };
}

class _EmptyLayerCard extends StatelessWidget {
  const _EmptyLayerCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE3EAF4)),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppTheme.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(detail, style: const TextStyle(color: AppTheme.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmergencyQuickButtons extends StatelessWidget {
  const _EmergencyQuickButtons();

  @override
  Widget build(BuildContext context) {
    final numbers = _EmergencyHelpCard._numbers;
    return Row(
      children: [
        for (var i = 0; i < numbers.length; i++) ...[
          Expanded(
            child: FilledButton.icon(
              onPressed: () =>
                  _EmergencyHelpCard._call(context, numbers[i].number),
              icon: const Icon(Icons.phone, size: 15),
              label: FittedBox(child: Text(numbers[i].displayNumber)),
            ),
          ),
          if (i < numbers.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _FeatureDetailsSheet extends StatelessWidget {
  const _FeatureDetailsSheet({required this.properties});

  final Map<String, dynamic> properties;

  @override
  Widget build(BuildContext context) {
    final title = properties['title']?.toString() ?? 'Map item';
    final severity = properties['severity']?.toString() ?? '';
    final location = properties['location']?.toString() ?? '';
    final description = properties['description']?.toString() ?? '';
    final time = properties['time']?.toString() ?? '';
    final status = properties['status']?.toString() ?? '';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (severity.isNotEmpty) _DetailRow('Type / Severity', severity),
            if (location.isNotEmpty) _DetailRow('Location', location),
            if (description.isNotEmpty) _DetailRow('Details', description),
            if (time.isNotEmpty) _DetailRow('Time', time),
            if (status.isNotEmpty) _DetailRow('Status', status),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(value),
      ],
    ),
  );
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
          ..._numbers.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          item.detail,
                          style: const TextStyle(
                            color: Color(0xFF5B6677),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _call(context, item.number),
                    icon: const Icon(Icons.phone, size: 16),
                    label: Text(item.displayNumber),
                  ),
                ],
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
  final String detail;
  final String displayNumber;
}
