import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/utils/rainfall_labels.dart';

void main() {
  test('uses the five plain-language hourly rainfall labels', () {
    expect(rainfallLabel(0), 'No rain');
    expect(rainfallLabel(0.2), 'Drizzle');
    expect(rainfallLabel(1), 'Light rain');
    expect(rainfallLabel(4), 'Moderate rain');
    expect(rainfallLabel(8), 'Heavy rain');
  });

  test('weather code prevents rounded drizzle from reading as no rain', () {
    expect(rainfallLabel(0, weatherCode: 51), 'Drizzle');
    expect(rainfallLabel(0, weatherCode: 61), 'Light rain');
  });

  test('daily outlook uses accumulation-aware plain language', () {
    expect(
      dailyRainOutlook(2.9, dayLabel: 'Sunday'),
      'Light rain expected on Sunday',
    );
    expect(
      dailyRainOutlook(8, dayLabel: 'Monday'),
      'Moderate rain expected on Monday',
    );
    expect(
      dailyRainOutlook(25, dayLabel: 'Tuesday'),
      'Heavy rain expected on Tuesday',
    );
  });
}
