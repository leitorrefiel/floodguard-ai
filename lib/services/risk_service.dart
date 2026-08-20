import 'weather_service.dart';

class RiskAssessment {
  const RiskAssessment({
    required this.level,
    required this.score,
    required this.summary,
    required this.aiExplanation,
    required this.riskFactors,
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
  final String aiExplanation;
  final List<String> riskFactors;
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

  RiskAssessment assess(
    WeatherForecastResponse forecast, {
    String locationLabel = 'selected area',
  }) {
    final current = forecast.current;
    final maxDailyRain = forecast.days
        .map((day) => day.precipitationMm)
        .fold<double>(0, (max, value) => value > max ? value : max);
    final nextRainTotal = forecast.days
        .map((day) => day.precipitationMm)
        .fold<double>(0, (total, value) => total + value);
    final score = _riskScore(
      currentRain: current.rainMm,
      currentPrecipitation: current.precipitationMm,
      forecastRain: maxDailyRain,
    );
    final level = _riskLevel(score);
    final factors = _riskFactors(
      currentRain: current.rainMm,
      currentPrecipitation: current.precipitationMm,
      forecastRain: maxDailyRain,
      nextRainTotal: nextRainTotal,
      temperature: current.temperatureCelsius,
    );

    return RiskAssessment(
      level: level,
      score: score,
      summary: _summaryFor(level, current.rainMm, maxDailyRain, nextRainTotal),
      aiExplanation: _aiExplanation(
        level: level,
        score: score,
        locationLabel: locationLabel,
        factors: factors,
      ),
      riskFactors: factors,
      currentRainMm: current.rainMm,
      currentPrecipitationMm: current.precipitationMm,
      forecastRainMm: maxDailyRain,
      temperatureCelsius: current.temperatureCelsius,
      observedAt: current.observedAt,
      actions: _actionsFor(
        level: level,
        currentRain: current.rainMm,
        forecastRain: maxDailyRain,
        nextRainTotal: nextRainTotal,
        locationLabel: locationLabel,
      ),
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

  String _summaryFor(
    String level,
    double currentRain,
    double forecastRain,
    double nextRainTotal,
  ) {
    if (level == 'High Risk') {
      return 'Heavy rain signals are present. Prepare for possible flooding and monitor local advisories.';
    }
    if (level == 'Moderate Risk') {
      return 'Rainfall could still affect flood-prone roads and low-lying areas. Stay alert.';
    }
    if (level == 'Low Risk') {
      return 'Light to moderate rain is possible. Check updates before traveling through flood-prone areas.';
    }
    if (currentRain <= 0 && forecastRain <= 2 && nextRainTotal <= 6) {
      return 'No significant rainfall is detected right now. Continue monitoring weather updates.';
    }
    return 'Flood risk is currently limited, but conditions can change when rain intensifies.';
  }

  List<String> _riskFactors({
    required double currentRain,
    required double currentPrecipitation,
    required double forecastRain,
    required double nextRainTotal,
    required double temperature,
  }) {
    final factors = <String>[];
    if (currentRain >= 8 || currentPrecipitation >= 8) {
      factors.add('heavy rain is active now');
    } else if (currentRain > 0 || currentPrecipitation > 0) {
      factors.add('rain is currently detected');
    } else {
      factors.add('no active rain at the moment');
    }
    if (forecastRain >= 50) {
      factors.add('very high forecast rainfall is possible');
    } else if (forecastRain >= 25) {
      factors.add('moderate forecast rainfall is possible');
    } else if (forecastRain >= 5) {
      factors.add('light forecast rainfall is possible');
    } else {
      factors.add('forecast rainfall is low');
    }
    if (nextRainTotal >= 60) {
      factors.add('multi-day rainfall accumulation may raise runoff');
    }
    if (temperature >= 30 && forecastRain >= 10) {
      factors.add('warm moist conditions may support stronger showers');
    }
    return factors;
  }

  String _aiExplanation({
    required String level,
    required double score,
    required String locationLabel,
    required List<String> factors,
  }) {
    final roundedScore = score.toStringAsFixed(0);
    final factorText = factors.take(2).join(', ');
    return 'Local AI model scored $locationLabel as $level ($roundedScore/100) because $factorText.';
  }

  List<RiskAction> _actionsFor({
    required String level,
    required double currentRain,
    required double forecastRain,
    required double nextRainTotal,
    required String locationLabel,
  }) {
    final actions = <RiskAction>[];

    if (currentRain >= 8) {
      actions.add(
        const RiskAction(
          title: 'Pause non-essential travel',
          description: 'Active heavy rain is detected. Wait for rainfall to weaken before leaving.',
          iconKey: 'route',
        ),
      );
    }

    if (forecastRain >= 25 || nextRainTotal >= 45) {
      actions.add(
        const RiskAction(
          title: 'Prepare flood essentials',
          description: 'Pack water, medicine, power bank, flashlight, and important documents early.',
          iconKey: 'bag',
        ),
      );
    }

    if (level == 'High Risk') {
      actions.addAll(const [
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
      ]);
    } else if (level == 'Moderate Risk') {
      actions.addAll(const [
        RiskAction(
          title: 'Watch rain intensity',
          description: 'Refresh the live forecast and monitor if rain gets stronger in the next hours.',
          iconKey: 'monitor',
        ),
        RiskAction(
          title: 'Avoid low-lying streets',
          description: 'Choose wider roads and avoid canals, riverbanks, and poor-drainage areas.',
          iconKey: 'route',
        ),
      ]);
    } else if (level == 'Low Risk') {
      actions.addAll(const [
        RiskAction(
          title: 'Keep alerts enabled',
          description: 'Risk is low, but stronger rain can still change local conditions quickly.',
          iconKey: 'monitor',
        ),
        RiskAction(
          title: 'Check route before travel',
          description: 'Look for reports of ponding or blocked drainage before passing flood-prone roads.',
          iconKey: 'route',
        ),
      ]);
    } else {
      actions.addAll(const [
        RiskAction(
          title: 'Stay weather-aware',
          description: 'No urgent flood signal is detected, but keep alerts enabled.',
          iconKey: 'monitor',
        ),
        RiskAction(
          title: 'Report blocked drainage',
          description: 'If you notice clogged drains nearby, report them before rainfall increases.',
          iconKey: 'drainage',
        ),
      ]);
    }

    if (_looksLikeStreet(locationLabel)) {
      actions.add(
        const RiskAction(
          title: 'Check nearby street drainage',
          description: 'Street-level flooding usually starts near clogged drains and low road sections.',
          iconKey: 'drainage',
        ),
      );
    }

    actions.add(
      const RiskAction(
        title: 'Keep emergency contacts ready',
        description: 'Save LGU, barangay, and family contacts before conditions worsen.',
        iconKey: 'phone',
      ),
    );

    final unique = <String>{};
    return actions
        .where((action) => unique.add(action.title.toLowerCase()))
        .take(3)
        .toList();
  }

  bool _looksLikeStreet(String locationLabel) {
    final label = locationLabel.toLowerCase();
    return label.contains('street') ||
        label.contains(' st') ||
        label.contains('road') ||
        label.contains('rd') ||
        label.contains('avenue') ||
        label.contains('ave');
  }
}
