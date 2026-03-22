enum GroupInvitePermission {
  onlyWarts('ONLY_WARTS'),
  allMembers('ALL_MEMBERS');

  final String jsonValue;

  const GroupInvitePermission(this.jsonValue);

  static GroupInvitePermission fromJsonValue(dynamic value) {
    switch (value?.toString().trim().toUpperCase()) {
      case 'ALL_MEMBERS':
        return GroupInvitePermission.allMembers;
      case 'ONLY_WARTS':
      default:
        return GroupInvitePermission.onlyWarts;
    }
  }
}

class GroupSettings {
  final String name;
  final double pricePerStrich;
  final bool onlyWartsCanBookForOthers;
  final bool allowArbitraryMoneySettlements;
  final GroupInvitePermission invitePermission;

  const GroupSettings({
    required this.name,
    required this.pricePerStrich,
    required this.onlyWartsCanBookForOthers,
    required this.allowArbitraryMoneySettlements,
    required this.invitePermission,
  });

  factory GroupSettings.fromJson(Map<String, dynamic> json) {
    return GroupSettings(
      name: (json['name'] ?? '').toString(),
      pricePerStrich: _toDouble(json['pricePerStrich']),
      onlyWartsCanBookForOthers: json['onlyWartsCanBookForOthers'] == true,
      allowArbitraryMoneySettlements:
          json['allowArbitraryMoneySettlements'] == true,
      invitePermission: GroupInvitePermission.fromJsonValue(
        json['invitePermission'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'pricePerStrich': pricePerStrich,
      'onlyWartsCanBookForOthers': onlyWartsCanBookForOthers,
      'allowArbitraryMoneySettlements': allowArbitraryMoneySettlements,
      'invitePermission': invitePermission.jsonValue,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.parse(value.toString());
  }
}
