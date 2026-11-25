import 'ingredient.dart';

/// Motivos aceptados por la web (`/api/inventory-losses`). El nombre del enum
/// es el valor que se guarda en Firestore.
enum LossReason {
  caducado('Caducado'),
  perdida('Pérdida'),
  dano('Daño'),
  otro('Otro');

  const LossReason(this.label);

  final String label;

  static LossReason fromName(String? value) => LossReason.values.firstWhere(
        (reason) => reason.name == value,
        orElse: () => LossReason.perdida,
      );
}

/// Cantidad descartada de un insumo. `unit` guarda el símbolo de
/// [IngredientUnit] para que la web muestre la misma unidad que la APK.
class LossLine {
  const LossLine({
    required this.ingredientId,
    required this.name,
    required this.quantity,
    this.unit = 'unidad',
  });

  final String ingredientId;
  final String name;
  final double quantity;
  final String unit;

  String get unitLabel => IngredientUnit.fromSymbol(unit).label;

  String get quantityLabel {
    final value = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);
    return '$value ${unitLabel.toLowerCase()}';
  }

  LossLine copyWith({
    String? ingredientId,
    String? name,
    double? quantity,
    String? unit,
  }) =>
      LossLine(
        ingredientId: ingredientId ?? this.ingredientId,
        name: name ?? this.name,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
      );

  Map<String, dynamic> toJson() => {
        'ingredientId': ingredientId,
        'name': name,
        'quantity': quantity,
        'unit': unit,
      };

  factory LossLine.fromJson(Map<String, dynamic> json) => LossLine(
        ingredientId: json['ingredientId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        unit: json['unit'] as String? ?? 'unidad',
      );
}

/// Entrada de auditoría. La web conserva todas las acciones y añade la del
/// servidor al recibir el registro.
class LossAuditEntry {
  const LossAuditEntry({
    required this.action,
    required this.timestamp,
    this.actorId = '',
    this.actorName = '',
    this.actorRole = '',
  });

  final String action;
  final DateTime timestamp;
  final String actorId;
  final String actorName;
  final String actorRole;

  LossAuditEntry copyWith({
    String? action,
    DateTime? timestamp,
    String? actorId,
    String? actorName,
    String? actorRole,
  }) =>
      LossAuditEntry(
        action: action ?? this.action,
        timestamp: timestamp ?? this.timestamp,
        actorId: actorId ?? this.actorId,
        actorName: actorName ?? this.actorName,
        actorRole: actorRole ?? this.actorRole,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'timestamp': timestamp.toIso8601String(),
        'actorId': actorId,
        'actorName': actorName,
        'actorRole': actorRole,
      };

  factory LossAuditEntry.fromJson(Map<String, dynamic> json) =>
      LossAuditEntry(
        action: json['action'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
        actorId: json['actorId'] as String? ?? '',
        actorName: json['actorName'] as String? ?? '',
        actorRole: json['actorRole'] as String? ?? '',
      );
}

/// Pérdida o caducidad de ingredientes registrada por administradores y
/// cocineros. Se guarda primero en el dispositivo; [synced] indica que la web
/// (y por ende Firestore) ya recibió la auditoría.
class InventoryLoss {
  const InventoryLoss({
    required this.id,
    required this.reason,
    required this.lines,
    required this.createdAt,
    this.notes = '',
    this.photoPath,
    this.photoUrl,
    this.synced = false,
    this.createdById = '',
    this.createdByName = '',
    this.createdByRole = '',
    this.auditLog = const [],
  });

  final String id;
  final LossReason reason;
  final List<LossLine> lines;
  final DateTime createdAt;
  final String notes;

  /// Ruta local de la foto tomada con la cámara. Se conserva mientras la
  /// subida a Storage esté pendiente.
  final String? photoPath;

  /// URL pública devuelta por Firebase Storage una vez subida la foto.
  final String? photoUrl;
  final bool synced;
  final String createdById;
  final String createdByName;
  final String createdByRole;
  final List<LossAuditEntry> auditLog;

  String get linesSummary => lines
      .map((line) => '${line.name} · ${line.quantityLabel}')
      .join(', ');

  String get statusLabel => synced ? 'Sincronizado' : 'Pendiente';

