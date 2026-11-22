class RestaurantSettings {
  const RestaurantSettings({
    required this.name,
    required this.isOpen,
    required this.hours,
    required this.whatsapp,
    required this.address,
    required this.currency,
  });

  final String name;
  final bool isOpen;
  final String hours;
  final String whatsapp;
  final String address;
  final String currency;

  static const defaults = RestaurantSettings(
    name: 'Restaurante Manía',
    isOpen: true,
    hours: '11:00 - 22:00',
    whatsapp: '+57 300 123 4567',
    address: 'Calle 10 # 43-12, Medellín',
    currency: 'COP',
  );

  RestaurantSettings copyWith({
    String? name,
    bool? isOpen,
    String? hours,
    String? whatsapp,
    String? address,
    String? currency,
  }) {
    return RestaurantSettings(
      name: name ?? this.name,
      isOpen: isOpen ?? this.isOpen,
      hours: hours ?? this.hours,
      whatsapp: whatsapp ?? this.whatsapp,
      address: address ?? this.address,
      currency: currency ?? this.currency,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'isOpen': isOpen,
        'hours': hours,
        'whatsapp': whatsapp,
        'address': address,
        'currency': currency,
      };

  factory RestaurantSettings.fromJson(Map<String, dynamic> json) =>
      RestaurantSettings(
        name: json['name'] as String? ?? defaults.name,
        isOpen: json['isOpen'] as bool? ?? defaults.isOpen,
        hours: json['hours'] as String? ?? defaults.hours,
        whatsapp: json['whatsapp'] as String? ?? defaults.whatsapp,
        address: json['address'] as String? ?? defaults.address,
        currency: json['currency'] as String? ?? defaults.currency,
      );
}
