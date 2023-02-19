import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:background_locator/background_locator.dart';
import 'package:background_locator/location_dto.dart';
import 'package:background_locator/settings/android_settings.dart';
import 'package:background_locator/settings/ios_settings.dart';
import 'package:background_locator/settings/locator_settings.dart';
// import 'package:background_locator_2/background_locator.dart';
// import 'package:background_locator_2/location_dto.dart';
// import 'package:background_locator_2/settings/android_settings.dart';
// import 'package:background_locator_2/settings/ios_settings.dart';
// import 'package:background_locator_2/settings/locator_settings.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';

import 'file_manager.dart';
import 'location_callback_handler.dart';
import 'location_service_repository.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ReceivePort port = ReceivePort();

  String logStr = '';
  bool isRunning = false;
  LocationDto? lastLocation;

  @override
  void initState() {
    super.initState();

    if (IsolateNameServer.lookupPortByName(
            LocationServiceRepository.isolateName) !=
        null) {
      IsolateNameServer.removePortNameMapping(
          LocationServiceRepository.isolateName);
    }

    IsolateNameServer.registerPortWithName(
        port.sendPort, LocationServiceRepository.isolateName);

    port.listen(
      (dynamic data) async {
        await updateUI(data);
      },
    );
    initPlatformState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> updateUI(dynamic data) async {
    final log = await FileManager.readLogFile();

    // await _updateNotificationText(data);
    LocationDto? locationDto = (data != null) ? LocationDto.fromJson(data) : null;
    await _updateNotificationText(locationDto!);

    setState(() {
      if (data != null) {
        // lastLocation = data;
        lastLocation = locationDto;
      }
      logStr = log;
    });
  }

  Future<void> _updateNotificationText(LocationDto data) async {
    if (data == null) {
      return;
    }

    await BackgroundLocator.updateNotificationText(
        title: "new location received",
        msg: "${DateTime.now()}",
        bigMsg: "${data.latitude}, ${data.longitude}");
  }

  Future<void> initPlatformState() async {
    print('Initializing...');
    await BackgroundLocator.initialize();
    logStr = await FileManager.readLogFile();
    print('Initialization done');
    final isRunning = await BackgroundLocator.isServiceRunning();
    setState(() {
      this.isRunning = isRunning;
    });
    print('Running ${isRunning.toString()}');
  }

  @override
  Widget build(BuildContext context) {
    final start = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: const Text('Start'),
        onPressed: () {
          _onStart();
        },
      ),
    );
    final stop = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: const Text('Stop'),
        onPressed: () {
          onStop();
        },
      ),
    );
    final clear = SizedBox(
      width: double.maxFinite,
      child: ElevatedButton(
        child: const Text('Clear Log'),
        onPressed: () {
          FileManager.clearLogFile();
          setState(() {
            logStr = '';
          });
        },
      ),
    );
    String msgStatus = "-";
    if (isRunning != null) {
      if (isRunning) {
        msgStatus = 'Is running';
      } else {
        msgStatus = 'Is not running';
      }
    }
    final status = Text("Status: $msgStatus");

    final log = Text(
      logStr,
    );

    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter background Locator'),
        ),
        body: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[start, stop, clear, status, log],
            ),
          ),
        ),
      ),
    );
  }

  void onStop() async {
    await BackgroundLocator.unRegisterLocationUpdate();
    final isRunning = await BackgroundLocator.isServiceRunning();
    setState(() {
      this.isRunning = isRunning;
    });
  }

  void _onStart() async {
    if (await _checkLocationPermission()) {
      await _startLocator();
      final isRunning = await BackgroundLocator.isServiceRunning();

      setState(() {
        this.isRunning = isRunning;
        lastLocation = null;
      });
    } else {
      // show error
    }
  }

  Future<bool> _checkLocationPermission() async {
    if (Platform.isAndroid) {
      final access = await Permission.locationAlways.request();
      print(access);
      if (access == PermissionStatus.granted) {
        return true;
      } else {
        await openAppSettings();
        return false;
      }
    } else if (Platform.isIOS) {
      final access = await geo.Geolocator.requestPermission();
      print(access);
      if (access != geo.LocationPermission.always) {
        await openAppSettings();
        return false;
      } else {
        return true;
      }
    }
    return true;
  }

  Future<void> _startLocator() async {
    Map<String, dynamic> data = {'countInit': 1};
    return await BackgroundLocator.registerLocationUpdate(
        LocationCallbackHandler.callback,
        initCallback: LocationCallbackHandler.initCallback,
        initDataCallback: data,
        disposeCallback: LocationCallbackHandler.disposeCallback,
        iosSettings: const IOSSettings(
          accuracy: LocationAccuracy.NAVIGATION,
          distanceFilter: 0,
          showsBackgroundLocationIndicator: true,
        ),
        autoStop: false,
        androidSettings:  const AndroidSettings(
            accuracy: LocationAccuracy.NAVIGATION,
            interval: 1,
            distanceFilter: 0,
            client: LocationClient.google,
            androidNotificationSettings: AndroidNotificationSettings(
                notificationChannelName: 'Location tracking',
                notificationTitle: 'Start Location Tracking',
                notificationMsg: 'Track location in background',
                notificationBigMsg:
                    'Background location is on to keep the app up-tp-date with your location. This is required for main features to work properly when the app is not running.',
                notificationIconColor: Colors.grey,
                notificationTapCallback:
                    LocationCallbackHandler.notificationCallback)));
  }
}