  InventoryLoss copyWith({
    String? id,
    LossReason? reason,
    List<LossLine>? lines,
    DateTime? createdAt,
    String? notes,
    String? photoPath,
    bool clearPhotoPath = false,
    String? photoUrl,
    bool clearPhotoUrl = false,
    bool? synced,
    String? createdById,
    String? createdByName,
    String? createdByRole,
    List<LossAuditEntry>? auditLog,
  }) =>
      InventoryLoss(
        id: id ?? this.id,
        reason: reason ?? this.reason,
        lines: lines ?? this.lines,
        createdAt: createdAt ?? this.createdAt,
        notes: notes ?? this.notes,
        photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
        photoUrl: clearPhotoUrl ? null : (photoUrl ?? this.photoUrl),
        synced: synced ?? this.synced,
        createdById: createdById ?? this.createdById,
        createdByName: createdByName ?? this.createdByName,
        createdByRole: createdByRole ?? this.createdByRole,
        auditLog: auditLog ?? this.auditLog,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'reason': reason.name,
        'lines': lines.map((line) => line.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
        'photoPath': photoPath,
        'photoUrl': photoUrl,
        'synced': synced,
        'createdById': createdById,
        'createdByName': createdByName,
        'createdByRole': createdByRole,
        'auditLog': auditLog.map((entry) => entry.toJson()).toList(),
      };

  /// Contrato exacto de `POST /api/inventory-losses`.
  Map<String, dynamic> toWebJson({String? photoUrlOverride}) => {
        'id': id,
        'reason': reason.name,
        'lines': lines.map((line) => line.toJson()).toList(),
        'notes': notes,
        'photoUrl': photoUrlOverride ?? photoUrl,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': {
          'uid': createdById,
          'name': createdByName,
          'role': createdByRole,
        },
        'auditLog': auditLog.map((entry) => entry.toJson()).toList(),
      };

  factory InventoryLoss.fromJson(Map<String, dynamic> json) => InventoryLoss(
        id: json['id'] as String? ?? '',
        reason: LossReason.fromName(json['reason'] as String?),
        lines: (json['lines'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LossLine.fromJson)
            .toList(),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        notes: json['notes'] as String? ?? '',
        photoPath: json['photoPath'] as String?,
        photoUrl: json['photoUrl'] as String?,
        synced: json['synced'] as bool? ?? false,
        createdById: json['createdById'] as String? ?? '',
        createdByName: json['createdByName'] as String? ?? '',
        createdByRole: json['createdByRole'] as String? ?? '',
        auditLog: (json['auditLog'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LossAuditEntry.fromJson)
            .toList(),
      );

  /// Convierte el documento de Firestore devuelto por la web en un registro
  /// local ya sincronizado.
  factory InventoryLoss.fromWebJson(Map<String, dynamic> json) {
    final createdBy = json['createdBy'] is Map<String, dynamic>
        ? json['createdBy'] as Map<String, dynamic>
        : <String, dynamic>{};
    return InventoryLoss(
      id: json['id'] as String? ?? '',
      reason: LossReason.fromName(json['reason'] as String?),
      lines: (json['lines'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LossLine.fromJson)
          .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now(),
      notes: json['notes'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      synced: true,
      createdById: createdBy['uid'] as String? ?? '',
      createdByName: createdBy['name'] as String? ?? '',
      createdByRole: createdBy['role'] as String? ?? '',
      auditLog: (json['auditLog'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(LossAuditEntry.fromJson)
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InventoryLoss &&
      other.id == id &&
      other.reason == reason &&
      other.synced == synced &&
      other.photoUrl == photoUrl &&
      other.notes == notes &&
      _sameLines(other.lines, lines) &&
      _sameAudit(other.auditLog, auditLog);

  @override
  int get hashCode => Object.hash(
        id,
        reason,
        synced,
        photoUrl,
        notes,
        Object.hashAll(lines.map((line) => line.toJson())),
      );

  static bool _sameLines(List<LossLine> a, List<LossLine> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toJson().toString() != b[i].toJson().toString()) return false;
    }
    return true;
  }

  static bool _sameAudit(List<LossAuditEntry> a, List<LossAuditEntry> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toJson().toString() != b[i].toJson().toString()) return false;
    }
    return true;
  }
}
