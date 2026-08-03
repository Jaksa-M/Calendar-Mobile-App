enum AppointmentScope { shared, private }

enum RsvpStatus { pending, yes, no }

RsvpStatus _rsvpFromJson(String? v) {
  switch (v) {
    case 'yes':
      return RsvpStatus.yes;
    case 'no':
      return RsvpStatus.no;
    default:
      return RsvpStatus.pending;
  }
}

class Participant {
  final int userId;
  final RsvpStatus response;

  const Participant({required this.userId, required this.response});

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(
        userId: json['user_id'] as int,
        response: _rsvpFromJson(json['response'] as String?),
      );
}

class Appointment {
  final int id;
  final String title;
  final String? description;
  final AppointmentScope scope;
  final DateTime startsAt;
  final DateTime endsAt;
  final int createdBy;
  final List<Participant> participants;

  const Appointment({
    required this.id,
    required this.title,
    required this.description,
    required this.scope,
    required this.startsAt,
    required this.endsAt,
    required this.createdBy,
    required this.participants,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as int,
        title: json['title'] as String,
        description: json['description'] as String?,
        scope: json['scope'] == 'shared'
            ? AppointmentScope.shared
            : AppointmentScope.private,
        // Server sends UTC ISO-8601; convert to local for display.
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        createdBy: json['created_by'] as int,
        participants: (json['participants'] as List)
            .map((e) => Participant.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  List<int> get participantIds => participants.map((p) => p.userId).toList();

  /// This user's response, or null if they aren't a participant.
  RsvpStatus? responseFor(int userId) {
    for (final p in participants) {
      if (p.userId == userId) return p.response;
    }
    return null;
  }

  /// The calendar-day this appointment starts on (date-only, for grouping).
  DateTime get day => DateTime(startsAt.year, startsAt.month, startsAt.day);
}
