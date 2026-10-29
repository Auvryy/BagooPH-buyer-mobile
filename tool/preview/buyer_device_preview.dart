import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:bagoo_buyer_mobile/app/theme.dart';

class BuyerDevicePreview extends StatefulWidget {
  const BuyerDevicePreview({super.key, required this.builder});
  final WidgetBuilder builder;

  static final devices = <DeviceInfo>[
    Devices.android.samsungGalaxyS25,
    Devices.android.samsungGalaxyS20,
    Devices.android.googlePixel9,
    Devices.android.googlePixel9ProXL,
    Devices.ios.iPhone16,
    Devices.ios.iPhone16ProMax,
    Devices.ios.iPhoneSE,
    Devices.ios.iPadPro11InchesM4,
  ];

  @override
  State<BuyerDevicePreview> createState() => _BuyerDevicePreviewState();
}

class _BuyerDevicePreviewState extends State<BuyerDevicePreview> {
  late DeviceInfo _device = BuyerDevicePreview.devices.first;
  Orientation _orientation = Orientation.portrait;
  bool _frame = true;
  double _textScale = 1;

  void _rotate() => setState(
    () => _orientation = _orientation == Orientation.portrait
        ? Orientation.landscape
        : Orientation.portrait,
  );

  Widget _controls({VoidCallback? onClose}) {
    final landscape = _orientation == Orientation.landscape;
    final size = landscape
        ? Size(_device.screenSize.height, _device.screenSize.width)
        : _device.screenSize;
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onClose != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close preview options',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
            const Text(
              'Bagoo buyer preview',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<DeviceInfo>(
              key: const ValueKey('preview-device'),
              initialValue: _device,
              isExpanded: true,
              menuMaxHeight: 360,
              decoration: const InputDecoration(labelText: 'Device'),
              items: [
                for (final device in BuyerDevicePreview.devices)
                  DropdownMenuItem(
                    value: device,
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _device = value);
                }
              },
            ),
            const SizedBox(height: 16),
            Tooltip(
              message: landscape ? 'Switch to portrait' : 'Switch to landscape',
              child: OutlinedButton.icon(
                key: const ValueKey('preview-rotate'),
                onPressed: _rotate,
                icon: const Icon(Icons.screen_rotation_outlined),
                label: const Text('Rotate'),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<double>(
              key: const ValueKey('preview-text-size'),
              initialValue: _textScale,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Text size'),
              items: [
                for (final scale in [1.0, 1.25, 1.5, 2.0])
                  DropdownMenuItem(
                    value: scale,
                    child: Text('${(scale * 100).round()}%'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _textScale = value);
                }
              },
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const ValueKey('preview-frame'),
                label: const Text('Device frame'),
                selected: _frame,
                onSelected: (value) => setState(() => _frame = value),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '${size.width.round()} × ${size.height.round()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Logical pixels · ${landscape ? 'Landscape' : 'Portrait'}',
              style: const TextStyle(color: BagooTheme.muted),
            ),
            const SizedBox(height: 16),
            const Text(
              'The frame fits the available window. Google sign-in runs on your Android device.',
              style: TextStyle(color: BagooTheme.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phone() => Padding(
    padding: const EdgeInsets.all(8),
    child: Center(
      child: DeviceFrame(
        key: const ValueKey('buyer-preview-frame'),
        device: _device,
        orientation: _orientation,
        isFrameVisible: _frame,
        screen: Builder(
          builder: (deviceContext) => MediaQuery(
            data: MediaQuery.of(deviceContext)
                .copyWith(textScaler: TextScaler.linear(_textScale)),
            child: ScrollConfiguration(
              behavior: const _PreviewScrollBehavior(),
              child: Builder(builder: widget.builder),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BagooPH Buyer Device Preview',
    debugShowCheckedModeBanner: false,
    theme: BagooTheme.light,
    home: LayoutBuilder(
      builder: (context, constraints) {
        final sidebar = constraints.maxWidth >= 640;
        return Scaffold(
          backgroundColor: BagooTheme.canvas,
          drawer: sidebar
              ? null
              : Drawer(
                  child: SafeArea(
                    child: Builder(
                      builder: (drawerContext) => _controls(
                        onClose: () => Scaffold.of(drawerContext).closeDrawer(),
                      ),
                    ),
                  ),
                ),
          body: SafeArea(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: sidebar ? 248 : 56,
                  child: sidebar
                      ? _controls()
                      : ColoredBox(
                          color: Colors.white,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Builder(
                              builder: (railContext) => IconButton(
                                tooltip: 'Preview options',
                                onPressed: () =>
                                    Scaffold.of(railContext).openDrawer(),
                                icon: const Icon(Icons.tune),
                              ),
                            ),
                          ),
                        ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _phone()),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _PreviewScrollBehavior extends MaterialScrollBehavior {
  const _PreviewScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
