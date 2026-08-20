import 'weather_service.dart';

class RiskAssessment {
  const RiskAssessment({
    required this.level,
    required this.score,
    required this.summary,
    required this.currentRainMm,
    required this.currentPrecipitationMm,
    required this.forecastRainMm,
    required this.temperatureCelsius,
    required this.observedAt,
    required this.actions,
  });

  final String level;
  final double score;
  final String summary;
  final double currentRainMm;
  final double currentPrecipitationMm;
  final double forecastRainMm;
  final double temperatureCelsius;
  final String observedAt;
  final List<RiskAction> actions;

  String get currentRainLabel => '${currentRainMm.toStringAsFixed(1)} mm';
  String get precipitationLabel =>
      '${currentPrecipitationMm.toStringAsFixed(1)} mm';
  String get forecastRainLabel => '${forecastRainMm.toStringAsFixed(1)} mm';
  String get temperatureLabel => '${temperatureCelsius.toStringAsFixed(0)} C';
}

class RiskAction {
  const RiskAction({
    required this.title,
    required this.description,
    required this.iconKey,
  });

  final String title;
  final String description;
  final String iconKey;
}

class RiskService {
  const RiskService();

  RiskAssessment assess(WeatherForecastResponse forecast) {
    final current = forecast.current;
    final maxDailyRain = forecast.days
        .map((day) => day.precipitationMm)
        .fold<double>(0, (max, value) => value > max ? value : max);
    final score = _riskScore(
      currentRain: current.rainMm,
      currentPrecipitation: current.precipitationMm,
      forecastRain: maxDailyRain,
    );
    final level = _riskLevel(score);

    return RiskAssessment(
      level: level,
      score: score,
      summary: _summaryFor(level, current.rainMm, maxDailyRain),
      currentRainMm: current.rainMm,
      currentPrecipitationMm: current.precipitationMm,
      forecastRainMm: maxDailyRain,
      temperatureCelsius: current.temperatureCelsius,
      observedAt: current.observedAt,
      actions: _actionsFor(level, current.rainMm, maxDailyRain),
    );
  }

  double _riskScore({
    required double currentRain,
    required double currentPrecipitation,
    required double forecastRain,
  }) {
    final currentLoad = (currentRain > currentPrecipitation
            ? currentRain
            : currentPrecipitation) *
        5;
    final forecastLoad = forecastRain * 1.15;
    final score = currentLoad + forecastLoad;
    if (score < 5) return 5;
    if (score > 100) return 100;
    return score;
  }

  String _riskLevel(double score) {
    if (score >= 75) return 'High Risk';
    if (score >= 45) return 'Moderate Risk';
    if (score >= 20) return 'Low Risk';
    return 'Minimal Risk';
  }

  String _summaryFor(String level, double currentRain, double forecastRain) {
    if (level == 'High Risk') {
      return 'Heavy rain signals are present. Prepare for possible flooding and monitor local advisories.';
    }
    if (level == 'Moderate Risk') {
      return 'Rainfall could still affect flood-prone roads and low-lying areas. Stay alert.';
    }
    if (level == 'Low Risk') {
      return 'Light to moderate rain is possible. Check updates before traveling through flood-prone areas.';
    }
    if (currentRain <= 0 && forecastRain <= 2) {
      return 'No significant rainfall is detected right now. Continue monitoring weather updates.';
    }
    return 'Flood risk is currently limited, but conditions can change when rain intensifies.';
  }

  List<RiskAction> _actionsFor(
    String level,
    double currentRain,
    double forecastRain,
  ) {
    if (level == 'High Risk') {
      return const [
        RiskAction(
          title: 'Move valuables higher',
          description: 'Keep documents, chargers, medicine, and essentials above floor level.',
          iconKey: 'move_up',
        ),
        RiskAction(
          title: 'Avoid flooded roads',
          description: 'Do not walk or drive through floodwater, especially at night.',
          iconKey: 'route',
        ),
        RiskAction(
          title: 'Prepare to evacuate',
          description: 'Check the nearest evacuation center and keep your phone charged.',
          iconKey: 'evacuate',
        ),
      ];
    }
    if (level == 'Moderate Risk') {
      return const [
        RiskAction(
          title: 'Monitor rainfall updates',
          description: 'Refresh the forecast and watch for stronger rain in the next hours.',
          iconKey: 'monitor',
        ),
        RiskAction(
          title: 'Plan a safer route',
          description: 'Avoid low-lying streets, riverbanks, and roads with poor drainage.',
          iconKey: 'route',
        ),
        RiskAction(
          title: 'Ready your go-bag',
          description: 'Prepare water, medicine, power bank, flashlight, and key documents.',
          iconKey: 'bag',
        ),
      ];
    }
    return const [
      RiskAction(
        title: 'Stay weather-aware',
        description: 'Keep alerts enabled and refresh if rain becomes stronger.',
        iconKey: 'monitor',
      ),
      RiskAction(
        title: 'Check drainage nearby',
        description: 'Clear small obstructions only if it is safe and water is not rising.',
        iconKey: 'drainage',
      ),
      RiskAction(
        title: 'Keep emergency contacts ready',
        description: 'Save LGU, barangay, and family contacts before conditions worsen.',
        iconKey: 'phone',
      ),
    ];
  }
}
