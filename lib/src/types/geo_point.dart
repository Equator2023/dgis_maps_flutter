import 'package:dgis_maps_flutter/src/method_channel.g.dart';

class GeoPoint extends DataGeoPoint {
  GeoPoint({
    required double latitude,
    required double longitude,
  }) : super(latitude: latitude, longitude: longitude);

  @override
  Object encode() {
    return <Object?>[
      latitude,
      longitude,
    ];
  }

  static GeoPoint decode(Object result) {
    result as List<Object?>;
    return GeoPoint(
      latitude: result[0]! as double,
      longitude: result[1]! as double,
    );
  }

  GeoPoint copyWith({
    double? latitude,
    double? longitude,
  }) =>
      GeoPoint(
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );
}
