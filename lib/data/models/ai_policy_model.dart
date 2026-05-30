class AiScope {
  final String id;
  final String name;
  final String type; // 'personal', 'team', 'organization'
  final String? parentId;

  AiScope({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
  });

  factory AiScope.fromJson(Map<String, dynamic> json) {
    return AiScope(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      type: json['type'] ?? 'personal',
      parentId: json['parent_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'parent_id': parentId,
    };
  }
}

class AiPolicy {
  final String id;
  final String scopeId;
  final String name;
  final String? description;
  final String action; // 'ALLOW_AI', 'FORCE_SILENT', 'FORCE_DELIVER', 'BLOCK'
  final int priority;
  final Map<String, dynamic> rules;
  final bool isActive;
  final DateTime createdAt;

  AiPolicy({
    required this.id,
    required this.scopeId,
    required this.name,
    this.description,
    required this.action,
    required this.priority,
    required this.rules,
    required this.isActive,
    required this.createdAt,
  });

  factory AiPolicy.fromJson(Map<String, dynamic> json) {
    return AiPolicy(
      id: json['id'] ?? '',
      scopeId: json['scope_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      action: json['action'] ?? 'ALLOW_AI',
      priority: json['priority'] ?? 0,
      rules: json['rules'] ?? {},
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'scope_id': scopeId,
      'name': name,
      'description': description,
      'action': action,
      'priority': priority,
      'rules': rules,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
