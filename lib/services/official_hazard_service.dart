import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

class OfficialFloodSusceptibility {
  const OfficialFloodSusceptibility({
    required this.code,
    required this.label,
    required this.checkedAt,
  });

  final String code;
  final String label;
  final DateTime checkedAt;

  bool get isElevated => code == 'HF' || code == 'VHF';
}

class OfficialHazardService {
  OfficialHazardService({http.Client? client})
    : _client = client ?? http.Client();

  static const sourceId = 'fg-mgb-flood-susceptibility-source';
  static const layerId = 'fg-mgb-flood-susceptibility-layer';
  static const mapServer =
      'https://controlmap.mgb.gov.ph/arcgis/rest/services/'
      'GeospatialDataInventory_Public/'
      'GDI_Detailed_Flood_Susceptibility_Public/MapServer';
  static const featureLayer =
      'https://controlmap.mgb.gov.ph/arcgis/rest/services/'
      'GeospatialDataInventory/GDI_Detailed_Flood_Susceptibility/'
      'FeatureServer/0';
  static const officialAdvisoryUrl =
      'https://www.pagasa.dost.gov.ph/regional-forecast/ncrprsd';
  static const attribution = 'Flood susceptibility: DENR-MGB';

  final http.Client _client;
  bool _installed = false;

  Future<OfficialFloodSusceptibility?> queryFloodSusceptibility({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse('$featureLayer/query').replace(
      queryParameters: {
        'geometry': '$longitude,$latitude',
        'geometryType': 'esriGeometryPoint',
        'inSR': '4326',
        'spatialRel': 'esriSpatialRelIntersects',
        'outFields': 'FloodSusc',
        'returnGeometry': 'false',
        'f': 'json',
      },
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw OfficialHazardException(
        'MGB service returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const OfficialHazardException('MGB returned invalid JSON.');
    }
    if (decoded['error'] != null) {
      throw const OfficialHazardException(
        'MGB could not assess this location.',
      );
    }
    final features = decoded['features'];
    if (features is! List || features.isEmpty) return null;
    final first = features.first;
    if (first is! Map) return null;
    final attributes = first['attributes'];
    if (attributes is! Map) return null;
    final code = attributes['FloodSusc']?.toString().trim().toUpperCase();
    if (code == null || code.isEmpty) return null;
    return OfficialFloodSusceptibility(
      code: code,
      label: _labelFor(code),
      checkedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> installLayer(
    ml.MapLibreMapController controller, {
    required bool visible,
    String? belowLayerId,
  }) async {
    if (_installed) {
      await setVisible(controller, visible: visible);
      return;
    }
    await controller.addSource(
      sourceId,
      const ml.RasterSourceProperties(
        tiles: ['$mapServer/tile/{z}/{y}/{x}'],
        tileSize: 256,
        minzoom: 6,
        maxzoom: 14,
        attribution: attribution,
      ),
    );
    await controller.addRasterLayer(
      sourceId,
      layerId,
      ml.RasterLayerProperties(
        rasterOpacity: .5,
        visibility: visible ? 'visible' : 'none',
      ),
      belowLayerId: belowLayerId,
    );
    _installed = true;
  }

  Future<void> setVisible(
    ml.MapLibreMapController controller, {
    required bool visible,
  }) async {
    if (!_installed) return;
    await controller.setLayerProperties(
      layerId,
      ml.RasterLayerProperties(
        rasterOpacity: .5,
        visibility: visible ? 'visible' : 'none',
      ),
    );
  }

  void reset() => _installed = false;

  static String _labelFor(String code) => switch (code) {
    'VHF' => 'Very high flood susceptibility',
    'HF' => 'High flood susceptibility',
    'MF' => 'Moderate flood susceptibility',
    'LF' => 'Low flood susceptibility',
    _ => 'Flood susceptibility: $code',
  };
}

class OfficialHazardException implements Exception {
  const OfficialHazardException(this.message);
  final String message;

  @override
  String toString() => message;
}
