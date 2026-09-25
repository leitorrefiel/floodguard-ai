import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConnectionService {
  const SupabaseConnectionService({required this.client, required this.host});

  final SupabaseClient client;
  final String host;

  Future<bool> verify() async {
    try {
      await client.from('hazard_reports').select('id').limit(1);
      debugPrint('[Supabase] connected host=$host');
      return true;
    } catch (error) {
      debugPrint('[Supabase] connection failed host=$host error=$error');
      return false;
    }
  }
}
