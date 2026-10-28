import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/web_session.dart';

class SaleClock extends StatefulWidget {
  const SaleClock({super.key, required this.offer, required this.onBoundary});
  final Map<String, dynamic> offer;
  final VoidCallback onBoundary;
  @override
  State<SaleClock> createState() => _SaleClockState();
}

class _SaleClockState extends State<SaleClock> with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _origin, _server;
  final _seen = <String>{};
  DateTime get _now => _server.add(DateTime.now().difference(_origin));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(SaleClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer != widget.offer) _sync();
  }

  void _sync() {
    _origin = DateTime.now();
    _server =
        DateTime.tryParse(widget.offer['server_now']?.toString() ?? '') ??
        _origin;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    for (final value in [
      mapOf(widget.offer['active'])['ends_at'],
      mapOf(widget.offer['upcoming'])['starts_at'],
    ].whereType<String>()) {
      final boundary = DateTime.tryParse(value);
      if (boundary != null && !boundary.isAfter(_now) && _seen.add(value)) {
        widget.onBoundary();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _tick();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = mapOf(widget.offer['active']);
    final end = DateTime.tryParse(
      (active.isEmpty
                  ? mapOf(widget.offer['upcoming'])['starts_at']
                  : active['ends_at'])
              ?.toString() ??
          '',
    );
    if (end == null) return const SizedBox.shrink();
    final seconds = end.difference(_now).inSeconds.clamp(0, 99999999);
    final hours = seconds ~/ 3600;
    return Text(
      seconds == 0
          ? 'Refreshing sale availability…'
          : '${active.isEmpty ? 'Starts' : 'Ends'} in ${hours}h ${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}m ${(seconds % 60).toString().padLeft(2, '0')}s',
      style: const TextStyle(fontWeight: FontWeight.w700, height: 1.7),
    );
  }
}
