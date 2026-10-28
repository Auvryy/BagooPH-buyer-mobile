import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ReadOutcome { success, retry, stop }

/// A read may finish after navigation, an explicit action or account cleanup.
/// Callers must check this ticket before accepting its result.
class ReadTicket {
  ReadTicket._(this._current);
  final bool Function() _current;
  bool get isCurrent => _current();
}

/// Serial foreground reads only. Never pass a submission callback here.
class ForegroundRead {
  ForegroundRead({
    required this.read,
    this.interval = const Duration(seconds: 15),
    this.maxBackoff = const Duration(minutes: 2),
  });

  final Future<ReadOutcome> Function(ReadTicket ticket) read;
  final Duration interval, maxBackoff;
  Timer? _timer;
  Future<void>? _running;
  bool _active = false, _disposed = false, _halted = false, _again = false;
  int _generation = 0, _failures = 0;
  bool get halted => _halted;
  bool get active => _active && !_disposed && !_halted;

  void setActive(bool value) {
    if (_disposed || value == _active) return;
    _active = value;
    _generation++;
    _again = false;
    _timer?.cancel();
    if (active) _schedule(Duration.zero);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (active) _timer = Timer(delay, refresh);
  }

  Future<void> refresh() {
    if (!active) return Future.value();
    _timer?.cancel();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final generation = _generation;
    final ticket = ReadTicket._(() => active && generation == _generation);
    return _running = _perform(ticket);
  }

  Future<void> _perform(ReadTicket ticket) async {
    var outcome = ReadOutcome.retry;
    try {
      outcome = await read(ticket);
    } catch (_) {
      // Screens provide feedback; an unexpected read failure must not create
      // an unhandled timer error or start a tight retry loop.
    } finally {
      _running = null;
      if (ticket.isCurrent) {
        if (outcome == ReadOutcome.stop) {
          _halted = true;
          _again = false;
          _timer?.cancel();
        } else {
          _failures = outcome == ReadOutcome.success ? 0 : _failures + 1;
        }
      }
      if (active) {
        final immediately = _again || !ticket.isCurrent;
        _again = false;
        final delay = Duration(
          milliseconds: math.min(
            maxBackoff.inMilliseconds,
            interval.inMilliseconds * (1 << math.min(_failures, 8)),
          ),
        );
        _schedule(immediately ? Duration.zero : delay);
      }
    }
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
  }
}

/// Reacts to route visibility as well as app lifecycle. A covered conversation
/// must not fetch messages because the current GET also acknowledges reads.
class ForegroundRefresh extends StatefulWidget {
  const ForegroundRefresh({
    super.key,
    required this.controller,
    required this.child,
    this.enabled = true,
  });
  final ForegroundRead controller;
  final Widget child;
  final bool enabled;

  @override
  State<ForegroundRefresh> createState() => _ForegroundRefreshState();
}

class _ForegroundRefreshState extends State<ForegroundRefresh>
    with WidgetsBindingObserver {
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ForegroundRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.setActive(false);
    }
    _sync();
  }

  void _sync() => widget.controller.setActive(
    widget.enabled &&
        _foreground &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.of(context),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.setActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
