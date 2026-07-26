/// Placeholder data service. A future version will connect verified weather,
/// rainfall, water-level, and community-report sources before making alerts.
class RiskService {
  const RiskService();

  String get currentRisk => 'Moderate Risk';
  String get rainfall => '36 mm';
  String get waterLevel => '1.2 m';
}
