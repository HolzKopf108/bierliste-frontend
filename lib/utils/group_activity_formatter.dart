import 'package:bierliste/models/group_activity.dart';
import 'package:intl/intl.dart';

class GroupActivityFormatter {
  static final DateFormat _timestampFormat = DateFormat('dd.MM.yyyy HH:mm');

  static String formatTimestamp(DateTime timestamp) {
    return _timestampFormat.format(timestamp.toLocal());
  }

  static String formatDescription(GroupActivity activity) {
    switch (activity.type) {
      case ActivityType.strichIncremented:
        return _formatStrichIncremented(activity);
      case ActivityType.strichIncrementUndone:
        return _formatStrichIncrementUndone(activity);
      case ActivityType.stricheDeducted:
        return _formatStricheDeducted(activity);
      case ActivityType.moneyDeducted:
        return _formatMoneyDeducted(activity);
      case ActivityType.userJoinedGroup:
        return '${_actorName(activity)} ist der Gruppe beigetreten.';
      case ActivityType.userLeftGroup:
        return '${_actorName(activity)} hat die Gruppe verlassen.';
      case ActivityType.roleGrantedWart:
        return _formatRoleGranted(activity);
      case ActivityType.roleRevokedWart:
        return _formatRoleRevoked(activity);
      case ActivityType.groupSettingsChanged:
        return _formatSettingsChanged(activity);
      case ActivityType.userRemovedFromGroup:
        return _formatUserRemoved(activity);
      case ActivityType.inviteCreated:
        return '${_actorName(activity)} hat einen Einladungslink erstellt.';
      case ActivityType.inviteUsed:
        return '${_actorName(activity)} hat einen Einladungslink verwendet.';
      case ActivityType.unknown:
        return 'Unbekannte Aktion';
    }
  }

  static String formatSettingsChangedTitle(GroupActivity activity) {
    return '${_actorName(activity)} hat Einstellungen geändert.';
  }

  static List<String> formatSettingsChangedDetails(GroupActivity activity) {
    final changedFields = _readStringList(activity.meta['changedFields']);
    final oldSettings = _readMap(activity.meta['oldSettings']);
    final newSettings = _readMap(activity.meta['newSettings']);

    return changedFields
        .map((field) => _formatChangedField(field, oldSettings, newSettings))
        .whereType<String>()
        .map((detail) => detail.trim())
        .where((detail) => detail.isNotEmpty)
        .toList();
  }

  static String _formatStrichIncremented(GroupActivity activity) {
    final actor = _actorName(activity);
    final amount = _readInt(activity.meta['amount']) ?? 0;
    final strichLabel = _strichLabel(amount);

    if (_isSelfAction(activity)) {
      return '$actor hat sich $amount $strichLabel gemacht.';
    }

    final target = _targetName(activity);
    return '$actor hat $target $amount $strichLabel gemacht.';
  }

  static String _formatStrichIncrementUndone(GroupActivity activity) {
    final actor = _actorName(activity);
    final amount = _readInt(activity.meta['amount']) ?? 0;
    final strichLabel = _strichLabel(amount);

    if (_isSelfAction(activity)) {
      return '$actor hat $amount $strichLabel rückgängig gemacht.';
    }

    final target = _targetName(activity);
    return '$actor hat bei $target $amount $strichLabel rückgängig gemacht.';
  }

  static String _formatStricheDeducted(GroupActivity activity) {
    final actor = _actorName(activity);
    final amount = _readInt(activity.meta['amountStriche']) ?? 0;
    final strichLabel = _strichLabel(amount);

    if (_isSelfAction(activity)) {
      return '$actor hat $amount $strichLabel verrechnet.';
    }

    final target = _targetName(activity);
    return '$actor hat bei $target $amount $strichLabel verrechnet.';
  }

  static String _formatMoneyDeducted(GroupActivity activity) {
    final actor = _actorName(activity);
    final amount = _readDouble(activity.meta['amountMoney']);
    final formattedAmount = amount == null
        ? 'einen Betrag'
        : _formatMoney(amount);

    if (_isSelfAction(activity)) {
      return '$actor hat $formattedAmount eingezahlt.';
    }

    final target = _targetName(activity);
    return '$actor hat bei $target $formattedAmount eingezahlt.';
  }

  static String _formatRoleGranted(GroupActivity activity) {
    final actor = _actorName(activity);
    if (_isSelfAction(activity)) {
      return '$actor ist jetzt Bierlistenwart.';
    }

    return '$actor hat ${_targetName(activity)} zum Bierlistenwart gemacht.';
  }

