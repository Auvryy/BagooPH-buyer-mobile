import 'dart:io';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/core/file_selection.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/return_fixtures.dart' show FixtureFileSelector;

class _UnreadableSelectedFile extends XFile {
  _UnreadableSelectedFile() : super('/private/buyer/evidence.png');

  @override
  Future<int> length() async => 8;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) => Stream.error(
    const FileSystemException('Access revoked', '/private/buyer/evidence.png'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform originalPicker;
  late FixtureFileSelector picker;

  setUp(() {
    originalPicker = FileSelectorPlatform.instance;
    picker = FixtureFileSelector();
    FileSelectorPlatform.instance = picker;
  });
  tearDown(() => FileSelectorPlatform.instance = originalPicker);

  test(
    'native selection filters match avatar and evidence permissions',
    () async {
      for (final selection in [
        (avatar: false, imageOnly: false, gif: false, pdf: true),
        (avatar: false, imageOnly: true, gif: false, pdf: false),
        (avatar: true, imageOnly: false, gif: true, pdf: false),
        (avatar: true, imageOnly: true, gif: true, pdf: false),
      ]) {
        expect(
          await pickUpload(
            'evidence',
            avatar: selection.avatar,
            imageOnly: selection.imageOnly,
          ),
          isNull,
        );
        final types = picker.lastTypes!.single;
        expect(types.extensions, containsAll(['jpg', 'jpeg', 'png', 'webp']));
        expect(types.extensions!.contains('gif'), selection.gif);
        expect(types.extensions!.contains('pdf'), selection.pdf);
        expect(
          types.uniformTypeIdentifiers!.contains('com.compuserve.gif'),
          selection.gif,
        );
        expect(
          types.uniformTypeIdentifiers!.contains('com.adobe.pdf'),
          selection.pdf,
        );
      }
    },
  );

  test(
    'GIF87a and uppercase JPEG extensions preserve selected contents',
    () async {
      for (final file in [
        (
          name: 'avatar.GIF',
          bytes: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61],
          mime: 'image/gif',
        ),
        (
          name: 'avatar.JPEG',
          bytes: [0xff, 0xd8, 0xff, 0xe0],
          mime: 'image/jpeg',
        ),
      ]) {
        final bytes = Uint8List.fromList(file.bytes);
        picker.next = XFile.fromData(bytes, path: '/qa/${file.name}');
        final result = await pickUpload('avatar', avatar: true);
        expect(result?.name, file.name);
        expect(result?.field, 'avatar');
        expect(result?.mime, file.mime);
        expect(result?.bytes, bytes);
      }
    },
  );

  for (final file in [
    (extension: 'jpg', bytes: [0xff, 0xd8]),
    (extension: 'jpg', bytes: [0xff, 0xd8, 0]),
    (extension: 'jpg', bytes: [0, 0xd8, 0xff]),
    (extension: 'jpg', bytes: [0xff, 0, 0xff]),
    (extension: 'png', bytes: [0x89]),
    (extension: 'png', bytes: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0]),
    (extension: 'pdf', bytes: [0x25]),
    (extension: 'pdf', bytes: [0x25, 0x50, 0x44, 0x46, 0]),
    (extension: 'gif', bytes: [0x47, 0x49, 0x46, 0x38, 0x37]),
    (extension: 'gif', bytes: [0x47, 0x49, 0x46, 0x38, 0x38, 0x61]),
    (extension: 'webp', bytes: [0x52, 0x49, 0x46, 0x46]),
    (
      extension: 'webp',
      bytes: [0, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
    ),
    (
      extension: 'webp',
      bytes: [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0, 0x45, 0x42, 0x50],
    ),
    (
      extension: 'webp',
      bytes: [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0, 0x42, 0x50],
    ),
    (
      extension: 'webp',
      bytes: [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0, 0x50],
    ),
    (
      extension: 'webp',
      bytes: [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0],
    ),
  ].indexed) {
    test(
      'rejects truncated or corrupt signature ${file.$1} (${file.$2.extension})',
      () async {
        picker.next = XFile.fromData(
          Uint8List.fromList(file.$2.bytes),
          path: '/qa/evidence.${file.$2.extension}',
        );
        await expectLater(
          pickUpload('evidence', avatar: file.$2.extension == 'gif'),
          throwsA(
            isA<BackendException>().having(
              (error) => error.message,
              'message',
              'The selected file contents do not match its file type. Choose another file.',
            ),
          ),
        );
      },
    );
  }

  test(
    'stream access failures produce actionable feedback without a path',
    () async {
      picker.next = _UnreadableSelectedFile();
      await expectLater(
        pickUpload('evidence'),
        throwsA(
          isA<BackendException>().having(
            (error) => error.message,
            'message',
            'The selected file could not be opened. Choose a file you can access and try again.',
          ),
        ),
      );
    },
  );
}
