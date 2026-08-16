import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/flood_alert.dart';

class AlertService {
  AlertService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<FloodAlert>> getActiveAlerts() async {
    final data = await _client
        .from('alerts')
        .select()
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(20);
    return (data as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(FloodAlert.fromJson)
        .toList();
  }

  RealtimeChannel subscribe(void Function() onChanged) => _client
      .channel('floodguard-alerts')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'alerts',
        callback: (_) => onChanged(),
      )
      .subscribe();

  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}
