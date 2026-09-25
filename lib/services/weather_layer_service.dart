import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

class RadarFrame {
  const RadarFrame({required this.time, required this.path});

  final DateTime time;
  final String path;
}

class RadarTimeline {
  const RadarTimeline({
    required this.host,
    required this.generatedAt,
    required this.frames,
    required this.hasCoverage,
  });

  final String host;
  final DateTime generatedAt;
  final List<RadarFrame> frames;
  final bool hasCoverage;

  bool get isStale =>
      DateTime.now().toUtc().difference(generatedAt) >
      const Duration(minutes: 35);
}

class WeatherLayerService {
  WeatherLayerService({http.Client? client})
    : _client = client ?? http.Client();

  static const sourceId = 'fg-weather-radar-source';
  static const layerId = 'fg-weather-radar-layer';
  static const metadataUrl =
      'https://api.rainviewer.com/public/weather-maps.json';
  static const attribution =
      '<a href="https://www.rainviewer.com/">Weather radar by RainViewer</a>';

  final http.Client _client;
  bool _installed = false;
  String? _installedPath;

  Future<RadarTimeline> loadTimeline({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client
        .get(Uri.parse(metadataUrl))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw RadarException(
        'Radar provider returned HTTP ${response.statusCode}.',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const RadarException('Radar provider returned invalid metadata.');
    }
    final host = decoded['host']?.toString();
    final generated = decoded['generated'];
    final radar = decoded['radar'];
    if (host == null ||
        !host.startsWith('https://') ||
        generated is! num ||
        radar is! Map) {
      throw const RadarException('Radar metadata is incomplete.');
    }
    final past = radar['past'];
    if (past is! List) {
      throw const RadarException('No historical radar frames are available.');
    }
    final frames =
        past
            .whereType<Map>()
            .map((item) {
              final time = item['time'];
              final path = item['path']?.toString();
              if (time is! num ||
                  path == null ||
                  !path.startsWith('/v2/radar/')) {
                return null;
              }
              return RadarFrame(
                time: DateTime.fromMillisecondsSinceEpoch(
                  time.toInt() * 1000,
                  isUtc: true,
                ),
                path: path,
              );
            })
            .whereType<RadarFrame>()
            .toList()
          ..sort((a, b) => a.time.compareTo(b.time));
    if (frames.isEmpty) {
      throw const RadarException(
        'No valid historical radar frames are available.',
      );
    }

    return RadarTimeline(
      host: host,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        generated.toInt() * 1000,
        isUtc: true,
      ),
      frames: frames,
      hasCoverage: await _hasCoverage(
        host: host,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  Future<void> showFrame(
    ml.MapLibreMapController controller, {
    required RadarTimeline timeline,
    required RadarFrame frame,
    required double opacity,
    String? belowLayerId,
  }) async {
    if (!timeline.hasCoverage) {
      throw const RadarException('Radar unavailable for this area.');
    }
    if (_installed && _installedPath == frame.path) {
      await setOpacity(controller, opacity);
      await setVisible(controller, visible: true);
      return;
    }
    if (_installed) {
      await controller.removeLayer(layerId);
      await controller.removeSource(sourceId);
    }
    final tileUrl = '${timeline.host}${frame.path}/256/{z}/{x}/{y}/2/1_1.png';
    await controller.addSource(
      sourceId,
      ml.RasterSourceProperties(
        tiles: [tileUrl],
        tileSize: 256,
        minzoom: 0,
        maxzoom: 7,
        attribution: attribution,
      ),
    );
    await controller.addRasterLayer(
      sourceId,
      layerId,
      ml.RasterLayerProperties(
        rasterOpacity: opacity.clamp(0.1, 1),
        visibility: 'visible',
      ),
      belowLayerId: belowLayerId,
    );
    _installed = true;
    _installedPath = frame.path;
  }

  Future<void> setOpacity(
    ml.MapLibreMapController controller,
    double opacity,
  ) async {
    if (!_installed) return;
    await controller.setLayerProperties(
      layerId,
      ml.RasterLayerProperties(
        rasterOpacity: opacity.clamp(0.1, 1),
        visibility: 'visible',
      ),
    );
  }

  Future<void> setVisible(
    ml.MapLibreMapController controller, {
    required bool visible,
  }) async {
    if (!_installed) return;
    await controller.setLayerProperties(
      layerId,
      ml.RasterLayerProperties(visibility: visible ? 'visible' : 'none'),
    );
  }

  void reset() {
    _installed = false;
    _installedPath = null;
  }

  Future<bool> _hasCoverage({
    required String host,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final uri = Uri.parse(
        '$host/v2/coverage/0/256/7/$latitude/$longitude/0/0_0.png',
      );
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }
      final codec = await ui.instantiateImageCodec(response.bodyBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return false;
      final centerX = image.width ~/ 2;
      final centerY = image.height ~/ 2;
      final alphaOffset = ((centerY * image.width + centerX) * 4) + 3;
      final alpha = bytes.buffer.asUint8List()[alphaOffset];
      image.dispose();
      codec.dispose();
      return alpha < 128;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

class RadarException implements Exception {
  const RadarException(this.message);
  final String message;

  @override
  String toString() => message;
}
