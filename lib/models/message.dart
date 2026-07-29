class Message {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final String status; // 'pending', 'sent', 'delivered', 'failed'
  final DateTime createdAt;
  final List<String> progressSteps; // SSE progress steps for processing messages

  Message({
    required this.id,
    required this.role,
    required this.content,
    this.status = 'pending',
    required this.createdAt,
    this.progressSteps = const [],
  });

  Message copyWith({
    String? id,
    String? role,
    String? content,
    String? status,
    DateTime? createdAt,
    List<String>? progressSteps,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      progressSteps: progressSteps ?? this.progressSteps,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'role': role,
    'content': content,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Message.fromMap(Map<String, dynamic> map) {
    // Handle both camelCase and snake_case from server
    final createdAtStr = map['createdAt'] ?? map['created_at'] ?? DateTime.now().toIso8601String();
    DateTime parsed;
    try {
      parsed = DateTime.parse(createdAtStr).toLocal();
    } catch (_) {
      parsed = DateTime.now();
    }
    return Message(
      id: map['id'] ?? '',
      role: map['role'] ?? 'assistant',
      content: map['content'] ?? '',
      status: map['status'] ?? 'sent',
      createdAt: parsed,
    );
  }
}
