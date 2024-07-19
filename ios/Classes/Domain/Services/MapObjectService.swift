//
//  IconsService.swift
//  dgis_maps_flutter
//
//  Created by Михаил Колчанов on 19.01.2023.
//

import DGis
import CoreLocation

final class MapObjectService {
    
    
    enum MarkerSize: UInt {
        case small
        case medium
        case big
        
        mutating func next() {
            self = MarkerSize(rawValue: self.rawValue + 1) ?? .small
        }
        
        var scale: UIImage.SymbolScale {
            switch self {
            case .small: return .small
            case .medium: return .medium
            case .big: return .large
            }
        }
        
    }
    
    private struct TypeSize: Hashable {
        let image: UIImage
        let size: MarkerSize
    }
    
    
    @Published var size: MarkerSize = .medium
    
    private let imageFactory: IImageFactory
    private let mapFactory: IMapFactory
    private let context: DGis.Context
    private var routeSearchCancellable: Cancellable?
    private var navigationManager: NavigationManager
    private var currentRoute: TrafficRoute?
    private var navigationView: INavigationView?
    private var routeMapObjectSource: RouteMapObjectSource
    private let flutterApi: PluginFlutterApi

    private var currentPosition: RoutePoint?
    private var remainingDistance: String?
    private var markers: [String: DGis.Marker] = [:]
    
    // private lazy var mapObjectManager: MapObjectManager = MapObjectManager(map: self.mapFactory.map)
    private lazy var mapObjectManager: MapObjectManager = MapObjectManager.withClustering(
        map: self.mapFactory.map,
        logicalPixel: LogicalPixel(80.0),
        maxZoom: Zoom(19.0),
        clusterRenderer: SimpleClusterRendererImpl(image: makeClusteringIcon())
      )
    private lazy var myLocationSource: MyLocationMapObjectSource = MyLocationMapObjectSource(
        context: context,
        directionBehaviour: .followMagneticHeading
//         controller: MyLocationController(bearingSource: .magnetic)
    )
    private var icons: [TypeSize: DGis.Image] = [:]
    
    
    init(dgisSdkService: DGisSdkService, flutterApi: PluginFlutterApi) {
        self.imageFactory = try! DGisSdkService.sdk.makeImageFactory()
        self.mapFactory = dgisSdkService.mapFactory
        self.context = try! DGisSdkService.sdk.context
        self.flutterApi = flutterApi

        self.routeMapObjectSource = RouteMapObjectSource(context: self.context, routeVisualizationType: .normal)
        mapFactory.map.addSource(source: routeMapObjectSource)

        self.navigationManager = try! NavigationManager(platformContext: self.context)
        self.navigationManager.mapManager.addMap(map: self.mapFactory.map)

        let mapView = mapFactory.mapView

        let navigationViewFactory = try! DGisSdkService.sdk.makeNavigationViewFactory()

        let navigationView = navigationViewFactory.makeNavigationView(
            map: mapFactory.map,
            navigationManager: self.navigationManager
        )

        // mapView.addSubview(navigationView)
        // navigationView.frame = CGRect(x: 0, y: 0, width: mapView.frame.size.width, height: mapView.frame.size.height)
        // navigationView.translatesAutoresizingMaskIntoConstraints = false
        // NSLayoutConstraint.activate([
        //     navigationView.topAnchor.constraint(equalTo: mapView.topAnchor),
        //     navigationView.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
        //     navigationView.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
        //     navigationView.heightAnchor.constraint(equalTo: mapView.bottomAnchor)
        // ])
    }
    
    func toggleSelfMarker(isVisible: Bool) {
        let containsMarker = self.mapFactory.map.sources.contains(myLocationSource)
        if (isVisible && !containsMarker) {
            self.mapFactory.map.addSource(source: myLocationSource)
        } else if (containsMarker) {
            self.mapFactory.map.removeSource(source: myLocationSource)
        }
    }
    
    
    func updateMarkers(markerUpdates: DataMarkerUpdates) {
         mapObjectManager.removeObjects(objects: Array(markers.values))
         markers.removeAll()

         for markerData in markerUpdates.toAdd {
             if let data = markerData {
                 let newMarker = data2Marker(data: data)
                 markers[data.markerId!.value] = newMarker
                 if let marker = newMarker {
                     mapObjectManager.addObject(item: marker)
                 }
             }
         }
    }

    func removeAllMarkers() {
        self.mapObjectManager.removeAll();
    }

    func removeMarker(marker: DataMarker) {
        if let markerToRemove = markers[marker.markerId.value] {
            mapObjectManager.removeObject(item: markerToRemove)
            markers.removeValue(forKey: marker.markerId.value)
        }
    }
    
    private func data2Marker(data: DataMarker) -> DGis.Marker {
        let icon = data.bitmap == nil ? nil : makeIcon(bitmap: data.bitmap!, size: MarkerSize.medium)
        return try! DGis.Marker(
            options: MarkerOptions(
                position: GeoPointWithElevation(
                    latitude: Latitude(floatLiteral: data.position.latitude),
                    longitude: Longitude(floatLiteral: data.position.longitude)
                ),
                icon: icon,
                text: data.infoText
            )
        )
    }
    
    
    private func makeIcon(bitmap: DataMarkerBitmap, size: MarkerSize) -> DGis.Image? {
        let image = UIImage(data: Data(bitmap.bytes.data))
        if (image != nil) {
            let typeSize = TypeSize(image: image!, size: size)
            if let icon = self.icons[typeSize] {
                return icon
            } else if let scaledImage = image!.applyingSymbolConfiguration(.init(scale: size.scale)) {
                let icon = self.imageFactory.make(image: scaledImage)
                self.icons[typeSize] = icon
                return icon
            }
        }
        return nil
    }
    
