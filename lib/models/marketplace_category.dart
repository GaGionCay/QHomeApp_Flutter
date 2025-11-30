class MarketplaceCategory {
  final String id;
  final String code;
  final String name;
  final String? nameEn;
  final String? icon;
  final int displayOrder;
  final bool active;

  MarketplaceCategory({
    required this.id,
    required this.code,
    required this.name,
    this.nameEn,
    this.icon,
    required this.displayOrder,
    required this.active,
  });

  factory MarketplaceCategory.fromJson(Map<String, dynamic> json) {
    return MarketplaceCategory(
      id: json['id']?.toString() ?? '',
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      nameEn: json['nameEn'],
      icon: json['icon'],
      displayOrder: json['displayOrder'] ?? 0,
      active: json['active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'nameEn': nameEn,
      'icon': icon,
      'displayOrder': displayOrder,
      'active': active,
    };
  }
}

