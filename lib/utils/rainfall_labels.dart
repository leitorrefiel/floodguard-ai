enum RainfallWindow { hourly, daily }

const _drizzleCodes = {51, 53, 55, 56, 57};
const _rainCodes = {61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99};

String rainfallLabel(
  double amountMm, {
  int? weatherCode,
  RainfallWindow window = RainfallWindow.hourly,
}) {
  if (_drizzleCodes.contains(weatherCode) && amountMm < 2.5) {
    return 'Drizzle';
  }
  if (amountMm <= 0) {
    return _rainCodes.contains(weatherCode) ? 'Light rain' : 'No rain';
  }

  if (window == RainfallWindow.daily) {
    if (amountMm < 1) return 'Drizzle';
    if (amountMm < 5) return 'Light rain';
    if (amountMm < 20) return 'Moderate rain';
    return 'Heavy rain';
  }

  if (amountMm < 0.5) return 'Drizzle';
  if (amountMm < 2.5) return 'Light rain';
  if (amountMm < 7.5) return 'Moderate rain';
  return 'Heavy rain';
}

String dailyRainOutlook(
  double amountMm, {
  required String dayLabel,
  int? weatherCode,
}) {
  final label = rainfallLabel(
    amountMm,
    weatherCode: weatherCode,
    window: RainfallWindow.daily,
  );
  return switch (label) {
    'No rain' => 'No rain expected on $dayLabel',
    'Drizzle' => 'Drizzle possible on $dayLabel',
    _ => '$label expected on $dayLabel',
  };
}
