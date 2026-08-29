import 'package:maplibre_gl/maplibre_gl.dart' as ml;

class WeatherLayerService {
  static const sourceId = 'fg-weather-radar-source';
  static const layerId = 'fg-weather-radar-layer';

  // Connect a real radar tile template with:
  // --dart-define=WEATHER_RADAR_TILE_URL=https://provider/{z}/{x}/{y}.png
  static const radarTileUrl = String.fromEnvironment('WEATHER_RADAR_TILE_URL');

  bool _installed = false;

  bool get hasConfiguredRadar => radarTileUrl.trim().isNotEmpty;

  void reset() => _installed = false;

  Future<void> installIfConfigured(ml.MapLibreMapController controller) async {
    if (_installed || !hasConfiguredRadar) return;
    await controller.addSource(
      sourceId,
      const ml.RasterSourceProperties(
        tiles: [radarTileUrl],
        tileSize: 256,
        minzoom: 0,
        maxzoom: 12,
        attribution: 'Weather radar provider',
      ),
    );
    await controller.addRasterLayer(
      sourceId,
      layerId,
      const ml.RasterLayerProperties(rasterOpacity: .62, visibility: 'none'),
    );
    _installed = true;
  }

  Future<void> setVisible(
    ml.MapLibreMapController controller, {
    required bool visible,
  }) async {
    if (!_installed || !hasConfiguredRadar) return;
    await controller.setLayerProperties(
      layerId,
      ml.RasterLayerProperties(
        rasterOpacity: .62,
        visibility: visible ? 'visible' : 'none',
      ),
    );
  }
}
