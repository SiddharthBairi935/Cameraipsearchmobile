class OperationHistoryEntry {
  const OperationHistoryEntry({required this.id, required this.occurredAt, required this.operation, required this.target, required this.outcome, required this.details});
  final int id;
  final DateTime occurredAt;
  final String operation, target, outcome, details;

  factory OperationHistoryEntry.fromMap(Map<String, Object?> map) => OperationHistoryEntry(
    id: map['id'] as int,
    occurredAt: DateTime.tryParse(map['occurred_at'] as String? ?? '')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    operation: map['operation'] as String? ?? '',
    target: map['target'] as String? ?? '',
    outcome: map['outcome'] as String? ?? '',
    details: map['details'] as String? ?? '',
  );
}