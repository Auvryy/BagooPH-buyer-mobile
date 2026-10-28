import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

import 'web_session.dart';

typedef BuyerLocation = ({double latitude, double longitude, double accuracy});

Future<BuyerLocation> captureBuyerLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const BackendException(
      'Turn on location services or enter coordinates manually.',
    );
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const BackendException(
      'Location permission is unavailable. You can still enter coordinates manually.',
    );
  }
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  } catch (_) {
    throw const BackendException(
      'Your location could not be captured. Try again or enter coordinates manually.',
    );
  }
}

Future<void> shareBuyerProduct(
  BuildContext context,
  Uri uri,
  String name,
) async {
  if (!Platform.isAndroid &&
      !Platform.isIOS &&
      !Platform.isMacOS &&
      !Platform.isWindows) {
    throw const BackendException(
      'System sharing is unavailable in this preview. Use Copy link.',
    );
  }
  final render = context.findRenderObject();
  final bounds = render is RenderBox
      ? render.localToGlobal(Offset.zero) & render.size
      : null;
  await SharePlus.instance.share(
    ShareParams(
      text: '$name\n$uri',
      title: name,
      subject: name,
      sharePositionOrigin: bounds,
    ),
  );
}
