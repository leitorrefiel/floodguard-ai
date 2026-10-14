import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main(List<String> arguments) async {
  final latitude = arguments.isNotEmpty
      ? double.tryParse(arguments.first)
      : null;
  final longitude = arguments.length > 1 ? double.tryParse(arguments[1]) : null;
  if (latitude == null || longitude == null) {
    stderr.writeln(
      'Usage: dart run tool/field_provider_check.dart <latitude> <longitude>',
    );
    exitCode = 64;
    return;
  }

  final client = http.Client();
  try {
    stdout.writeln('[Field] requested location: $latitude,$longitude');
    stdout.writeln('[Field] comparison timezone: Asia/Manila (UTC+08:00)');
    final results = await Future.wait([
      _runCheck(
        'Open-Meteo',
        () => _checkOpenMeteo(client, latitude, longitude),
      ),
      _runCheck('RainViewer', () => _checkRainViewer(client)),
      _runCheck('DENR-MGB', () => _checkMgb(client, latitude, longitude)),
    ]);
    if (results.any((passed) => !passed)) exitCode = 1;
  } finally {
    client.close();
  }
}

Future<bool> _runCheck(String source, Future<void> Function() check) async {
  try {
    await check();
    return true;
  } catch (error) {
    stderr.writeln('[$source] unavailable: $error');
    return false;
  }
}

Future<void> _checkOpenMeteo(
  http.Client client,
  double latitude,
  double longitude,
) async {
  final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': latitude.toStringAsFixed(6),
    'longitude': longitude.toStringAsFixed(6),
    'current': 'temperature_2m,precipitation,rain,weather_code',
    'hourly': 'precipitation_probability,precipitation,rain',
    'daily': 'precipitation_sum,precipitation_probability_max',
    'timezone': 'Asia/Manila',
    'forecast_days': '3',
  });
  final response = await client.get(uri).timeout(const Duration(seconds: 15));
  _requireSuccess('Open-Meteo', response);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final current = data['current'] as Map<String, dynamic>?;
  if (data['timezone'] != 'Asia/Manila' || current == null) {
    throw const FormatException('Open-Meteo returned incomplete local data.');
  }
  for (final key in ['time', 'precipitation', 'rain']) {
    if (current[key] == null) {
      throw FormatException('Open-Meteo current.$key is missing.');
    }
  }
  stdout.writeln(
    '[Open-Meteo] model grid=${data['latitude']},${data['longitude']} '
    'valid=${current['time']} precipitation=${current['precipitation']} mm '
    'rain=${current['rain']} mm (MODEL ESTIMATE, NOT A RAIN GAUGE)',
  );
}

Future<void> _checkRainViewer(http.Client client) async {
  final response = await client
      .get(Uri.parse('https://api.rainviewer.com/public/weather-maps.json'))
      .timeout(const Duration(seconds: 15));
  _requireSuccess('RainViewer', response);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  final radar = data['radar'] as Map<String, dynamic>?;
  final past = radar?['past'] as List<dynamic>?;
  if (data['host'] == null ||
      data['generated'] is! num ||
      past == null ||
      past.isEmpty) {
    throw const FormatException('RainViewer returned no historical frames.');
  }
  final latest = past.last as Map<String, dynamic>;
  final generated = DateTime.fromMillisecondsSinceEpoch(
    (data['generated'] as num).toInt() * 1000,
    isUtc: true,
  );
  final frameTime = DateTime.fromMillisecondsSinceEpoch(
    (latest['time'] as num).toInt() * 1000,
    isUtc: true,
  );
  stdout.writeln(
    '[RainViewer] historical_frames=${past.length} '
    'generated=${_formatPht(generated)} '
    'latest_frame=${_formatPht(frameTime)} path=${latest['path']} '
    '(FRAME GENERATION TIME, NOT A GAUGE OBSERVATION)',
  );
}

String _formatPht(DateTime value) {
  final pht = value.toUtc().add(const Duration(hours: 8));
  String two(int number) => number.toString().padLeft(2, '0');
  return '${pht.year}-${two(pht.month)}-${two(pht.day)} '
      '${two(pht.hour)}:${two(pht.minute)}:${two(pht.second)} PHT';
}

Future<void> _checkMgb(
  http.Client client,
  double latitude,
  double longitude,
) async {
  const endpoint =
      'https://controlmap.mgb.gov.ph/arcgis/rest/services/'
      'GeospatialDataInventory/GDI_Detailed_Flood_Susceptibility/'
      'FeatureServer/0/query';
  final uri = Uri.parse(endpoint).replace(
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
  final response = await client.get(uri).timeout(const Duration(seconds: 20));
  _requireSuccess('DENR-MGB', response);
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (data['error'] != null) throw const FormatException('MGB query failed.');
  final features = data['features'] as List<dynamic>? ?? const [];
  final value = features.isEmpty
      ? 'no polygon returned'
      : ((features.first as Map<String, dynamic>)['attributes']
            as Map<String, dynamic>)['FloodSusc'];
  stdout.writeln(
    '[DENR-MGB] flood_susceptibility=$value '
    '(STATIC SUSCEPTIBILITY, NOT A CURRENT FLOOD INCIDENT)',
  );
}

void _requireSuccess(String source, http.Response response) {
  if (response.statusCode != 200) {
    throw HttpException('$source returned HTTP ${response.statusCode}.');
  }
}
