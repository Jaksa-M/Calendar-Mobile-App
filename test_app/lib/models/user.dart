class User {
  final int id;
  final String username;
  final String displayName;

  const User({
    required this.id,
    required this.username,
    required this.displayName,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as int,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
      );

  @override
  bool operator ==(Object other) => other is User && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
