String? validateEmailAddress(String? value) {
  final email = value?.trim() ?? '';
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  return valid ? null : 'Enter a valid email address.';
}

String? validatePassword(String? value) =>
    (value ?? '').length >= 6 ? null : 'Use at least 6 characters.';

String? validateHazardLocation(String? value) {
  final location = value?.trim() ?? '';
  if (location.isEmpty) return 'Location is required.';
  if (location.length < 3) return 'Enter a more specific location.';
  return null;
}

String? validateHazardDescription(String? value) {
  final description = value?.trim() ?? '';
  if (description.length > 300) return 'Use 300 characters or fewer.';
  if (description.isNotEmpty && description.length < 8) {
    return 'Use at least 8 characters or leave it blank.';
  }
  return null;
}

bool hasValidCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;
