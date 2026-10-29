import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:bagoo_buyer_mobile/main.dart' as buyer;

import 'preview/buyer_device_preview.dart';

/// Desktop layout tooling is opt-in through this debug entrypoint.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || !Platform.isLinux) {
    buyer.main();
    return;
  }
  final appKey = GlobalKey();
  runApp(
    BuyerDevicePreview(
      builder: (context) => buyer.MainApp(
        key: appKey,
        theme: Theme.of(context),
        scrollBehavior: ScrollConfiguration.of(context),
      ),
    ),
  );
}
