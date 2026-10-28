import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Measures the visible area inside every containing viewport after layout.
class ViewportVisibility extends StatefulWidget {
  const ViewportVisibility({
    super.key,
    required this.child,
    required this.onVisibility,
    this.active = true,
  });
  final Widget child;
  final ValueChanged<double> onVisibility;
  final bool active;
  @override
  State<ViewportVisibility> createState() => _ViewportVisibilityState();
}

class _ViewportVisibilityState extends State<ViewportVisibility>
    with WidgetsBindingObserver {
  final _box = GlobalKey();
  final _positions = <ScrollPosition>{};
  bool _scheduled = false;
  double? _last;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final position in _positions) {
      position.removeListener(_schedule);
    }
    _positions.clear();
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        if (_positions.add(position)) position.addListener(_schedule);
      }
      return true;
    });
    _schedule();
  }

  @override
  void didUpdateWidget(ViewportVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeMetrics() => _schedule();
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _schedule();
  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _measure();
    });
  }

  void _measure() {
    var ratio = 0.0;
    final box = _box.currentContext?.findRenderObject();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (widget.active &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        box is RenderBox &&
        box.attached &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      final media = MediaQuery.of(context);
      var clip = Rect.fromLTWH(
        0,
        0,
        media.size.width,
        (media.size.height - media.viewInsets.bottom).clamp(0, double.infinity),
      );
      context.visitAncestorElements((element) {
        if (element is RenderObjectElement &&
            element.renderObject is RenderAbstractViewport &&
            element.renderObject is RenderBox) {
          final viewport = element.renderObject as RenderBox;
          if (viewport.hasSize) {
            clip = clip.intersect(
              viewport.localToGlobal(Offset.zero) & viewport.size,
            );
          }
        }
        return true;
      });
      final rect = box.localToGlobal(Offset.zero) & box.size;
      final visible = rect.intersect(clip);
      if (!visible.isEmpty) {
        ratio = ((visible.width * visible.height) / (rect.width * rect.height))
            .clamp(0, 1);
      }
    }
    if (_last != ratio) {
      _last = ratio;
      widget.onVisibility(ratio);
    }
  }

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_schedule);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    return SizedBox(key: _box, child: widget.child);
  }
}
