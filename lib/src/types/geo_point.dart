class GeoPoint1 {
  GeoPoint1({
    required this.latitude,
    required this.longitude,
  });

  /// Координата долготы
  double latitude;

  /// Координата широты
  double longitude;

  Object encode() {
    return <Object?>[
      latitude,
      longitude,
    ];
  }

  static GeoPoint1 decode(Object result) {
    result as List<Object?>;
    return GeoPoint1(
      latitude: result[0]! as double,
      longitude: result[1]! as double,
    );
  }
}