  static String _formatRoleRevoked(GroupActivity activity) {
    final actor = _actorName(activity);
    if (_isSelfAction(activity)) {
      return '$actor ist kein Bierlistenwart mehr.';
    }

    return '$actor hat ${_targetName(activity)} als Bierlistenwart entfernt.';
  }

  static String _formatSettingsChanged(GroupActivity activity) {
    final actor = _actorName(activity);
    final details = formatSettingsChangedDetails(activity);

    if (details.isEmpty) {
      return '$actor hat Einstellungen geändert.';
    }

    return '$actor hat Einstellungen geändert: ${details.join(', ')}.';
  }

  static String _formatUserRemoved(GroupActivity activity) {
    final actor = _actorName(activity);
    final target = activity.targetName?.trim();
    if (target == null || target.isEmpty) {
      return '$actor hat ein Mitglied aus der Gruppe entfernt.';
    }

    return '$actor hat $target aus der Gruppe entfernt.';
  }

  static String? _formatChangedField(
    String rawField,
    Map<String, dynamic>? oldSettings,
    Map<String, dynamic>? newSettings,
  ) {
    switch (rawField.trim().toUpperCase()) {
      case 'NAME':
        return _formatChangedValue(
          'Name',
          _readNullableString(oldSettings?['name']),
          _readNullableString(newSettings?['name']),
        );
      case 'PRICE_PER_STRICH':
        final oldPrice = _readDouble(oldSettings?['pricePerStrich']);
        final newPrice = _readDouble(newSettings?['pricePerStrich']);
        return _formatChangedValue(
          'Preis pro Strich',
          oldPrice == null ? null : _formatMoney(oldPrice),
          newPrice == null ? null : _formatMoney(newPrice),
        );
      case 'ONLY_WARTS_CAN_BOOK_FOR_OTHERS':
        return _formatChangedValue(
          'Nur Bierlistenwarte buchen für andere',
          _formatBool(oldSettings?['onlyWartsCanBookForOthers']),
          _formatBool(newSettings?['onlyWartsCanBookForOthers']),
        );
      case 'ALLOW_ARBITRARY_MONEY_SETTLEMENTS':
        return _formatChangedValue(
          'Beliebige Einzahlungsbeträge erlaubt',
          _formatBool(oldSettings?['allowArbitraryMoneySettlements']),
          _formatBool(newSettings?['allowArbitraryMoneySettlements']),
        );
      default:
        return null;
    }
  }

  static String _formatChangedValue(
    String label,
    String? oldValue,
    String? newValue,
  ) {
    if (oldValue == null && newValue == null) {
      return label;
    }

    if (oldValue == null) {
      return '$label: $newValue';
    }

    if (newValue == null) {
      return '$label: $oldValue';
    }

    return '$label: $oldValue -> $newValue';
  }

  static String _actorName(GroupActivity activity) {
    final actorName = activity.actorName.trim();
    if (actorName.isEmpty) {
      return 'Jemand';
    }

    return actorName;
  }

  static String _targetName(GroupActivity activity) {
    final targetName = activity.targetName?.trim();
    if (targetName == null || targetName.isEmpty) {
      return 'sich selbst';
    }

    return targetName;
  }

  static bool _isSelfAction(GroupActivity activity) {
    if (activity.targetUserId != null &&
        activity.actorUserId != null &&
        activity.targetUserId == activity.actorUserId) {
      return true;
    }

    final targetName = activity.targetName?.trim();
    if (targetName == null || targetName.isEmpty) {
      return true;
    }

    return targetName.toLowerCase() == activity.actorName.trim().toLowerCase();
  }

  static String _strichLabel(int amount) {
    return amount == 1 ? 'Strich' : 'Striche';
  }

  static String _formatMoney(double value) {
    return '${value.toStringAsFixed(2).replaceAll('.', ',')} €';
  }

  static String? _formatBool(dynamic value) {
    if (value == null) {
      return null;
    }

    return value == true ? 'Ja' : 'Nein';
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value.trim());
    }

    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.').trim());
    }

    return null;
  }

  static String? _readNullableString(dynamic value) {
    if (value is! String) {
      return null;
    }

    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      return null;
    }

    return trimmedValue;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _readMap(dynamic value) {
    if (value is! Map) {
      return null;
    }

    return Map<String, dynamic>.from(value);
  }
}
