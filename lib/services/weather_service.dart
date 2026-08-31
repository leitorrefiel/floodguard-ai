import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.precipitationMm,
    required this.rainMm,
    required this.observedAt,
  });

  final double temperatureCelsius;
  final double precipitationMm;
  final double rainMm;
  final String observedAt;
}

class WeatherForecastDay {
  const WeatherForecastDay({
    required this.date,
    required this.weatherCode,
    required this.maxTemperatureCelsius,
    required this.minTemperatureCelsius,
    required this.precipitationMm,
    this.precipitationProbabilityMax,
  });

  final String date;
  final int weatherCode;
  final double maxTemperatureCelsius;
  final double minTemperatureCelsius;
  final double precipitationMm;
  final int? precipitationProbabilityMax;
}

class WeatherForecastHour {
  const WeatherForecastHour({
    required this.time,
    required this.temperatureCelsius,
    required this.precipitationMm,
    required this.rainMm,
    required this.weatherCode,
    this.precipitationProbability,
  });

  final String time;
  final double temperatureCelsius;
  final double precipitationMm;
  final double rainMm;
  final int weatherCode;
  final int? precipitationProbability;
}

class WeatherForecastResponse {
  const WeatherForecastResponse({
    required this.current,
    required this.days,
    this.hours = const [],
    required this.endpoint,
    required this.jsonSample,
  });

  final WeatherSnapshot current;
  final List<WeatherForecastDay> days;
  final List<WeatherForecastHour> hours;
  final Uri endpoint;
  final String jsonSample;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<WeatherSnapshot> getCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,precipitation,rain',
      'timezone': 'auto',
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const WeatherException('Live weather is temporarily unavailable.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;
    if (current == null) {
      throw const WeatherException(
        'Live weather returned no current conditions.',
      );
    }

    return WeatherSnapshot(
      temperatureCelsius: (current['temperature_2m'] as num?)?.toDouble() ?? 0,
      precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
      rainMm: (current['rain'] as num?)?.toDouble() ?? 0,
      observedAt: current['time'] as String? ?? '',
    );
  }

  Future<WeatherForecastResponse> getForecast({
    required double latitude,
    required double longitude,
    int forecastDays = 3,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'current': 'temperature_2m,precipitation,rain,weather_code',
      'hourly':
          'temperature_2m,precipitation,precipitation_probability,rain,weather_code',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': forecastDays.toString(),
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const WeatherException('Forecast data is temporarily unavailable.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>?;
    final daily = data['daily'] as Map<String, dynamic>?;
    final hourly = data['hourly'] as Map<String, dynamic>?;
    if (current == null || daily == null || hourly == null) {
      throw const WeatherException('Forecast returned incomplete data.');
    }

    final dates = (daily['time'] as List<dynamic>?) ?? const [];
    final weatherCodes = (daily['weather_code'] as List<dynamic>?) ?? const [];
    final maxTemps =
        (daily['temperature_2m_max'] as List<dynamic>?) ?? const [];
    final minTemps =
        (daily['temperature_2m_min'] as List<dynamic>?) ?? const [];
    final rainTotals =
        (daily['precipitation_sum'] as List<dynamic>?) ?? const [];
    final rainChances =
        (daily['precipitation_probability_max'] as List<dynamic>?) ?? const [];
    final dayCount = [
      dates.length,
      weatherCodes.length,
      maxTemps.length,
      minTemps.length,
      rainTotals.length,
    ].reduce((value, element) => value < element ? value : element);

    if (dayCount == 0) {
      throw const WeatherException('Forecast returned no daily results.');
    }

    final hourlyTimes = (hourly['time'] as List<dynamic>?) ?? const [];
    final hourlyTemps =
        (hourly['temperature_2m'] as List<dynamic>?) ?? const [];
    final hourlyPrecipitation =
        (hourly['precipitation'] as List<dynamic>?) ?? const [];
    final hourlyRain = (hourly['rain'] as List<dynamic>?) ?? const [];
    final hourlyWeatherCodes =
        (hourly['weather_code'] as List<dynamic>?) ?? const [];
    final hourlyRainChances =
        (hourly['precipitation_probability'] as List<dynamic>?) ?? const [];
    final hourCount = [
      hourlyTimes.length,
      hourlyTemps.length,
      hourlyPrecipitation.length,
      hourlyRain.length,
      hourlyWeatherCodes.length,
    ].reduce((value, element) => value < element ? value : element);
    final now = DateTime.now();
    final upcomingHours =
        List.generate(
              hourCount,
              (index) => WeatherForecastHour(
                time: hourlyTimes[index] as String,
                temperatureCelsius:
                    (hourlyTemps[index] as num?)?.toDouble() ?? 0,
                precipitationMm:
                    (hourlyPrecipitation[index] as num?)?.toDouble() ?? 0,
                rainMm: (hourlyRain[index] as num?)?.toDouble() ?? 0,
                weatherCode: (hourlyWeatherCodes[index] as num?)?.toInt() ?? 0,
                precipitationProbability: index < hourlyRainChances.length
                    ? (hourlyRainChances[index] as num?)?.toInt()
                    : null,
              ),
            )
            .where((hour) {
              final parsed = DateTime.tryParse(hour.time);
              return parsed != null && !parsed.isBefore(now);
            })
            .take(6)
            .toList();

    return WeatherForecastResponse(
      current: WeatherSnapshot(
        temperatureCelsius:
            (current['temperature_2m'] as num?)?.toDouble() ?? 0,
        precipitationMm: (current['precipitation'] as num?)?.toDouble() ?? 0,
        rainMm: (current['rain'] as num?)?.toDouble() ?? 0,
        observedAt: current['time'] as String? ?? '',
      ),
      days: List.generate(
        dayCount,
        (index) => WeatherForecastDay(
          date: dates[index] as String,
          weatherCode: (weatherCodes[index] as num?)?.toInt() ?? 0,
          maxTemperatureCelsius: (maxTemps[index] as num?)?.toDouble() ?? 0,
          minTemperatureCelsius: (minTemps[index] as num?)?.toDouble() ?? 0,
          precipitationMm: (rainTotals[index] as num?)?.toDouble() ?? 0,
          precipitationProbabilityMax: index < rainChances.length
              ? (rainChances[index] as num?)?.toInt()
              : null,
        ),
      ),
      hours: upcomingHours,
      endpoint: uri,
      jsonSample: const JsonEncoder.withIndent('  ').convert({
        'current': data['current'],
        'hourly': {
          'time': hourlyTimes.take(6).toList(),
          'precipitation': hourlyPrecipitation.take(6).toList(),
          'precipitation_probability': hourlyRainChances.take(6).toList(),
          'rain': hourlyRain.take(6).toList(),
          'weather_code': hourlyWeatherCodes.take(6).toList(),
        },
        'daily': {
          'time': dates,
          'weather_code': weatherCodes,
          'precipitation_sum': rainTotals,
          'precipitation_probability_max': rainChances,
        },
      }),
    );
  }
}

class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;
}
