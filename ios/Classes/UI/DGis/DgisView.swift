//
//  DgisView.swift
//  dgis_maps_flutter
//
//  Created by Михаил Колчанов on 13.01.2023.
//

import Flutter
import UIKit
import SwiftUI
import DGis


class DGisNativeView: NSObject, FlutterPlatformView {    
    
    private var _view: UIView
    private let flutterApi: PluginFlutterApi
    
    init(
        mapViewFactory: MapViewFactory,
        flutterApi: PluginFlutterApi
    ) {
        _view = UIView()
        self.flutterApi = flutterApi
        super.init()
        
        let mapView = mapViewFactory.makeMapViewWithMarkerViewOverlay(
        tapRecognizerCallback: _onMapTapCallback)
            .edgesIgnoringSafeArea([.top, .bottom])
        let controller = UIHostingController(rootView: mapView)
        _view = controller.view
        flutterApi.onNativeMapReady(completion: {})
    }
    
    func _onMapTapCallback(objectInfo : RenderedObjectInfo) {
        if let cluster = objectInfo.item.item as? SimpleClusterObject {
            var points: [[Double]] = []
            for obj in cluster.objects {
                if let marker = obj as? Marker {
                    let latitude = marker.position.latitude.value
                    let longitude = marker.position.longitude.value
                    points.append([latitude, longitude])
                }
            }

            self.flutterApi.onClusterObjectTapped(points: points, completion: {})
        }
        else{
            self.flutterApi.onMarkerTapped(point: [objectInfo.closestMapPoint.latitude.value, objectInfo.closestMapPoint.longitude.value], completion: {})
        }
    }
    
    func view() -> UIView {
        return _view
    }
}
