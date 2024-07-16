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
import ru.dgis.sdk.positioning.*
import ru.dgis.sdk.routing.*
import ru.dgis.sdk.coordinates.GeoPoint
import ru.dgis.sdk.navigation.*

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
import android.view.ViewGroup

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
    private lateinit var navigationManager: NavigationManager
    private lateinit var routeMapObjectSource: RouteMapObjectSource
    private lateinit var cameraStateConnection: AutoCloseable
    private lateinit var dataLoadingConnection: AutoCloseable
    private lateinit var navigationView: NavigationView


    private var myLocationSource: MyLocationMapObjectSource? = null
    private var currentRoute: TrafficRoute? = null
    private var currentPosition: RoutePoint? = null
    private var remainingDistance: String? = null

    private val markers = mutableMapOf<String, Marker>()

    init {
        sdkContext = DGis.initialize(context.applicationContext)
        val compassSource = CustomCompassManager(context.applicationContext)
        registerPlatformMagneticSource(sdkContext, compassSource)
        val locationSource = CustomLocationManager(context.applicationContext)
        registerPlatformLocationSource(sdkContext, locationSource)

        // Создаем канал для общения..
        methodChannel = MethodChannel(binaryMessenger, "fgis")

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
                        if (renderedObjectInfo.item.item is SimpleClusterObject) {
                            val cluster = renderedObjectInfo.item.item as SimpleClusterObject
                            val clusterObjects = cluster.objects.map {listOf((it as Marker).position.latitude.value, (it as Marker).position.longitude.value)}
                            val args = mapOf("objects" to clusterObjects)
                            methodChannel.invokeMethod("ontap_cluster", args)
                            break
                        }
                        else if (renderedObjectInfo.item.item.userData != null) {
                            val args = mapOf("id" to renderedObjectInfo.item.item.userData)
                            Log.d("DGIS", "нажатие на камеру")
                            methodChannel.invokeMethod("ontap_marker", args)
                            isMarkerTapped = true;
                        }
                    }
                }
                super.onTap(point)
            }
        })

        // Создаем NavigationView и добавляем элементы управления навигации
        navigationView = NavigationView(context.applicationContext)
        val navLayoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        navigationView.layoutParams = navLayoutParams

//        val defaultNavigationControls = DefaultNavigationControls(context.applicationContext)
//        val controlLayoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
//        navigationView.addView(defaultNavigationControls, controlLayoutParams)

        mapView.addView(navigationView, navLayoutParams)
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

        // Cluster Renderer
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
                    iconWidth = LogicalPixel(30.0f),
                    text = objectCount.toString(),
                    textStyle = textStyle,
                    iconMapDirection = iconMapDirection,
                    userData = objectCount.toString()
                )
            }
        }

        cameraStateConnection = map.camera.stateChannel.connect {
            flutterApi.onCameraStateChanged(toDataCameraStateValue(it)) {}
        }

        routeEditor = RouteEditor(sdkContext)
        trafficRouter = TrafficRouter(sdkContext)

        navigationManager = NavigationManager(sdkContext)
        navigationManager.voiceSelector.voice = null
        navigationView.navigationManager = navigationManager

        routeMapObjectSource = RouteMapObjectSource(sdkContext, RouteVisualizationType.NORMAL)
        map.addSource(routeMapObjectSource)
        val routeEditorSource = RouteEditorSource(sdkContext, routeEditor)
//        map.addSource(routeEditorSource)

        objectManager = MapObjectManager.withClustering(map, LogicalPixel(80.0f), Zoom(18.0f), clusterRenderer)
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
        objectManager.removeObjects(markers.values.toList())

        markers.clear()

        updates.toAdd.forEach { markerData ->
            val newMarker = toMarker(sdkContext, markerData!!)
            markers[markerData!!.markerId.value] = newMarker
            newMarker?.let { marker -> objectManager.addObject(marker)}
        }
    }


    override fun removeAllMarkers() {
        objectManager.removeAll();
    }

    override fun removeMarker(marker: DataMarker) {
        objectManager.removeObject(markers[marker.markerId.value]!!)
        markers.remove(marker.markerId.value)
    }

    override fun createRoute(startPoint: DataGeoPoint, endPoint: DataGeoPoint) {

        val startPointGeo = toGeoPoint(startPoint)
        val endPointGeo = toGeoPoint(endPoint)


        val routesFuture = trafficRouter.findRoute(
            startPoint = RouteSearchPoint(coordinates = startPointGeo),
            finishPoint = RouteSearchPoint(coordinates = endPointGeo),
            routeSearchOptions = RouteSearchOptions(car = CarRouteSearchOptions())
        )

        routesFuture.onResult { routes: List<TrafficRoute> ->
            if (routes.isNotEmpty()) {
                currentRoute = routes.first()
                routeMapObjectSource.clear()

                val routeMapObject = RouteMapObject(routes.first(), isActive = true, index = RouteIndex(0))
                routeMapObjectSource.addObject(routeMapObject)
            }
        }
    }

    override fun updatePolylines(updates: DataPolylineUpdates) {
        objectManager.removeObjects(updates.toRemove.map { toPolyline(it!!) })
        objectManager.addObjects(updates.toAdd.map { toPolyline(it!!) })
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

    override fun startNavigation(endPoint: DataGeoPoint) {
        val routeBuildOptions = RouteBuildOptions(
            /// Without route
            finishPoint = RouteSearchPoint(
                coordinates = toGeoPoint(endPoint)
            ),
            routeSearchOptions = RouteSearchOptions(
                car = CarRouteSearchOptions(
                    avoidTollRoads = true,
                    avoidUnpavedRoads = false,
                    avoidFerries = false,
                    routeSearchType = RouteSearchType.JAM
                )
            )
        )

        navigationManager.simulationSettings.speedMode = SimulationSpeedMode(SimulationConstantSpeed(200.0))
        currentRoute?.let { route ->
            /// Simulation
//            navigationManager.startSimulation(routeBuildOptions, route)
            /// Without route
            navigationManager.start(routeBuildOptions)
            /// With route
//            navigationManager.start(routeBuildOptions, route)
        }

        navigationManager.uiModel.routePositionChannel.connect { position ->
            position?.let {
                currentPosition = position
                remainingDistance = convertMillimetersToKilometers(navigationManager.uiModel.route.route.geometry.length.minus(position.distance).millimeters)
            }
        }

        navigationManager.uiModel.dynamicRouteInfoChannel.connect { info ->
            info?.let {
                currentPosition?.let { routePoint ->
                    val durationString = info.traffic.durations.calculateDuration(routePoint).toString()
                    remainingDistance?.let { distance ->
                        flutterApi.onRoutePositionChanged(durationString, distance){}
                    }
                }
            }
        }
    }

    fun convertMillimetersToKilometers(mm: Long): String {
        val kilometers = mm / 1000000.0
        return String.format("%.1f", kilometers)
    }

    override fun stopNavigation() {
        navigationManager.stop()
    }
}