import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/viewport_visibility.dart';

class BuyerAdvertisementSession {
  BuyerAdvertisementSession(this.send);
  final Future<void> Function(Map<String, dynamic>, String) send;
  final _attempted = <String>{};
  void record(Map<String, dynamic> measurement, String type) {
    final revision = measurement['revision_id'];
    if (revision is! num ||
        revision <= 0 ||
        !['impression', 'click'].contains(type) ||
        !_attempted.add('$revision:$type')) {
      return;
    }
    unawaited(
      Future<void>.sync(() => send(measurement, type)).catchError((_) {}),
    );
  }
}

class AdvertisementExposure extends StatefulWidget {
  const AdvertisementExposure({
    super.key,
    required this.builder,
    required this.onImpression,
    required this.active,
  });
  final Widget Function(BuildContext, ValueChanged<bool>) builder;
  final VoidCallback onImpression;
  final bool active;
  @override
  State<AdvertisementExposure> createState() => _AdvertisementExposureState();
}

class _AdvertisementExposureState extends State<AdvertisementExposure>
    with WidgetsBindingObserver {
  bool _loaded = false, _visible = false, _attempted = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _eligible =>
      _loaded &&
      _visible &&
      widget.active &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);
  void _sync() {
    if (!_eligible) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_timer != null || _attempted) return;
    _timer = Timer(const Duration(seconds: 1), () {
      _timer = null;
      if (mounted && _eligible && !_attempted) {
        _attempted = true;
        widget.onImpression();
      }
    });
  }

  @override
  void didUpdateWidget(AdvertisementExposure oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ViewportVisibility(
    active: widget.active,
    onVisibility: (ratio) {
      _visible = ratio >= .5;
      _sync();
    },
    child: widget.builder(context, (loaded) {
      if (mounted && _loaded != loaded) {
        _loaded = loaded;
        _sync();
      }
    }),
  );
}