    func updatePolylines(polylineUpdates: DataPolylineUpdates) {
        let toAdd = polylineUpdates.toAdd.filter({ line in
            line != nil
        }).map { data2Polyline(data: $0!) }
        let toRemove = polylineUpdates.toRemove.filter({ line in
            line != nil
        }).map { data2Polyline(data: $0!) }
        self.mapObjectManager.removeAndAddObjects(
            objectsToRemove: toRemove,
            objectsToAdd: toAdd
        )
    }
    
    private func data2Polyline(data: DataPolyline) -> DGis.Polyline {
        var points = [DGis.GeoPoint]()
        data.points.forEach(
            { p in
                if (p != nil) {
                    points.append(
                        DGis.GeoPoint(
                            latitude: p!.latitude,
                            longitude: p!.longitude
                        )
                    )
                }
            }
        )
        let options = DGis.PolylineOptions(
            points: points,
            width: LogicalPixel(value: Float(data.width)),
            color: DGis.Color(argb: UInt32(data.color))
        )
        return try! DGis.Polyline(options: options)
    }
    
    func removeAll() {
        self.mapObjectManager.removeAll()
    }

    private func makeClusteringIcon() -> DGis.Image {
        let imageSize = CGSize(width: 32, height: 32)
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let whiteCircleImage = renderer.image { context in
            let inset: CGFloat = 3.0
            let rect = CGRect(x: inset, y: inset, width: imageSize.width - 2 * inset, height: imageSize.height - 2 * inset)
            let path = UIBezierPath(ovalIn: rect)
            UIColor.white.setFill()
            path.fill()
            UIColor(red: 0x57/255.0, green: 0x75/255.0, blue: 0xF1/255.0, alpha: 1.0).setStroke()
            let strokeWidth = 3.0
            path.lineWidth = CGFloat(strokeWidth + strokeWidth / 2)
            path.stroke()
        }
        return self.imageFactory.make(image: whiteCircleImage)
    }

    func createRoute(startPoint: DGis.GeoPoint, endPoint: DGis.GeoPoint) {
        let point1 = RouteSearchPoint(coordinates: startPoint)
        let point2 = RouteSearchPoint(coordinates: endPoint)

        let routeSearchOptions = RouteSearchOptions.car(CarRouteSearchOptions())
        let trafficRouter = TrafficRouter(context: context)
        let routesFuture = trafficRouter.findRoute(
            startPoint: point1,
            finishPoint: point2,
            routeSearchOptions: routeSearchOptions
        )
        
        self.routeMapObjectSource.clear()
        
        self.routeSearchCancellable = routesFuture.sink { routes in
            for (index, route) in routes.enumerated() {
                self.currentRoute = route
                let routeMapObject = RouteMapObject(
//                     trafficRoute: route,
                    route: route,
                    isActive: index == 0,
                    index: RouteIndex(value: UInt64(index)),
                    displayFlags: nil
                )
                
                self.routeMapObjectSource.addObject(item: routeMapObject)

                if index == 0 {
                    break
                }
            }
        } failure: { error in
            print("Не удалось найти маршрут: \(error)")
        }
    }

    func startNavigation(endPoint: DGis.GeoPoint) {
        guard let currentRoute = self.currentRoute else {
            return
        }

        let routeBuildOptions = RouteBuildOptions(
            finishPoint: RouteSearchPoint(coordinates: endPoint),
            routeSearchOptions: RouteSearchOptions.car(CarRouteSearchOptions())
        )

        do {
            try self.navigationManager.voiceSelector.voice = nil
            // try self.navigationManager.startSimulation(routeBuildOptions: routeBuildOptions, trafficRoute: currentRoute)
            try self.navigationManager.start(routeBuildOptions: routeBuildOptions)

            self.navigationManager.uiModel.routePositionChannel.sink { position in
                if let position = position {
                    self.currentPosition = position
                    self.remainingDistance = self.convertMillimetersToKilometers(
                        millimeters: self.navigationManager.uiModel.route.route.geometry.length.millimeters - position.distance.millimeters)
                }
            }

            self.navigationManager.uiModel.dynamicRouteInfoChannel.sink { info in
                if let routePoint = self.currentPosition {
                    let durationString = self.formatTimeInterval(info.traffic.durations.calculateDuration(routePoint: routePoint))
                    if let distance = self.remainingDistance {
                        self.flutterApi.onRoutePositionChanged(duration: durationString, distance: "\(distance)"){}
                    }
                }
            }
        } catch {
            self.flutterApi.onCatchErrorMessage(message: "Failed to start navigation: \(error)"){}
            print("Failed to start navigation: \(error)")
        }
    }

    func convertMillimetersToKilometers(millimeters: Int64) -> String {
        let kilometers = Double(millimeters) / 1_000_000.0
        return String(format: "%.1f", kilometers)
    }

    func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    func stopNavigation(){
        navigationManager.stop()
    }
}
