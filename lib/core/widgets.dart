import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../app/theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BagooPH',
    image: true,
    child: ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                'assets/branding/bagoo-mark.png',
                width: size,
                height: size,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Bagoo',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const Text(
              'PH',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: BagooTheme.crimson,
                letterSpacing: -.8,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? BagooTheme.rose : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: error ? const Color(0xFFBE123C) : const Color(0xFF047857),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: error ? const Color(0xFF9F1239) : const Color(0xFF065F46),
        ),
      ),
    ),
  );
}

class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(label),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const ExcludeSemantics(
              child: Icon(Icons.arrow_forward_rounded, size: 19),
            ),
        ],
      ),
    ),
  );
}

class RemoteImage extends StatefulWidget {
  const RemoteImage({
    super.key,
    required this.uri,
    this.fit = BoxFit.cover,
    this.headers,
    this.onReady,
    this.thumbnail = false,
  });
  final Uri? uri;
  final BoxFit fit;
  final Map<String, String>? headers;
  final ValueChanged<bool>? onReady;

  /// Decode public previews near their display size. Full-size viewers and
  /// authenticated images keep their original decoding behavior.
  final bool thumbnail;

  @override
  State<RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<RemoteImage> {
  bool? _reported;
  int _generation = 0;

  @override
  void didUpdateWidget(covariant RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri ||
        !mapEquals(oldWidget.headers, widget.headers) ||
        oldWidget.onReady == null && widget.onReady != null) {
      _reported = null;
      _generation++;
    }
  }

  void _report(bool ready) {
    if (widget.onReady == null || _reported == ready) return;
    _reported = ready;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) widget.onReady?.call(ready);
    });
  }

  int _decodeExtent(double logical, double ratio) =>
      (((logical * ratio).ceil() + 63) ~/ 64 * 64).clamp(64, 1536);

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: Color(0xFFF1F5F9),
      child: Center(
        child: Icon(
          Icons.shopping_bag_outlined,
          color: BagooTheme.muted,
          size: 40,
        ),
      ),
    );
    return widget.uri == null
        ? fallback
        : LayoutBuilder(
            builder: (context, box) {
              ImageProvider provider = NetworkImage(
                widget.uri.toString(),
                headers: widget.headers,
              );
              if (widget.thumbnail &&
                  widget.headers == null &&
                  box.hasBoundedWidth &&
                  box.hasBoundedHeight &&
                  box.maxWidth > 0 &&
                  box.maxHeight > 0) {
                final ratio = MediaQuery.devicePixelRatioOf(context);
                provider = ResizeImage(
                  provider,
                  width: _decodeExtent(box.maxWidth, ratio),
                  height: _decodeExtent(box.maxHeight, ratio),
                  policy: ResizeImagePolicy.fit,
                );
              }
              return Image(
                image: provider,
                fit: widget.fit,
                frameBuilder: (_, child, frame, synchronous) {
                  final ready = synchronous || frame != null;
                  _report(ready);
                  return ready
                      ? child
                      : const ColoredBox(
                          color: Color(0xFFF1F5F9),
                          child: Center(child: SizedBox.shrink()),
                        );
                },
                errorBuilder: (_, _, _) {
                  _report(false);
                  return fallback;
                },
              );
            },
          );
  }
}
