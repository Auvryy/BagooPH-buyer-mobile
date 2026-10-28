import 'package:flutter/material.dart';

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

class RemoteImage extends StatelessWidget {
  const RemoteImage({
    super.key,
    required this.uri,
    this.fit = BoxFit.cover,
    this.headers,
    this.onReady,
  });
  final Uri? uri;
  final BoxFit fit;
  final Map<String, String>? headers;
  final ValueChanged<bool>? onReady;
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
    return uri == null
        ? fallback
        : Image.network(
            uri.toString(),
            headers: headers,
            fit: fit,
            frameBuilder: (_, child, frame, synchronous) {
              if (onReady != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => onReady!(synchronous || frame != null),
                );
              }
              return child;
            },
            errorBuilder: (_, _, _) {
              if (onReady != null) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => onReady!(false),
                );
              }
              return fallback;
            },
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const ColoredBox(
                    color: Color(0xFFF1F5F9),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
          );
  }
}
