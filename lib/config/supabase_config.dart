class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.publishableKey});

  factory SupabaseConfig.fromEnvironment() {
    const url = String.fromEnvironment('SUPABASE_URL');
    const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
    final config = SupabaseConfig(url: url, publishableKey: publishableKey);
    config.validate();
    return config;
  }

  final String url;
  final String publishableKey;

  String get projectHost => Uri.parse(url).host;

  void validate() {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.path.isNotEmpty && uri.path != '/') {
      throw const SupabaseConfigurationException(
        'SUPABASE_URL is missing or invalid. Copy Project URL from the '
        'Supabase Dashboard and pass it with --dart-define.',
      );
    }
    if (publishableKey.isEmpty ||
        !(publishableKey.startsWith('sb_publishable_') ||
            publishableKey.startsWith('eyJ'))) {
      throw const SupabaseConfigurationException(
        'SUPABASE_PUBLISHABLE_KEY is missing or invalid. Copy the publishable '
        'key (or legacy anon key) from the Supabase Dashboard. Never use the '
        'service_role key in Flutter.',
      );
    }
  }
}

class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}
