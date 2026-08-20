import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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

class LocationSuggestion {
  const LocationSuggestion({
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;

  DeviceLocation toDeviceLocation() => DeviceLocation(
    label: title,
    latitude: latitude,
    longitude: longitude,
  );
}

class DeviceLocationService {
  DeviceLocationService({Geocoding? geocoding, http.Client? client})
    : _geocoding = geocoding,
      _client = client ?? http.Client();

  static const _labelKey = 'saved_location_label';
  static const _latitudeKey = 'saved_location_latitude';
  static const _longitudeKey = 'saved_location_longitude';

  Geocoding? _geocoding;
  final http.Client _client;

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

  Future<void> saveLocation(DeviceLocation location) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_labelKey, location.label);
    await preferences.setDouble(_latitudeKey, location.latitude);
    await preferences.setDouble(_longitudeKey, location.longitude);
  }

  Future<DeviceLocation> selectSuggestion(LocationSuggestion suggestion) async {
    final location = suggestion.toDeviceLocation();
    await saveLocation(location);
    return location;
  }

  Future<List<LocationSuggestion>> searchSuggestions(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 3) return const [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmedQuery,
      'format': 'jsonv2',
      'addressdetails': '1',
      'countrycodes': 'ph',
      'viewbox': '120.80,15.05,120.98,14.86',
      'bounded': '1',
      'limit': '8',
      'accept-language': 'en',
    });

    final response = await _client
        .get(
          uri,
          headers: const {
            'User-Agent': 'FloodGuardAI/1.0 student prototype',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw const LocationAccessException(
        'Location search is temporarily unavailable.',
      );
    }

    final results = jsonDecode(response.body) as List<dynamic>;
    return results
        .cast<Map<String, dynamic>>()
        .map(_suggestionFromNominatim)
        .whereType<LocationSuggestion>()
        .toList();
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

    final cachedPosition = await Geolocator.getLastKnownPosition();
    final position =
        cachedPosition ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
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
    await saveLocation(location);
    return location;
  }

  LocationSuggestion? _suggestionFromNominatim(Map<String, dynamic> json) {
    final latitude = double.tryParse(json['lat'] as String? ?? '');
    final longitude = double.tryParse(json['lon'] as String? ?? '');
    if (latitude == null || longitude == null) return null;

    final displayName = (json['display_name'] as String? ?? '').trim();
    final address = json['address'] as Map<String, dynamic>? ?? const {};
    final title = _firstNonEmpty([
      address['road'],
      address['neighbourhood'],
      address['suburb'],
      address['village'],
      address['town'],
      address['city'],
      json['name'],
      displayName.split(',').first,
    ]);
    final subtitle = _firstNonEmpty([
      address['city'],
      address['town'],
      address['municipality'],
      address['state'],
      displayName,
    ]);

    return LocationSuggestion(
      title: title,
      subtitle: subtitle == title ? displayName : subtitle,
      latitude: latitude,
      longitude: longitude,
    );
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return 'Selected location';
  }
}
