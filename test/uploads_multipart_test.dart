import 'dart:convert';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multipart headers replace every ASCII control character', () {
    final controls = String.fromCharCodes([
      for (var code = 0; code <= 0x1f; code++) code,
      0x7f,
    ]);
    final safeControls = '_' * 33;
    final payload = MultipartPayload(const {}, [
      UploadPart(
        'field$controls',
        'file$controls.png',
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
        'image/png$controls',
      ),
    ]);
    final body = latin1.decode(payload.bytes);

    expect(
      body,
      contains(
        'Content-Disposition: form-data; name="field$safeControls"; filename="file$safeControls.png"',
      ),
    );
    expect(body, contains('Content-Type: image/png$safeControls'));
  });

  test('multipart metadata cannot inject additional headers', () {
    final payload = MultipartPayload(
      {
        'note\r\nContent-Disposition: injected': 'A safe value',
        'attribute\u0000name': 'Another safe value',
      },
      [
        UploadPart(
          'photo"\r\nX-Injected: yes',
          'evidence\\\r\nX-Injected: yes\u007f.png',
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
          'image/png\r\nX-Injected: yes\u0007',
        ),
      ],
    );
    final body = latin1.decode(payload.bytes);

    expect(body, contains('name="note__Content-Disposition: injected"'));
    expect(body, contains('name="attribute_name"'));
    expect(body, contains('name="photo___X-Injected: yes"'));
    expect(body, contains('filename="evidence___X-Injected: yes_.png"'));
    expect(body, contains('Content-Type: image/png__X-Injected: yes_'));
    expect(body, isNot(contains('\r\nX-Injected: yes')));
    expect(body, isNot(contains('\u0000')));
    expect(body, isNot(contains('\u0007')));
    expect(body, isNot(contains('\u007f')));
    expect(body, startsWith('--${payload.boundary}\r\n'));
    expect(body, endsWith('--${payload.boundary}--\r\n'));
  });
}
