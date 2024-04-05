import Foundation

class Converter {
    static func toGeoPoint(lat: Double, lng: Double) -> GeoPoint {
        return GeoPoint(latitude: lat, longitude: lng)
    }
}