import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

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

  Geocoding? _geocoding;

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

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 20));

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

    return DeviceLocation(
      label: label,
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
