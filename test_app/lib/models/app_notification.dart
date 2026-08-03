class AppNotification {
  final int id;
  final String type; // 'invited' | 'rsvp'
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        read: json['read'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );
}
