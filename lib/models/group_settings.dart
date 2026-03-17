class GroupSettings {
  final String name;
  final double pricePerStrich;
  final bool onlyWartsCanBookForOthers;

  const GroupSettings({
    required this.name,
    required this.pricePerStrich,
    required this.onlyWartsCanBookForOthers,
  });

  factory GroupSettings.fromJson(Map<String, dynamic> json) {
    return GroupSettings(
      name: (json['name'] ?? '').toString(),
      pricePerStrich: _toDouble(json['pricePerStrich']),
      onlyWartsCanBookForOthers: json['onlyWartsCanBookForOthers'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'pricePerStrich': pricePerStrich,
      'onlyWartsCanBookForOthers': onlyWartsCanBookForOthers,
    };
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.parse(value.toString());
  }
}
