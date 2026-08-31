import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:url_launcher/url_launcher.dart';

import '../data/demo_map_data.dart';
import '../models/hazard_report.dart';
import '../models/map_hazard.dart';
import '../services/device_location_service.dart';
import '../services/hazard_map_service.dart';
import '../utils/app_theme.dart';
import '../widgets/app_bottom_nav.dart';

enum HazardMapInitialMode { general, facilities }

class EvacuationCentersScreen extends StatefulWidget {
  const EvacuationCentersScreen({
    super.key,
    this.initialMode = HazardMapInitialMode.general,
    this.focusReportId,
  });

  final HazardMapInitialMode initialMode;
  final String? focusReportId;

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
  static const _floodPointSourceId = 'fg-flood-point-source';
  static const _floodPointLayerId = 'fg-flood-point-layer';
  static const _floodLabelLayerId = 'fg-flood-label-layer';
  static const _hazardSourceId = 'fg-hazard-report-source';
  static const _hazardHaloLayerId = 'fg-hazard-report-halo-layer';
  static const _hazardLayerId = 'fg-hazard-report-layer';
  static const _hazardLabelLayerId = 'fg-hazard-label-layer';
  static const _facilitySourceId = 'fg-facility-source';
  static const _facilityHaloLayerId = 'fg-facility-halo-layer';
  static const _facilityLayerId = 'fg-facility-layer';
  static const _facilityLabelLayerId = 'fg-facility-label-layer';
  static const _markerIconSourceId = 'fg-marker-icon-source';
  static const _markerIconLayerId = 'fg-marker-icon-layer';

  final _locationService = DeviceLocationService();
  final _hazardMapService = HazardMapService();
  final _sheetController = DraggableScrollableController();

  ml.MapLibreMapController? _mapController;
  ml.LatLng _mapCenter = _baliwag;
  ml.LatLng _assessmentPoint = _baliwag;
  String _locationLabel = 'Baliwag, Bulacan';
  DateTime? _locationUpdatedAt;
  HazardMapData? _mapData;
  String? _mapDataError;
  bool _isRefreshing = false;
  bool _isLoadingMapData = true;
  bool _showFloodHazard = true;
  bool _showHazards = true;
  bool _showFacilities = true;
  bool _styleReady = false;
  bool _layersInstalled = false;
  bool _isSheetExpanded = false;
  bool _layerControlsExpanded = false;
  bool _markerImagesInstalled = false;
  bool _didFocusInitialReport = false;

  bool get _isFacilityMode =>
      widget.initialMode == HazardMapInitialMode.facilities;

  @override
  void initState() {
    super.initState();
    if (_isFacilityMode) {
      _showFloodHazard = false;
      _showHazards = false;
      _showFacilities = true;
      _isSheetExpanded = true;
    }
    _restoreSavedLocation();
    _loadHazardMapData();
  }

