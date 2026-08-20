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

    final suggestions = <LocationSuggestion>[];
    final seen = <String>{};
    for (final searchQuery in _queryVariants(trimmedQuery)) {
      final results = await _searchNominatim(searchQuery);
      for (final suggestion in results) {
        final key =
            '${suggestion.title}|${suggestion.subtitle}'.toLowerCase();
        if (seen.add(key)) suggestions.add(suggestion);
      }
      if (suggestions.length >= 12) break;
    }

    return suggestions.take(12).toList();
  }

  Future<List<LocationSuggestion>> _searchNominatim(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'namedetails': '1',
      'dedupe': '1',
      'countrycodes': 'ph',
      'limit': '12',
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

  List<String> _queryVariants(String query) {
    final normalized = query.toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final variants = <String>[];

    void add(String value) {
      final cleaned = value.trim();
      if (cleaned.length < 3) return;
      if (variants.any((item) => item.toLowerCase() == cleaned.toLowerCase())) {
        return;
      }
      variants.add(cleaned);
    }

    final smMatch = RegExp(r'^s\.?m\.?\s+(.+)$').firstMatch(normalized);
    if (smMatch != null) {
      final place = smMatch.group(1)!.trim();
      add('SM City $place');
      add('SM Center $place');
      add('mall $place');
    }

    final robinsonsMatch = RegExp(
      r'^(robinson|robinsons)\s+(.+)$',
    ).firstMatch(normalized);
    if (robinsonsMatch != null) {
      final place = robinsonsMatch.group(2)!.trim();
      add('Robinsons Place $place');
      add('Robinsons $place');
    }

    add(query);
    add('$query Philippines');
    return variants;
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

    final displayName = _cleanText(json['display_name']);
    final address = json['address'] as Map<String, dynamic>? ?? const {};
    final roadAddress = _joinNonEmpty([
      address['house_number'],
      address['road'],
    ]);
    final title = _firstNonEmpty([
      json['name'],
      roadAddress,
      address['amenity'],
      address['shop'],
      address['tourism'],
      address['office'],
      address['building'],
      address['leisure'],
      address['road'],
      address['neighbourhood'],
      address['suburb'],
      address['quarter'],
      address['village'],
      address['town'],
      address['city'],
      displayName.split(',').first,
    ]);
    final subtitle = _subtitleFor(title, displayName, address);

    return LocationSuggestion(
      title: title,
      subtitle: subtitle,
      latitude: latitude,
      longitude: longitude,
    );
  }

  String _subtitleFor(
    String title,
    String displayName,
    Map<String, dynamic> address,
  ) {
    final parts = <String>[
      _cleanText(address['road']),
      _cleanText(address['neighbourhood']),
      _cleanText(address['suburb']),
      _cleanText(address['quarter']),
      _cleanText(address['village']),
      _cleanText(address['city']),
      _cleanText(address['town']),
      _cleanText(address['municipality']),
      _cleanText(address['county']),
      _cleanText(address['state']),
    ];
    final uniqueParts = <String>[];
    for (final part in parts) {
      if (part.isEmpty) continue;
      if (part.toLowerCase() == title.toLowerCase()) continue;
      if (uniqueParts.any((item) => item.toLowerCase() == part.toLowerCase())) {
        continue;
      }
      uniqueParts.add(part);
      if (uniqueParts.length == 3) break;
    }

    if (uniqueParts.isNotEmpty) return uniqueParts.join(', ');
    return displayName.isEmpty || displayName == title
        ? 'Tap to use this location'
        : displayName;
  }

  String _joinNonEmpty(List<dynamic> values) {
    final parts = values.map(_cleanText).where((value) => value.isNotEmpty);
    return parts.join(' ');
  }

  String _cleanText(dynamic value) => value?.toString().trim() ?? '';

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = _cleanText(value);
      if (text.isNotEmpty) return text;
    }
    return 'Selected location';
  }
}
