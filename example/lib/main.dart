import 'dart:math';

import 'package:dgis_maps_flutter/dgis_maps_flutter.dart';
import 'package:example/core/map_markers.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
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
    print(mId);
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

  void toggleMyLocation() {
    setState(() {
      myLocationEnabled = !myLocationEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
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
              onTapMarker: (marker) {},
              mapTheme: MapTheme.light,
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
          Row(
            children: [
              Expanded(
                child: Wrap(
                  children: [
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
                      onPressed: addMarker,
                      child: const Text('addMarker'),
                    ),
                    TextButton(
                      onPressed: addPolyline,
                      child: const Text('addPolyline'),
                    ),
                    TextButton(
                      onPressed: toggleMyLocation,
                      child: const Text('toggleMyLocation'),
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
                  ],
                ),
              ),
              const SizedBox(width: 100),
            ],
          ),
        ],
      ),
    );
  }
}