  @override
  void dispose() {
    _mapController?.onFeatureTapped.remove(_handleFeatureTap);
    _sheetController.dispose();
    super.dispose();
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
      if (!await _focusInitialReport()) {
        if (_isFacilityMode) await _focusNearestFacility(showMessage: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mapDataError = 'Hazards are unavailable. The map is still usable.';
      });
    } finally {
      if (mounted) setState(() => _isLoadingMapData = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadHazardMapData();
  }

  Future<bool> _focusInitialReport() async {
    final focusReportId = widget.focusReportId;
    if (_didFocusInitialReport ||
        focusReportId == null ||
        focusReportId.isEmpty ||
        _mapData == null) {
      return false;
    }

    final mapped = _mapData!.reports.where((item) {
      return item.report.id == focusReportId;
    }).toList();
    if (mapped.isEmpty) return false;

    _didFocusInitialReport = true;
    final item = mapped.first;
    final point = _latLng(item.coordinate);
    await _moveCamera(point, zoom: 16.4);
    if (!mounted) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return true;
    _showFeatureDetails(
      item.report.type == HazardType.floodedRoad
          ? _floodProperties(item)
          : _hazardProperties(item),
    );
    return true;
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
    final nearbyFeature = _featureNear(coordinate);
    if (nearbyFeature != null) {
      _showFeatureDetails(nearbyFeature);
      return;
    }
  }

  Future<Map<dynamic, dynamic>?> _featureAt(math.Point<double> point) async {
    final controller = _mapController;
    if (controller == null || !_layersInstalled) return null;
    try {
      const hitSlop = 32.0;
      final features = await controller.queryRenderedFeaturesInRect(
        Rect.fromLTRB(
          point.x - hitSlop,
          point.y - hitSlop,
          point.x + hitSlop,
          point.y + hitSlop,
        ),
        [
          _markerIconLayerId,
          _facilityLayerId,
          _hazardLayerId,
          _floodPointLayerId,
          _floodLayerId,
        ],
        null,
      );
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

  Map<String, dynamic>? _featureNear(ml.LatLng coordinate) {
    const hitRadiusMeters = 90.0;

    Map<String, dynamic>? nearest;
    var nearestDistance = double.infinity;

    void consider(ml.LatLng point, Map<String, dynamic> properties) {
      final distance = _distanceMeters(coordinate, point);
      if (distance <= hitRadiusMeters && distance < nearestDistance) {
        nearest = properties;
        nearestDistance = distance;
      }
    }

    if (_showFloodHazard) {
      for (final item in _floodReports) {
        consider(_latLng(item.coordinate), _floodProperties(item));
      }
    }
    if (_showHazards) {
      for (final item in _hazardReports) {
        consider(_latLng(item.coordinate), _hazardProperties(item));
      }
    }
    if (_showFacilities) {
      for (final facility in _facilities) {
        consider(_latLng(facility.coordinate), _facilityProperties(facility));
      }
    }

    return nearest;
  }

  void _handleFeatureTap(
    math.Point<double> point,
    ml.LatLng coordinate,
    String id,
    String layerId,
    ml.Annotation? annotation,
  ) {
    const interactiveLayerIds = {
      _markerIconLayerId,
      _facilityLayerId,
      _hazardLayerId,
      _floodPointLayerId,
      _floodLayerId,
    };
    if (!interactiveLayerIds.contains(layerId)) return;

    final properties = _propertiesByFeatureId(id);
    if (properties != null) {
      _showFeatureDetails(properties);
    }
  }

  Future<void> _focusFacility(
    EmergencyFacility facility, {
    bool showMessage = true,
  }) async {
    final point = _latLng(facility.coordinate);
    setState(() {
      _showFacilities = true;
      _mapCenter = point;
    });
    await _moveCamera(point, zoom: 16.3);
    await _updateMapSources();
    if (mounted && showMessage) {
      _message('Showing ${facility.name} on the map.');
    }
  }

  Future<void> _focusNearestFacility({bool showMessage = true}) async {
    final facilities = _nearbyFacilities;
    if (facilities.isEmpty) return;
    final facility = facilities.first;
    final point = _latLng(facility.coordinate);
    setState(() {
      _showFacilities = true;
      _mapCenter = point;
    });
    await _moveCamera(point, zoom: 15.8);
    await _updateMapSources();
    if (mounted && showMessage) {
      _message('Showing nearest safety facility.');
    }
  }

  Future<void> _navigateToFacility(EmergencyFacility facility) async {
    final coordinate = facility.coordinate;
    final label = Uri.encodeComponent(facility.name);
    final geoUri = Uri.parse(
      'geo:${coordinate.latitude},${coordinate.longitude}'
      '?q=${coordinate.latitude},${coordinate.longitude}($label)',
    );
    final mapsUri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${coordinate.latitude},${coordinate.longitude}',
    });

    if (await launchUrl(geoUri)) return;
    if (await launchUrl(mapsUri, mode: LaunchMode.externalApplication)) return;
    if (mounted) _message('Map directions are not available on this device.');
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
    await controller.addGeoJsonSource(_floodPointSourceId, _emptyCollection());
    await controller.addGeoJsonSource(_assessmentSourceId, _emptyCollection());
    await controller.addGeoJsonSource(_hazardSourceId, _emptyCollection());
    await controller.addGeoJsonSource(_facilitySourceId, _emptyCollection());
    await controller.addGeoJsonSource(_markerIconSourceId, _emptyCollection());
    await _installMarkerImages(controller);

    await controller.addFillLayer(
      _floodSourceId,
      _floodLayerId,
      const ml.FillLayerProperties(
        fillColor: ['get', 'color'],
        fillOpacity: ['get', 'fillOpacity'],
        fillOutlineColor: ['get', 'stroke'],
      ),
    );
    await controller.addCircleLayer(
      _floodPointSourceId,
      _floodPointLayerId,
      const ml.CircleLayerProperties(
        circleRadius: ['get', 'radius'],
        circleColor: ['get', 'color'],
        circleOpacity: ['get', 'opacity'],
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 3,
      ),
    );
    await controller.addSymbolLayer(
      _floodPointSourceId,
      _floodLabelLayerId,
      const ml.SymbolLayerProperties(
        textField: ['get', 'code'],
        textSize: 12,
        textColor: '#0F172A',
        textHaloColor: '#FFFFFF',
        textHaloWidth: 1.3,
        textAllowOverlap: false,
      ),
      minzoom: 13,
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
      _hazardHaloLayerId,
      const ml.CircleLayerProperties(
        circleRadius: ['get', 'haloRadius'],
        circleColor: ['get', 'color'],
        circleOpacity: ['get', 'haloOpacity'],
        circleStrokeColor: '#FFFFFF',
        circleStrokeOpacity: .8,
        circleStrokeWidth: 2,
      ),
    );
    await controller.addCircleLayer(
      _hazardSourceId,
      _hazardLayerId,
      const ml.CircleLayerProperties(
        circleRadius: ['get', 'radius'],
        circleColor: ['get', 'color'],
        circleOpacity: ['get', 'opacity'],
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 5,
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
      _facilityHaloLayerId,
      const ml.CircleLayerProperties(
        circleRadius: ['get', 'haloRadius'],
        circleColor: ['get', 'color'],
        circleOpacity: .26,
        circleStrokeColor: '#0F172A',
        circleStrokeOpacity: .25,
        circleStrokeWidth: 2,
      ),
    );
    await controller.addCircleLayer(
      _facilitySourceId,
      _facilityLayerId,
      const ml.CircleLayerProperties(
        circleRadius: ['get', 'radius'],
        circleColor: ['get', 'color'],
        circleOpacity: .96,
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 5,
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
    await controller.addSymbolLayer(
      _markerIconSourceId,
      _markerIconLayerId,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'markerIcon'],
        iconSize: .82,
        iconOpacity: ['get', 'opacity'],
        iconAnchor: 'center',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );

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
        _floodPointSourceId,
        _showFloodHazard ? _floodPointGeoJson() : _emptyCollection(),
      );
      await controller.setGeoJsonSource(
        _hazardSourceId,
        _showHazards ? _hazardReportsGeoJson() : _emptyCollection(),
      );
      await controller.setGeoJsonSource(
        _facilitySourceId,
        _showFacilities ? _facilitiesGeoJson() : _emptyCollection(),
      );
      await controller.setGeoJsonSource(
        _markerIconSourceId,
        _markerIconGeoJson(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mapDataError = 'Map layers could not refresh. Try again.';
      });
    }
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

  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: const AppBottomNav(index: 0),
    body: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: ClipRect(child: _mapView())),
          _topBar(context),
          _mapQuickActions(),
          if (_isLoadingMapData || _mapDataError != null) _mapStateChip(),
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
    translucentTextureSurface: true,
    annotationOrder: const [
      ml.AnnotationType.fill,
      ml.AnnotationType.line,
      ml.AnnotationType.circle,
      ml.AnnotationType.symbol,
    ],
    annotationConsumeTapEvents: const [ml.AnnotationType.fill],
    attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
    onMapCreated: (controller) async {
      _mapController = controller;
      controller.onFeatureTapped.add(_handleFeatureTap);
      await _moveCamera(_assessmentPoint, zoom: 15.4);
    },
    onStyleLoadedCallback: () {
      _styleReady = true;
      _layersInstalled = false;
      _markerImagesInstalled = false;
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
        Expanded(
          child: Text(
            _isFacilityMode ? 'Evacuation Centers' : 'Hazard Map',
            style: const TextStyle(
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
        _LayerMenuButton(
          expanded: _layerControlsExpanded,
          onPressed: () =>
              setState(() => _layerControlsExpanded = !_layerControlsExpanded),
        ),
        if (_layerControlsExpanded) ...[
          const SizedBox(height: 8),
          _MapActionButton(
            label: 'Locate',
            icon: Icons.my_location,
            selected: false,
            onPressed: _isRefreshing ? null : _useMyLocation,
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

  Widget _bottomSheet(BuildContext context) =>
      NotificationListener<DraggableScrollableNotification>(
        onNotification: (notification) {
          final expanded = notification.extent > .32;
          if (expanded != _isSheetExpanded) {
            setState(() => _isSheetExpanded = expanded);
          }
          return false;
        },
        child: DraggableScrollableSheet(
          controller: _sheetController,
          initialChildSize: _isFacilityMode ? .34 : .18,
          minChildSize: _isFacilityMode ? .22 : .16,
          maxChildSize: _isFacilityMode ? .68 : .58,
          snap: true,
          snapSizes: _isFacilityMode
              ? const [.22, .42, .68]
              : const [.16, .36, .58],
          builder: (context, scrollController) => Material(
            color: const Color(0xFFF8FBFF),
            elevation: 12,
            shadowColor: const Color(0x26000000),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleSheet,
                  child: Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5DEEC),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
                _statusHeaderCard(compact: !_isSheetExpanded),
                if (_isSheetExpanded) ...[
                  const SizedBox(height: 10),
                  if (_isFacilityMode) ...[
                    _facilitiesSection(context),
                    const SizedBox(height: 12),
                    const _EmergencyHelpCard(),
                    const SizedBox(height: 8),
                    _facilityLayerNote(),
                  ] else ...[
                    const _EmergencyHelpCard(),
                    const SizedBox(height: 10),
                    const _HazardLegend(),
                    const SizedBox(height: 10),
                    _facilitySummaryCard(),
                    const SizedBox(height: 14),
                    _floodReportsSection(context),
                    const SizedBox(height: 14),
                    _nearbyHazardsSection(context),
                    const SizedBox(height: 14),
                    _facilitiesSection(context),
                    const SizedBox(height: 8),
                    _layerNote(),
                  ],
                ],
              ],
            ),
          ),
        ),
      );

  Future<void> _toggleSheet() async {
    final target = _isSheetExpanded
        ? (_isFacilityMode ? .22 : .16)
        : (_isFacilityMode ? .68 : .58);
    setState(() => _isSheetExpanded = !_isSheetExpanded);
    await _sheetController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _expandSheet() async {
    setState(() => _isSheetExpanded = true);
    await _sheetController.animateTo(
      _isFacilityMode ? .68 : .58,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _statusHeaderCard({required bool compact}) {
    if (_isFacilityMode) return _evacuationHeaderCard(compact: compact);

    final level = _reportedFloodLevel;
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
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _reportCountsLabel,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (_hasDemoData && !compact) const _DemoBadge(),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    _reportStatusSummary,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _dataFreshnessLabel,
                style: const TextStyle(
                  color: Color(0xFF166534),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              if (compact)
                TextButton(
                  onPressed: _expandSheet,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Details'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _evacuationHeaderCard({required bool compact}) {
    final facilities = _nearbyFacilities;
    final nearest = facilities.isEmpty
        ? null
        : _distanceLabel(facilities.first);
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
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFFE8F8ED),
            child: Icon(Icons.home_work_outlined, color: Color(0xFF16A34A)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nearby Evacuation Centers',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  _locationLabel,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  facilities.isEmpty
                      ? 'No mapped safety facilities are available.'
                      : '${facilities.length} mapped safety facilities${nearest == null ? '' : ', nearest $nearest away'}.',
                  style: const TextStyle(fontSize: 13),
                ),
                if (_hasDemoData && !compact) ...[
                  const SizedBox(height: 6),
                  const _DemoBadge(),
                ],
              ],
            ),
          ),
          if (compact)
            TextButton(
              onPressed: _expandSheet,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Details'),
            ),
        ],
      ),
    );
  }

  Widget _layerNote() {
    final floods = _floodReports.length;
    final hazards = _hazardReports.length;
    final unmapped = _mapData?.unmappedReportCount ?? 0;
    return Text(
      'Current layers show community reports: $floods flood, '
      '$hazards drainage/waterway hazard${unmapped > 0 ? ', $unmapped without coordinates' : ''}.',
      style: const TextStyle(color: Color(0xFF5B6677), fontSize: 12),
    );
  }

  Widget _facilitySummaryCard() {
    final facilities = _facilities;
    final floods = _floodReports.length;
    final hazards = _hazardReports.length;
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
              '$floods flood reports, $hazards community hazards, ${facilities.length} safety facilities',
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
              _floodReportsSection(sheetContext),
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

  Widget _floodReportsSection(BuildContext context) {
    final reports = _floodReports;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Flooded Locations',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (reports.isEmpty)
          const _EmptyLayerCard(
            icon: Icons.flood_outlined,
            title: 'No mapped flooded-road reports',
            detail:
                'Flood locations appear here when reports have coordinates.',
          )
        else
          ...reports
              .take(4)
              .map(
                (item) => _HazardReportCard(
                  item,
                  titlePrefix: 'Flood',
                  onTap: () {
                    _moveCamera(_latLng(item.coordinate), zoom: 16.2);
                    _showFeatureDetails(_floodProperties(item));
                  },
                ),
              ),
      ],
    );
  }

  Widget _nearbyHazardsSection(BuildContext context) {
    final reports = _hazardReports;
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
    final facilities = _nearbyFacilities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _isFacilityMode ? 'Nearby Evacuation Centers' : 'Critical Facilities',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (facilities.isEmpty)
          const _EmptyLayerCard(
            icon: Icons.home_work_outlined,
            title: 'No mapped safety facilities',
            detail:
                'Facilities appear here once evacuation or safety sites are available.',
          )
        else
          ...facilities.map(
            (facility) => _FacilityCard(
              facility,
              distanceLabel: _distanceLabel(facility),
              onTap: () async {
                await _focusFacility(facility, showMessage: false);
                if (mounted) _showFeatureDetails(_facilityProperties(facility));
              },
              onNavigate: () => _navigateToFacility(facility),
            ),
          ),
      ],
    );
  }

  Widget _facilityLayerNote() {
    return Text(
      'Facility layer uses safety facility data and community reports. Verify opening status with the LGU before emergency travel.',
      style: const TextStyle(color: Color(0xFF5B6677), fontSize: 12),
    );
  }

  Map<String, dynamic> _floodGeoJson() {
    return _featureCollection(
      _floodReports.map((item) {
        final report = item.report;
        return _circlePolygonFeature(
          id: 'flood-${report.id}',
          center: _latLng(item.coordinate),
          radiusMeters: _floodRadiusMeters(report.severity),
          properties: _floodProperties(item),
        );
      }).toList(),
    );
  }

  Map<String, dynamic> _floodPointGeoJson() {
    return _featureCollection(
      _floodReports.map((item) {
        final properties = _floodProperties(item);
        return _pointFeature(_latLng(item.coordinate), {
          ...properties,
          'radius': _severityRadius(item.report.severity) + 2,
        });
      }).toList(),
    );
  }

  Map<String, dynamic> _hazardReportsGeoJson() {
    return _featureCollection(
      _hazardReports.map((item) {
        final point = _latLng(item.coordinate);
        return _pointFeature(point, _hazardProperties(item));
      }).toList(),
    );
  }

  Map<String, dynamic> _facilitiesGeoJson() {
    final facilities = _facilities;
    return _featureCollection(
      facilities.map((facility) {
        final point = _latLng(facility.coordinate);
        return _pointFeature(point, _facilityProperties(facility));
      }).toList(),
    );
  }

  Map<String, dynamic>? _propertiesByFeatureId(String id) {
    for (final item in _floodReports) {
      if ('flood-${item.report.id}' == id) return _floodProperties(item);
    }
    for (final item in _hazardReports) {
      if ('hazard-${item.report.id}' == id) return _hazardProperties(item);
    }
    for (final facility in _facilities) {
      if (facility.id == id) return _facilityProperties(facility);
    }
    return null;
  }

  Map<String, dynamic> _markerIconGeoJson() {
    final features = <Map<String, dynamic>>[];

    if (_showFloodHazard) {
      for (final item in _floodReports) {
        features.add(
          _pointFeature(_latLng(item.coordinate), {
            ..._floodProperties(item),
            'markerIcon': _floodMarkerImage(item.report.severity),
          }),
        );
      }
    }
    if (_showHazards) {
      for (final item in _hazardReports) {
        features.add(
          _pointFeature(_latLng(item.coordinate), {
            ..._hazardProperties(item),
            'markerIcon': _hazardMarkerImage(item.report.type),
          }),
        );
      }
    }
    if (_showFacilities) {
      for (final facility in _facilities) {
        features.add(
          _pointFeature(_latLng(facility.coordinate), {
            ..._facilityProperties(facility),
            'markerIcon': _facilityMarkerImage(facility.type),
          }),
        );
      }
    }

    return _featureCollection(features);
  }

  Map<String, dynamic> _hazardProperties(MappedHazardReport item) {
    final report = item.report;
    final isDemo = _isDemoReport(item);
    return {
      'kind': 'hazard',
      'id': 'hazard-${report.id}',
      'title': isDemo
          ? 'DEMO ${hazardTypeLabel(report.type)}'
          : report.displayType,
      'severity': report.severity,
      'location': report.location,
      'description': report.description.isEmpty
          ? 'No description provided.'
          : report.description,
      'time': _formatDateTime(report.createdAt),
      'status': isDemo
          ? 'DEMO DATA - not a real report'
          : '${hazardReportStatusLabel(report.status)} Community Report',
      'verificationState': hazardVerificationStateLabel(
        report.verificationState,
      ),
      'confidenceScore': report.confidenceScore,
      'verificationReason': report.verificationReason,
      'isDemo': isDemo,
      'photoUrl': report.photoUrl,
      'source': report.source,
      'color': _hazardHexColor(item),
      'opacity': report.isPending ? .62 : .96,
      'haloOpacity': report.isPending ? .14 : .28,
      'radius': _hazardRadius(report.severity),
      'haloRadius': _hazardRadius(report.severity) + 9,
      'code': _hazardCode(report.type),
    };
  }

  Map<String, dynamic> _floodProperties(MappedHazardReport item) {
    final report = item.report;
    final color = _severityColor(report.severity);
    final isDemo = _isDemoReport(item);
    return {
      'kind': 'flood',
      'id': 'flood-${report.id}',
      'title': isDemo ? 'DEMO Flooded Road' : 'Flooded Road',
      'severity': report.severity,
      'location': report.location,
      'description': report.description.isEmpty
          ? 'No description provided.'
          : report.description,
      'time': _formatDateTime(report.createdAt),
      'status': isDemo
          ? 'DEMO DATA - not a real flood report'
          : '${hazardReportStatusLabel(report.status)} Community Report',
      'verificationState': hazardVerificationStateLabel(
        report.verificationState,
      ),
      'confidenceScore': report.confidenceScore,
      'verificationReason': report.verificationReason,
      'isDemo': isDemo,
      'photoUrl': report.photoUrl,
      'source': report.source,
      'color': _hex(color),
      'stroke': _hex(color.withValues(alpha: .9)),
      'opacity': report.isPending ? .68 : 1,
      'fillOpacity': report.isPending ? .11 : .24,
      'code': 'F',
    };
  }

  Map<String, dynamic> _facilityProperties(EmergencyFacility facility) => {
    'kind': 'facility',
    'id': facility.id,
    'title': facility.name,
    'severity': emergencyFacilityTypeLabel(facility.type),
    'location': facility.address,
    'latitude': facility.coordinate.latitude,
    'longitude': facility.coordinate.longitude,
    'description': _isDemoFacility(facility)
        ? 'TEST FACILITY - development marker only.'
        : facility.recommended
        ? 'Recommended reference site. Verify opening status with the LGU.'
        : 'Reference facility. Verify status before emergency use.',
    'time': _isDemoFacility(facility) ? 'Demo facility' : 'Reference facility',
    'status': _isDemoFacility(facility)
        ? 'DEMO DATA - not an official facility'
        : facility.recommended
        ? 'Recommended'
        : 'Reference',
    'isDemo': _isDemoFacility(facility),
    'color': _facilityHexColor(facility),
    'opacity': 1,
    'radius': _facilityRadius(facility),
    'haloRadius': _facilityRadius(facility) + 9,
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
    required String id,
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
      'id': id,
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: .55,
        minChildSize: .30,
        maxChildSize: .90,
        expand: false,
        builder: (context, scrollController) => _FeatureDetailsSheet(
          properties: properties,
          scrollController: scrollController,
        ),
      ),
    );
  }

  List<MappedHazardReport> get _mappedReports => [
    ...?_mapData?.reports,
    if (useDemoFloodData) ...DemoMapData.floodReports,
    if (useDemoHazardData) ...DemoMapData.hazardReports,
  ];

  List<MappedHazardReport> get _floodReports => _mappedReports
      .where((item) => item.report.type == HazardType.floodedRoad)
      .toList();

  List<MappedHazardReport> get _hazardReports => _mappedReports
      .where((item) => item.report.type != HazardType.floodedRoad)
      .toList();

  List<EmergencyFacility> get _facilities => [
    ...?_mapData?.facilities,
    if (useDemoFacilityData) ...DemoMapData.facilities,
  ];

  List<EmergencyFacility> get _nearbyFacilities {
    final facilities = [..._facilities];
    facilities.sort((a, b) {
      final aDistance = _distanceMeters(
        _assessmentPoint,
        _latLng(a.coordinate),
      );
      final bDistance = _distanceMeters(
        _assessmentPoint,
        _latLng(b.coordinate),
      );
      return aDistance.compareTo(bDistance);
    });
    return facilities;
  }

  bool get _hasDemoData =>
      useDemoFloodData || useDemoHazardData || useDemoFacilityData;

  String get _reportCountsLabel =>
      '${_floodReports.length} floods - ${_hazardReports.length} hazards - ${_facilities.length} facilities';

  bool _isDemoReport(MappedHazardReport item) =>
      item.report.id.startsWith('demo-');

  bool _isDemoFacility(EmergencyFacility facility) =>
      facility.id.startsWith('demo-');

  String get _reportedFloodLevel {
    final reports = _floodReports
        .where((item) => _isDemoReport(item) || item.report.contributesToRisk)
        .toList();
    if (reports.isEmpty) return 'Minimal';
    if (reports.any((item) => item.report.severity == 'Critical')) {
      return 'Critical';
    }
    if (reports.any((item) => item.report.severity == 'High')) return 'High';
    if (reports.any((item) => item.report.severity == 'Moderate')) {
      return 'Moderate';
    }
    return 'Low';
  }

  String get _reportStatusSummary {
    final floods = _floodReports.length;
    final hazards = _hazardReports.length;
    final supportedFloods = _floodReports
        .where((item) => _isDemoReport(item) || item.report.contributesToRisk)
        .length;
    if (floods == 0 && hazards == 0) {
      return 'No mapped flood or drainage hazard reports are currently available nearby.';
    }
    if (floods == 0) {
      return 'Based on current reports: $hazards drainage or waterway hazard${hazards == 1 ? '' : 's'} mapped nearby.';
    }
    if (supportedFloods == 0) {
      return 'Community flood reports are visible for awareness, but none are high-confidence or verified yet.';
    }
    return 'Based on current reports: $floods flooded-road report${floods == 1 ? '' : 's'} and $hazards related hazard${hazards == 1 ? '' : 's'} mapped nearby.';
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

  String get _dataFreshnessLabel =>
      _hasDemoData ? 'DEMO' : _locationUpdatedLabel;

  String _distanceLabel(EmergencyFacility facility) {
    final meters = _distanceMeters(
      _assessmentPoint,
      _latLng(facility.coordinate),
    );
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  double _floodRadiusMeters(String severity) => switch (severity) {
    'Critical' => 180,
    'High' => 150,
    'Moderate' => 120,
    'Low' => 90,
    _ => 100,
  };

  Color _riskColor(String level) => switch (level) {
    'Critical' => const Color(0xFF991B1B),
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

  double _hazardRadius(String severity) => switch (severity) {
    'Critical' => 23,
    'High' => 22,
    'Moderate' => 21,
    'Low' => 20,
    _ => 20,
  };

  double _facilityRadius(EmergencyFacility facility) =>
      facility.recommended ? 22 : 21;

  String _hazardHexColor(MappedHazardReport item) {
    if (_isDemoReport(item)) {
      return switch (item.report.type) {
        HazardType.cloggedDrainage => '#F97316',
        HazardType.blockedWaterway => '#7C3AED',
        HazardType.overflowingCanal => '#EA580C',
        HazardType.roadObstruction => '#B45309',
        HazardType.damagedDrainage => '#475569',
        HazardType.other => '#64748B',
        HazardType.floodedRoad => _hex(_severityColor(item.report.severity)),
      };
    }
    return _hex(_severityColor(item.report.severity));
  }

  String _facilityHexColor(EmergencyFacility facility) {
    if (_isDemoFacility(facility)) {
      return switch (facility.type) {
        EmergencyFacilityType.hospital => '#0EA5E9',
        EmergencyFacilityType.fireStation => '#0891B2',
        EmergencyFacilityType.evacuation => '#059669',
        EmergencyFacilityType.school => '#10B981',
      };
    }
    if (facility.recommended) return '#16A34A';
    return switch (facility.type) {
      EmergencyFacilityType.hospital => '#DC2626',
      EmergencyFacilityType.fireStation => '#F97316',
      EmergencyFacilityType.evacuation => '#16A34A',
      EmergencyFacilityType.school => '#2563EB',
    };
  }

  Future<void> _installMarkerImages(ml.MapLibreMapController controller) async {
    if (_markerImagesInstalled) return;

    final markerSpecs = <_MarkerImageSpec>[
      for (final severity in const ['Low', 'Moderate', 'High', 'Critical'])
        _MarkerImageSpec(
          name: _floodMarkerImage(severity),
          icon: Icons.flood_outlined,
          color: _severityColor(severity),
        ),
      _MarkerImageSpec(
        name: _hazardMarkerImage(HazardType.cloggedDrainage),
        icon: Icons.water_damage_outlined,
        color: const Color(0xFFF97316),
      ),
      _MarkerImageSpec(
        name: _hazardMarkerImage(HazardType.blockedWaterway),
        icon: Icons.waves_outlined,
        color: const Color(0xFF7C3AED),
      ),
      _MarkerImageSpec(
        name: _hazardMarkerImage(HazardType.overflowingCanal),
        icon: Icons.warning_amber_outlined,
        color: const Color(0xFFEA580C),
      ),
      _MarkerImageSpec(
        name: _hazardMarkerImage(HazardType.roadObstruction),
        icon: Icons.traffic_outlined,
        color: const Color(0xFFB45309),
      ),
      _MarkerImageSpec(
        name: _hazardMarkerImage(HazardType.damagedDrainage),
        icon: Icons.construction_outlined,
        color: const Color(0xFF475569),
      ),
      _MarkerImageSpec(
        name: _hazardMarkerImage(HazardType.other),
        icon: Icons.report_problem_outlined,
        color: const Color(0xFF64748B),
      ),
      _MarkerImageSpec(
        name: _facilityMarkerImage(EmergencyFacilityType.evacuation),
        icon: Icons.home_work_outlined,
        color: const Color(0xFF059669),
      ),
      _MarkerImageSpec(
        name: _facilityMarkerImage(EmergencyFacilityType.school),
        icon: Icons.school_outlined,
        color: const Color(0xFF10B981),
      ),
      _MarkerImageSpec(
        name: _facilityMarkerImage(EmergencyFacilityType.hospital),
        icon: Icons.local_hospital_outlined,
        color: const Color(0xFF0EA5E9),
      ),
      _MarkerImageSpec(
        name: _facilityMarkerImage(EmergencyFacilityType.fireStation),
        icon: Icons.local_fire_department_outlined,
        color: const Color(0xFF0891B2),
      ),
    ];

    for (final spec in markerSpecs) {
      await controller.addImage(
        spec.name,
        await _markerImageBytes(spec.icon, spec.color),
      );
    }
    _markerImagesInstalled = true;
  }

  Future<Uint8List> _markerImageBytes(IconData icon, Color color) async {
    const size = 72.0;
    const center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      center,
      31,
      Paint()..color = Colors.white.withValues(alpha: .96),
    );
    canvas.drawCircle(
      center,
      27,
      Paint()..color = color.withValues(alpha: .92),
    );
    canvas.drawCircle(
      center,
      27,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
          fontSize: 30,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );

    final image = await recorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  String _floodMarkerImage(String severity) =>
      'fg-marker-flood-${severity.toLowerCase()}';

  String _hazardMarkerImage(HazardType type) => switch (type) {
    HazardType.floodedRoad => _floodMarkerImage('Low'),
    HazardType.cloggedDrainage => 'fg-marker-hazard-drainage',
    HazardType.blockedWaterway => 'fg-marker-hazard-waterway',
    HazardType.overflowingCanal => 'fg-marker-hazard-warning',
    HazardType.roadObstruction => 'fg-marker-hazard-obstruction',
    HazardType.damagedDrainage => 'fg-marker-hazard-damaged-drainage',
    HazardType.other => 'fg-marker-hazard-other',
  };

  String _facilityMarkerImage(EmergencyFacilityType type) => switch (type) {
    EmergencyFacilityType.evacuation => 'fg-marker-facility-evacuation',
    EmergencyFacilityType.school => 'fg-marker-facility-school',
    EmergencyFacilityType.hospital => 'fg-marker-facility-hospital',
    EmergencyFacilityType.fireStation => 'fg-marker-facility-fire',
  };

  String _hazardCode(HazardType type) => switch (type) {
    HazardType.floodedRoad => 'FR',
    HazardType.cloggedDrainage => 'CD',
    HazardType.blockedWaterway => 'BW',
    HazardType.overflowingCanal => 'OC',
    HazardType.roadObstruction => 'RO',
    HazardType.damagedDrainage => 'DD',
    HazardType.other => 'OT',
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

  double _distanceMeters(ml.LatLng a, ml.LatLng b) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _radians(b.latitude - a.latitude);
    final dLng = _radians(b.longitude - a.longitude);
    final lat1 = _radians(a.latitude);
    final lat2 = _radians(b.latitude);
    final value =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadiusMeters *
        2 *
        math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

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

class _MarkerImageSpec {
  const _MarkerImageSpec({
    required this.name,
    required this.icon,
    required this.color,
  });

  final String name;
  final IconData icon;
  final Color color;
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

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: const Color(0xFFF97316)),
    ),
    child: const Text(
      'Demo map markers enabled',
      style: TextStyle(
        color: Color(0xFFC2410C),
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _LayerMenuButton extends StatelessWidget {
  const _LayerMenuButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: expanded ? 'Collapse map controls' : 'Map controls',
    child: Material(
      color: expanded ? AppTheme.blue : Colors.white,
      elevation: 3,
      shadowColor: const Color(0x26000000),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            expanded ? Icons.close : Icons.layers_outlined,
            color: expanded ? Colors.white : AppTheme.navy,
          ),
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

class _HazardReportCard extends StatelessWidget {
  const _HazardReportCard(this.item, {required this.onTap, this.titlePrefix});

  final MappedHazardReport item;
  final VoidCallback onTap;
  final String? titlePrefix;

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
        titlePrefix == null
            ? hazardTypeLabel(item.report.type)
            : '$titlePrefix: ${hazardTypeLabel(item.report.type)}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_isDemo ? 'DEMO DATA - ' : ''}${item.report.location}\n${item.report.severity} severity',
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.info_outline),
      onTap: onTap,
    ),
  );

  bool get _isDemo => item.report.id.startsWith('demo-');

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
    HazardType.roadObstruction => Icons.traffic_outlined,
    HazardType.damagedDrainage => Icons.construction_outlined,
    HazardType.other => Icons.report_problem_outlined,
  };
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard(
    this.facility, {
    required this.distanceLabel,
    required this.onTap,
    required this.onNavigate,
  });

  final EmergencyFacility facility;
  final String distanceLabel;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

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
      subtitle: Text(
        '${_isDemo ? 'TEST FACILITY - ' : ''}${facility.address}\n$distanceLabel away - ${_detail(facility)}',
      ),
      isThreeLine: true,
      trailing: TextButton.icon(
        onPressed: onNavigate,
        icon: const Icon(Icons.directions_outlined, size: 18),
        label: const Text('Navigate'),
      ),
      onTap: onTap,
    ),
  );

  bool get _isDemo => facility.id.startsWith('demo-');

  String _detail(EmergencyFacility facility) {
    if (_isDemo) {
      return 'Development marker only, not an official facility.';
    }
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

class _FeatureDetailsSheet extends StatelessWidget {
  const _FeatureDetailsSheet({
    required this.properties,
    required this.scrollController,
  });

  final Map<String, dynamic> properties;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final title = properties['title']?.toString() ?? 'Map item';
    final severity = properties['severity']?.toString() ?? '';
    final location = properties['location']?.toString() ?? '';
    final description = properties['description']?.toString() ?? '';
    final photoUrl = properties['photoUrl']?.toString() ?? '';
    final time = properties['time']?.toString() ?? '';
    final status = properties['status']?.toString() ?? '';
    final verificationState = properties['verificationState']?.toString() ?? '';
    final confidenceScore = properties['confidenceScore']?.toString() ?? '';
    final verificationReason =
        properties['verificationReason']?.toString() ?? '';
    final isDemo =
        properties['isDemo'] == true || properties['isDemo'] == 'true';
    final isFacility = properties['kind'] == 'facility';
    final kind = properties['kind']?.toString() ?? '';
    final source =
        properties['source']?.toString() ?? 'FloodGuard Community Report';
    final statusBadge = _statusBadgeLabel(status);

    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.muted.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (statusBadge.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _StatusBadge(statusBadge),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (kind.isNotEmpty) _InfoChip(_kindLabel(kind)),
                if (severity.isNotEmpty) _InfoChip(severity),
                if (isDemo) const _DemoBadge(),
              ],
            ),
            const SizedBox(height: 14),
            if (location.isNotEmpty)
              _MetaLine(Icons.location_on_outlined, location),
            if (time.isNotEmpty)
              _MetaLine(Icons.schedule_outlined, 'Reported $time'),
            if (source.isNotEmpty) _MetaLine(Icons.person_outline, source),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              _DetailRow('Description', description),
            ],
            if (photoUrl.isNotEmpty) ...[
              const SizedBox(height: 2),
              const Text(
                'Photo Evidence',
                style: TextStyle(
                  color: AppTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              _EvidencePhoto(photoUrl: photoUrl),
              const SizedBox(height: 12),
            ],
            if (status.isNotEmpty) ...[
              _DetailRow('Verification Status', status),
              if (verificationState.isNotEmpty)
                _DetailRow('Verification Process', verificationState),
              if (confidenceScore.isNotEmpty)
                _DetailRow('Confidence', '$confidenceScore/100'),
              if (verificationReason.isNotEmpty)
                _DetailRow(
                  'Automated Credibility Assessment',
                  verificationReason,
                ),
              if (status.toLowerCase().contains('pending'))
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    'This community report has not yet been verified.',
                    style: TextStyle(color: AppTheme.muted),
                  ),
                ),
            ],
            _DetailRow('Source', source),
            if (isFacility) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openDirections(context),
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Navigate'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _kindLabel(String kind) => switch (kind) {
    'flood' => 'Flood',
    'hazard' => 'Hazard',
    'facility' => 'Facility',
    _ => kind,
  };

  String _statusBadgeLabel(String status) {
    final value = status.toLowerCase();
    if (value.contains('demo')) return 'DEMO';
    if (value.contains('verified')) return 'VERIFIED';
    if (value.contains('resolved')) return 'RESOLVED';
    if (value.contains('pending')) return 'PENDING';
    if (value.contains('recommended')) return 'OPEN';
    if (value.contains('reference')) return 'REFERENCE';
    return status.isEmpty ? '' : status.toUpperCase();
  }

  Future<void> _openDirections(BuildContext context) async {
    final latitude = double.tryParse(properties['latitude']?.toString() ?? '');
    final longitude = double.tryParse(
      properties['longitude']?.toString() ?? '',
    );
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Directions are unavailable.')),
      );
      return;
    }

    final title = Uri.encodeComponent(
      properties['title']?.toString() ?? 'Safety facility',
    );
    final geoUri = Uri.parse(
      'geo:$latitude,$longitude?q=$latitude,$longitude($title)',
    );
    final mapsUri = Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '$latitude,$longitude',
    });

    if (await launchUrl(geoUri)) return;
    if (await launchUrl(mapsUri, mode: LaunchMode.externalApplication)) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Map directions are not available.')),
      );
    }
  }
}

