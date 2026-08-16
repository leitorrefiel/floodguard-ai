class FloodAlert {
  const FloodAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.area,
    required this.createdAt,
  });

  factory FloodAlert.fromJson(Map<String, dynamic> json) => FloodAlert(
    id: json['id'] as String,
    title: json['title'] as String,
    message: json['message'] as String,
    severity: json['severity'] as String,
    area: json['area'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );

  final String id;
  final String title;
  final String message;
  final String severity;
  final String? area;
  final DateTime createdAt;
}
