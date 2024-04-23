import 'dart:convert';
import 'dart:math';

import 'package:dgis_maps_flutter/dgis_maps_flutter.dart';
import 'package:example/core/map_markers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  runApp(const MyApp());
  checkPermission();
}

void checkPermission() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return;
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DGis Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int i = 0;
  int mId = 0;
  bool isShrinked = false;
  bool isShrinkedTop = false;
  late DGisMapController controller;
  bool myLocationEnabled = true;

  Set<Marker> markers = {};
  Set<Polyline> polylines = {};

  bool isNavigationActive = false;
  String remainingDistance = '';
  String remainingDuration = '';

  List<LatLng> points = [
    LatLng(43.24103142234661, 76.91515532883092),
    LatLng(43.24553402103508, 76.90073286394733),
    LatLng(43.23461335020524, 76.86520955142616),
    LatLng(43.23005817922267, 76.93661140959371),
    LatLng(43.22498497447905, 76.93519047709287),
    LatLng(43.25665970536574, 76.90037763082212),
    LatLng(43.25960896456512, 76.86584897105155),
  ];

  void onMapCreated(DGisMapController controller) {
    this.controller = controller;
  }

  void shrinkMapTop() {
    setState(() => isShrinkedTop = !isShrinkedTop);
  }

  void shrinkMap() {
    setState(() => isShrinked = !isShrinked);
  }

  void moveMap() {
    isShrinkedTop = !isShrinkedTop;
    setState(() => isShrinked = !isShrinked);
  }

  Future<void> moveCamera() async {
    await controller.moveCamera(
      cameraPosition: CameraPosition(
        target: LatLng(43.24103142234661, 76.91515532883092),
        zoom: 14,
        bearing: 0,
        tilt: 0,
      ),
      duration: 1000,
      cameraAnimationType: CameraAnimationType.linear,
    );
  }

  Future<void> moveCameraToBounds() async {
    await controller.moveCameraToBounds(
      cameraPosition: LatLngBounds(
        southwest: LatLng(58, 28),
        northeast: LatLng(62, 32),
      ),
      padding: MapPadding.all(20),
      duration: 1000,
      cameraAnimationType: CameraAnimationType.showBothPositions,
    );
  }

  Future<void> getCameraPosition() async {
    final cameraPosition = await controller.getCameraPosition();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(cameraPosition.toString())));
  }

  Future<void> addMarker() async {
    // print(mId);
    if (mId < points.length) {
      markers.add(Marker(
        markerId: MapObjectId('m${mId}'),
        position: points[mId],
        infoText: 'm${mId}',
        bitmap: MarkerBitmap(
          bytes: selectedMarker,
          width: 50,
          height: 50,
        ),
      ));
      mId++;
    }

    setState(() {});
  }

  Future<void> addPolyline() async {
    polylines.add(
      Polyline(
        polylineId: MapObjectId('p${mId++}'),
        color: Colors.primaries[Random().nextInt(Colors.primaries.length)],
        points: List.generate(
          10,
          (index) => LatLng(60.0 + index + mId, 30.0 + index + mId),
        ),
        erasedPart: 0,
      ),
    );
    setState(() {});
  }

  void toggleMyLocation() async {
    if (!myLocationEnabled) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return; // GPS не активирован
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse &&
            permission != LocationPermission.always) {
          return; // Разрешение не предоставлено
        }
      }

      myLocationEnabled = true; // Активируем отображение местоположения
      Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .then((Position position) {
        controller.moveCamera(
          cameraPosition: CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16,
          ),
        );
        print("Current position: ${position.latitude}, ${position.longitude}");
      });
      setState(() {});
    } else {
      myLocationEnabled = false; // Деактивируем отображение местоположения
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    // getDirections();
    Geolocator.getServiceStatusStream().listen(
      (ServiceStatus status) {
        print("GPS Status: $status");
        if (status == ServiceStatus.enabled && myLocationEnabled == false) {
          toggleMyLocation();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("DGis Map Example")),
      // floatingActionButton: FloatingActionButton(
      //   child: Text("iter\n$i"),
      //   onPressed: () => setState(() => i++),
      // ),
      body: Column(
        children: [
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: const SizedBox(height: 100),
            crossFadeState: !isShrinkedTop
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(seconds: 2),
          ),
          Expanded(
            child: DGisMap(
              key: ValueKey(i),
              myLocationEnabled: myLocationEnabled,
              initialPosition: CameraPosition(
                  target: LatLng(43.24103142234661, 76.91515532883092),
                  zoom: 9),
              onMapCreated: onMapCreated,
              markers: markers,
              polylines: polylines,
              onCameraStateChanged: (cameraState) {
                print(cameraState);
              },
              onTapMarker: (marker) {
                if (marker != null) {
                  print(marker.markerId.value);
                }
              },
              mapTheme: MapTheme.light,
              onClusterTapped: (markers) {
                print(markers);
              },
              onRoutePositionChanged: onRoutePositionChanged,
              onCatchErrorMessage: onCatchErrorMessage,
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(height: 0),
            secondChild: const SizedBox(height: 100),
            crossFadeState: !isShrinked
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(seconds: 2),
          ),
          isNavigationActive
              ? SizedBox(
                  height: 40,
                  child: Text(
                    'Оставшееся время: $remainingDuration,\nОставшееся расстояние: $remainingDistance',
                    textAlign: TextAlign.center,
                  ),
                )
              : const SizedBox.shrink(),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              height: 80,
              child: Row(
                children: [
                  TextButton(
                    onPressed: addMarker,
                    child: const Text('addMarker'),
                  ),
                  TextButton(
                    onPressed: toggleMyLocation,
                    child: Text(myLocationEnabled
                        ? "Disable My Location"
                        : "Enable My Location"),
                  ),
                  TextButton(
                    onPressed: () {
                      createRoute(LatLng(43.25665970536574, 76.90037763082212));
                    },
                    child: const Text('createRoute'),
                  ),
                  TextButton(
                    onPressed: () {
                      startNavigation(
                          LatLng(43.25665970536574, 76.90037763082212));
                    },
                    child: const Text('startNavigation'),
                  ),
                  TextButton(
                    onPressed: stopNavigation,
                    child: const Text('stopNavigation'),
                  ),
                  TextButton(
                    onPressed: moveCamera,
                    child: const Text('moveCamera'),
                  ),
                  TextButton(
                    onPressed: moveCameraToBounds,
                    child: const Text('moveCameraToBounds'),
                  ),
                  TextButton(
                    onPressed: getCameraPosition,
                    child: const Text('getCameraPosition'),
                  ),
                  TextButton(
                    onPressed: addPolyline,
                    child: const Text('addPolyline'),
                  ),
                  TextButton(
                    onPressed: shrinkMapTop,
                    child: const Text('shrinkMapTop'),
                  ),
                  TextButton(
                    onPressed: shrinkMap,
                    child: const Text('shrinkMap'),
                  ),
                  TextButton(
                    onPressed: moveMap,
                    child: const Text('moveMap'),
                  ),
                  const SizedBox(width: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void getDirections() async {
    var url = Uri.parse(
        'https://routing.api.2gis.com/carrouting/6.0.0/global?key=API_KEY');
    var response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'points': [
            {
              "type": "walking",
              "x": 43.2451643117112,
              "y": 76.83592641374008,
            },
            {
              "type": "walking",
              "x": 43.23046997709439,
              "y": 76.89557874085693,
            },
          ],
        },
      ),
    );
    print('Response status: ${response.statusCode}');
    print('Response body: ${response.body}');
  }

  void createRoute(LatLng endPoint) async {
    try {
      Position currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      GeoPoint startPoint = GeoPoint(
          latitude: currentPosition.latitude,
          longitude: currentPosition.longitude);
      GeoPoint destinationPoint =
          GeoPoint(latitude: endPoint.latitude, longitude: endPoint.longitude);

      await controller.createRoute(startPoint, destinationPoint);

      // Вычисление границ для отображения маршрута
      LatLngBounds routeBounds = LatLngBounds(
        southwest: LatLng(
          min(startPoint.latitude, destinationPoint.latitude),
          min(startPoint.longitude, destinationPoint.longitude),
        ),
        northeast: LatLng(
          max(startPoint.latitude, destinationPoint.latitude),
          max(startPoint.longitude, destinationPoint.longitude),
        ),
      );

      // Анимированное перемещение камеры, чтобы весь маршрут был виден
      await controller.moveCameraToBounds(
          cameraPosition: routeBounds, padding: MapPadding.all(50));
    } catch (e) {
      print("Error getting current position or creating route: $e");
    }
  }

  Future<void> startNavigation(LatLng endPoint) async {
    try {
      GeoPoint destinationPoint =
          GeoPoint(latitude: endPoint.latitude, longitude: endPoint.longitude);
      await controller.startNavigation(destinationPoint);
      isNavigationActive = true;
      setState(() {});
    } catch (e) {
      print("Error getting current position or starting navigation: $e");
    }
  }

  Future<void> stopNavigation() async {
    await controller.stopNavigation();
    isNavigationActive = false;
    setState(() {});
  }

  void onRoutePositionChanged(String duration, String distance) async {
    remainingDuration = duration;
    remainingDistance = distance;
    setState(() {});
  }

  void onCatchErrorMessage(String message) async {
    print(" ------------ $message");
  }
}