class _EvidencePhoto extends StatelessWidget {
  const _EvidencePhoto({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: photoUrl.startsWith('http')
          ? Image.network(
              photoUrl,
              width: double.infinity,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const _PhotoFallback(label: 'Loading photo...');
              },
              errorBuilder: (context, error, stackTrace) =>
                  const _PhotoFallback(),
            )
          : Image.file(
              File(photoUrl),
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const _PhotoFallback(),
            ),
    ),
  );
}

class _PhotoFallback extends StatelessWidget {
  const _PhotoFallback({this.label = 'Photo unavailable'});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.paleBlue,
    alignment: Alignment.center,
    child: Text(label, style: const TextStyle(color: AppTheme.muted)),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _color.withValues(alpha: .35)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );

  Color get _color {
    final value = label.toLowerCase();
    if (value.contains('verified') || value.contains('open')) {
      return Colors.green;
    }
    if (value.contains('resolved')) return AppTheme.blue;
    if (value.contains('demo') || value.contains('reference')) {
      return Colors.orange;
    }
    return const Color(0xFFB45309);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.paleBlue,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.blue,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.blue),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
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
      shortLabel: 'Emergency',
      number: '911',
      detail: 'Police, fire, rescue, or medical emergency',
    ),
    _EmergencyNumber(
      label: 'Philippine Red Cross',
      shortLabel: 'Red Cross',
      number: '143',
      detail: 'Rescue and disaster assistance',
    ),
    _EmergencyNumber(
      label: 'NDRRMC Operations Center',
      shortLabel: 'NDRRMC',
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
                'Emergency Hotlines',
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
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 118,
                    height: 42,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      onPressed: () => _call(context, item.number),
                      icon: const Icon(Icons.phone, size: 15),
                      label: FittedBox(child: Text(item.displayNumber)),
                    ),
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
    required this.shortLabel,
    required this.number,
    required this.detail,
    String? displayNumber,
  }) : displayNumber = displayNumber ?? number;

  final String label;
  final String shortLabel;
  final String number;
  final String detail;
  final String displayNumber;
}
