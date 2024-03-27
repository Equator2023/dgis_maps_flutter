package pro.flown.dgis_maps_flutter

import android.content.Context
import android.util.Log
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import ru.dgis.sdk.DGis
import ru.dgis.sdk.Duration
import ru.dgis.sdk.coordinates.Bearing
import ru.dgis.sdk.demo.CustomCompassManager
import ru.dgis.sdk.demo.CustomLocationManager
import ru.dgis.sdk.directory.SearchManager
import ru.dgis.sdk.directory.SearchQueryBuilder
import ru.dgis.sdk.geometry.ComplexGeometry
import ru.dgis.sdk.geometry.PointGeometry
import ru.dgis.sdk.map.*
import ru.dgis.sdk.map.Map
import ru.dgis.sdk.positioning.registerPlatformLocationSource
import ru.dgis.sdk.positioning.registerPlatformMagneticSource
import ru.dgis.sdk.routing.*
import ru.dgis.sdk.coordinates.GeoPoint

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Bitmap.Config
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import androidx.core.content.ContextCompat



class DgisMapController internal constructor(
        id: Int,
        context: Context,
        args: Any?,
        binaryMessenger: BinaryMessenger,
) : PlatformView, PluginHostApi {
    private val sdkContext: ru.dgis.sdk.Context
    private val flutterApi = PluginFlutterApi(binaryMessenger, id)
    private val mapView: MapView
    private var methodChannel: MethodChannel
    private lateinit var map: Map
    private lateinit var objectManager: MapObjectManager
    private lateinit var routeEditor: RouteEditor
    private lateinit var trafficRouter: TrafficRouter
    private lateinit var routeMapObjectSource: RouteMapObjectSource
    private var myLocationSource: MyLocationMapObjectSource? = null
    private lateinit var cameraStateConnection: AutoCloseable
    private lateinit var dataLoadingConnection: AutoCloseable

    init {
        sdkContext = DGis.initialize(context.applicationContext)
        val compassSource = CustomCompassManager(context.applicationContext)
        registerPlatformMagneticSource(sdkContext, compassSource)
        val locationSource = CustomLocationManager(context.applicationContext)
        registerPlatformLocationSource(sdkContext, locationSource)

        // Создаем канал для общения..
        methodChannel = MethodChannel(binaryMessenger, "fgis")
//        methodChannel.setMethodCallHandler(this)

        val params = DataCreationParams.fromList(args as List<Any?>)
        mapView = MapView(context, MapOptions().also {
            it.position = CameraPosition(
                    toGeoPoint(params.position), Zoom(params.zoom.toFloat())
            )
            val lightTheme = "day"
            val darkTheme = "night"
            when (params.mapTheme) {
                DataMapTheme.AUTO -> it.setTheme(lightTheme, darkTheme)
                DataMapTheme.DARK -> it.setTheme(darkTheme)
                DataMapTheme.LIGHT -> it.setTheme(lightTheme)
            }
        })
        PluginHostApi.setUp(binaryMessenger, id, this)

        mapView.getMapAsync { init(it) }

        mapView.setTouchEventsObserver(object : TouchEventsObserver {
            override fun onTap(point: ScreenPoint) {
                var isMarkerTapped = false;
                map.getRenderedObjects(point, ScreenDistance(1f)).onResult {
                    for (renderedObjectInfo in it) {
                        if (renderedObjectInfo.item.item.userData != null) {
                            val args = mapOf(
                                    "id" to renderedObjectInfo.item.item.userData
                            )

                            Log.d("DGIS", "нажатие на камеру")

                            methodChannel.invokeMethod(
                                    "ontap_marker",
                                    args
                            )
                            isMarkerTapped = true;
                        }
                    }
//                    if (!isMarkerTapped) {
//                        methodChannel.invokeMethod(
//                            "ontap_map",
//                            {},
//                        )
//                    }
                }
                super.onTap(point)
            }
        })
    }

    override fun getView(): View {
        return mapView
    }

    override fun dispose() {
        cameraStateConnection.close()
    }

    private fun init(map: Map) {
        this.map = map
        dataLoadingConnection = map.dataLoadingStateChannel.connect {
            if (it == MapDataLoadingState.LOADED) {
                flutterApi.onNativeMapReady { }
                dataLoadingConnection.close()
            }
        }
        cameraStateConnection = map.camera.stateChannel.connect {
            flutterApi.onCameraStateChanged(toDataCameraStateValue(it)) {}
        }
        routeEditor = RouteEditor(sdkContext)
        trafficRouter = TrafficRouter(sdkContext)
        routeMapObjectSource = RouteMapObjectSource(sdkContext, RouteVisualizationType.NORMAL)
        map.addSource(routeMapObjectSource)
        val routeEditorSource = RouteEditorSource(sdkContext, routeEditor)
        map.addSource(routeEditorSource)
        objectManager = MapObjectManager(map)

//        val searchManager = SearchManager.createOnlineManager(sdkContext)
//        searchManager.search(SearchQueryBuilder.fromQueryText("осенний").build()).onResult {
//            it.itemMarkerInfos.onResult { it ->
//                Log.v("searchMarkers", it.toString())
//            }
//            Log.v("onSearch", it.toString())
//        }
    }

    override fun changeMyLocationLayerState(isVisible: Boolean) {
        myLocationSource = myLocationSource ?: MyLocationMapObjectSource(
                sdkContext,
                MyLocationDirectionBehaviour.FOLLOW_SATELLITE_HEADING,
                createSmoothMyLocationController()
        )
        val isMyLocationVisible = map.sources.contains(myLocationSource!!)
        if (isVisible && !isMyLocationVisible) {
            map.addSource(myLocationSource!!)
        } else if (!isVisible && isMyLocationVisible) {
            map.removeSource(myLocationSource!!)
        }
    }

    override fun getCameraPosition(): DataCameraPosition {
        return DataCameraPosition(
                target = toDataLatLng(map.camera.position.point),
                zoom = map.camera.position.zoom.value.toDouble(),
                bearing = map.camera.position.bearing.value,
                tilt = map.camera.position.tilt.value.toDouble(),
        )
    }

    override fun moveCamera(
            cameraPosition: DataCameraPosition,
            duration: Long?,
            cameraAnimationType: DataCameraAnimationType,
            callback: () -> Unit,
    ) {
        map.camera.move(
                CameraPosition(
                        point = toGeoPoint(cameraPosition.target),
                        zoom = Zoom(cameraPosition.zoom.toFloat()),
                        tilt = Tilt(cameraPosition.tilt.toFloat()),
                        bearing = Bearing(cameraPosition.bearing),
                ), time = Duration.ofMilliseconds(duration ?: 100),
                animationType = toAnimationType(cameraAnimationType)
        ).onResult { callback() }
    }

    override fun getVisibleArea(): DataLatLngBounds {
        return geoRectToBounds(map.camera.visibleArea.bounds);
    }

    override fun moveCameraToBounds(
            firstPoint: DataLatLng,
            secondPoint: DataLatLng,
            padding: DataPadding,
            duration: Long?,
            cameraAnimationType: DataCameraAnimationType,
            callback: () -> Unit,
    ) {
        val geometry = ComplexGeometry(
                listOf(
                        PointGeometry(toGeoPoint(firstPoint)), PointGeometry(toGeoPoint(secondPoint))
                )
        )
        val position = calcPosition(
                map.camera, geometry, toPadding(padding)
        )
        map.camera.move(
                position, time = Duration.ofMilliseconds(duration ?: 100),
                animationType = toAnimationType(cameraAnimationType)
        ).onResult { callback() }
    }

    override fun updateMarkers(updates: DataMarkerUpdates) {
        objectManager.removeObjects(updates.toRemove.map { toMarker(sdkContext, it!!) })
        objectManager.addObjects(updates.toAdd.map { toMarker(sdkContext, it!!) })
    }

    override fun createRoute(startPoint: DataGeoPoint, endPoint: DataGeoPoint) {

        val startPointGeo = toGeoPoint(startPoint)
        val endPointGeo = toGeoPoint(endPoint)

        // Ищем маршрут
        val routesFuture = trafficRouter.findRoute(
            startPoint = RouteSearchPoint(coordinates = startPointGeo),
            finishPoint = RouteSearchPoint(coordinates = endPointGeo),
            routeSearchOptions = RouteSearchOptions(car = CarRouteSearchOptions())
        )

        // После получения маршрута добавляем его на карту

        routesFuture.onResult { routes: List<TrafficRoute> ->
            if (routes.isNotEmpty()) {
//                 Очищаем предыдущие маршруты
                routeMapObjectSource.clear()

                // Добавляем новый маршрут на карту
                // Все маршруты
//                routes.forEachIndexed { index, route ->
//                    val routeMapObject =
//                        RouteMapObject(route, isActive = true, index = RouteIndex(index.toLong()))
//                    routeMapObjectSource.addObject(routeMapObject)
//                }

                val routeMapObject = RouteMapObject(routes.first(), isActive = true, index = RouteIndex(0))
                routeMapObjectSource.addObject(routeMapObject)
            }
        }

//        -----------
        // Ищем маршрут
//        val routesFuture = trafficRouter.findRoute(
//                startPoint = RouteSearchPoint(
//                        coordinates = toGeoPoint(startPoint)
//                ),
//                finishPoint = RouteSearchPoint(
//                        coordinates = toGeoPoint(endPoint)
//                ),
//                routeSearchOptions = RouteSearchOptions(
//                        car = CarRouteSearchOptions()
//                )
//        )
//
//        // После получения маршрута добавляем его на карту
//        routesFuture.onResult { routes: List<TrafficRoute> ->
//            var isActive = true
//            var routeIndex: Long = 0;
//            for (route in routes) {
//                routeMapObjectSource.addObject(
//                        RouteMapObject(route, isActive, index = RouteIndex(routeIndex))
//                )
//                isActive = false
//                routeIndex++
//            }
//        }
//        -------------
//        routeEditor.setRouteParams(
//                RouteEditorRouteParams(
//                        startPoint = RouteSearchPoint(
//                                coordinates = toGeoPoint(startPoint)
//                        ),
//                        finishPoint = RouteSearchPoint(
//                                coordinates = toGeoPoint(endPoint)
//                        ),
//                        routeSearchOptions = RouteSearchOptions(
//                                car = CarRouteSearchOptions()
//                        )
//                )
//        )
    }

    override fun updatePolylines(updates: DataPolylineUpdates) {
        objectManager.removeObjects(updates.toRemove.map { toPolyline(it!!) })
        objectManager.addObjects(updates.toAdd.map { toPolyline(it!!) })
    }

    override fun clusteringMarkers() {
        val clusterRenderer = object : SimpleClusterRenderer {
            override fun renderCluster(cluster: SimpleClusterObject): SimpleClusterOptions {
                val textStyle = TextStyle(
                    fontSize = LogicalPixel(15.0f),
                    textPlacement = TextPlacement.CENTER_CENTER
                )
                val objectCount = cluster.objectCount
                val iconMapDirection = if (objectCount < 5) MapDirection(45.0) else null
                return SimpleClusterOptions(
                    icon = makeClusteringIcon(context = sdkContext),
//                    icon = imageFromResource(context = sdkContext, resourceId = R.drawable.dgis_ic_road_event_marker_comment),
                    iconWidth = LogicalPixel(30.0f),
                    text = objectCount.toString(),
                    textStyle = textStyle,
                    iconMapDirection = iconMapDirection,
                    userData = objectCount.toString()
                )
            }
        }

        objectManager = MapObjectManager.withClustering(map, LogicalPixel(80.0f), Zoom(18.0f), clusterRenderer)
    }

    fun makeClusteringIcon(context: ru.dgis.sdk.Context): Image? {
        val imageSize = Pair(42.0f, 42.0f)
        val whiteCircleBitmap = createWhiteCircleBitmap(imageSize)
        return whiteCircleBitmap?.let { imageFromBitmap(context, it) }
    }

    fun createWhiteCircleBitmap(size: Pair<Float, Float>): Bitmap {
        val bitmap = Bitmap.createBitmap(size.first.toInt(), size.second.toInt(), Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val inset = 2.0f
        val rect = RectF(inset, inset, size.first - 2 * inset, size.second - 2 * inset)
        val paint = Paint().apply {
            isAntiAlias = true
            style = Paint.Style.FILL
            color = Color.WHITE
        }
        canvas.drawOval(rect, paint)
        paint.style = Paint.Style.STROKE
        paint.color = Color.parseColor("#5775F1")
        paint.strokeWidth = 3.0f
        canvas.drawOval(rect, paint)
        return bitmap
    }
}