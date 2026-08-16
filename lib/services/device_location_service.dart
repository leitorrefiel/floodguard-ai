import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceLocation {
  const DeviceLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String label;
  final double latitude;
  final double longitude;
}

class LocationAccessException implements Exception {
  const LocationAccessException(this.message);
  final String message;
}

class DeviceLocationService {
  DeviceLocationService({Geocoding? geocoding}) : _geocoding = geocoding;

  static const _labelKey = 'saved_location_label';
  static const _latitudeKey = 'saved_location_latitude';
  static const _longitudeKey = 'saved_location_longitude';

  Geocoding? _geocoding;

  Future<DeviceLocation?> getSavedLocation() async {
    final preferences = await SharedPreferences.getInstance();
    final label = preferences.getString(_labelKey);
    final latitude = preferences.getDouble(_latitudeKey);
    final longitude = preferences.getDouble(_longitudeKey);
    if (label == null || latitude == null || longitude == null) return null;
    return DeviceLocation(
      label: label,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<void> _saveLocation(DeviceLocation location) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_labelKey, location.label);
    await preferences.setDouble(_latitudeKey, location.latitude);
    await preferences.setDouble(_longitudeKey, location.longitude);
  }

  Future<DeviceLocation> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationAccessException(
        'Turn on your phone location service, then try again.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationAccessException('Location permission was denied.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationAccessException(
        'Location permission is blocked. Enable it in App Settings.',
      );
    }

    final cachedPosition = await Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: true,
    );
    final position =
        cachedPosition ??
        await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            forceLocationManager: true,
            timeLimit: const Duration(seconds: 20),
          ),
        );

    var label =
        '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    try {
      final placemarks = await (_geocoding ??= Geocoding())
          .placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String>[
          if (place.locality?.trim().isNotEmpty ?? false)
            place.locality!.trim(),
          if (place.administrativeArea?.trim().isNotEmpty ?? false)
            place.administrativeArea!.trim(),
          if (place.country?.trim().isNotEmpty ?? false) place.country!.trim(),
        ];
        if (parts.isNotEmpty) label = parts.join(', ');
      }
    } catch (_) {
      // The coordinates remain useful when Android's geocoding service is unavailable.
    }

    final location = DeviceLocation(
      label: label,
      latitude: position.latitude,
      longitude: position.longitude,
    );
    await _saveLocation(location);
    return location;
  }
}
