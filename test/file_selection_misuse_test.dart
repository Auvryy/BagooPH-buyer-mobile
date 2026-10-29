import 'dart:io';

import 'package:bagoo_buyer_mobile/core/file_selection.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/return_fixtures.dart';

class ChangingFile extends XFile {
  ChangingFile(this.actual, {this.reported = 1}) : super('/qa/photo.png');
  final Uint8List actual;
  final int reported;
  @override
  Future<int> length() async => reported;
  @override
  Future<Uint8List> readAsBytes() async => actual;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List.sublistView(
      actual,
      start ?? 0,
      end == null || end > actual.length ? actual.length : end,
    );
  }
}

class GrowingFile extends XFile {
  GrowingFile() : super('/qa/photo.png');
  int streamed = 0;
  @override
  Future<int> length() async => 1;
  @override
  Future<Uint8List> readAsBytes() =>
      throw StateError('An unbounded read would consume the grown file.');
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final limit = end ?? 20 * 1024 * 1024;
    while (streamed < limit) {
      final count = (limit - streamed).clamp(0, 65536);
      streamed += count;
      yield Uint8List(count);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform original;
  late FixtureFileSelector picker;
  setUp(() {
    original = FileSelectorPlatform.instance;
    picker = FixtureFileSelector();
    FileSelectorPlatform.instance = picker;
  });
  tearDown(() => FileSelectorPlatform.instance = original);

  test('cancelled native selection returns no upload', () async {
    expect(await pickUpload('photo', imageOnly: true), isNull);
  });
  test('a supported image preserves its selected bytes and field', () async {
    picker.next = returnPhoto();
    final upload = await pickUpload('photo', imageOnly: true);
    expect(upload!.field, 'photo');
    expect(upload.mime, 'image/png');
    expect(upload.bytes, returnPhotoBytes());
  });
  for (final length in [0, 5 * 1024 * 1024 + 1]) {
    test('rejects invalid reported file size $length', () async {
      picker.next = ChangingFile(Uint8List(1), reported: length);
      await expectLater(
        pickUpload('photo', imageOnly: true),
        throwsA(isA<BackendException>()),
      );
    });
  }
  for (final name in [
    'document.pdf',
    'animation.gif',
    'executable.exe',
    'photo.png.exe',
  ]) {
    test('return photos reject unsupported selection $name', () async {
      picker.next = XFile.fromData(returnPhotoBytes(), path: '/qa/$name');
      await expectLater(
        pickUpload('photo', imageOnly: true),
        throwsA(isA<BackendException>()),
      );
    });
  }
  test('a file emptied after selection cannot become an upload', () async {
    picker.next = ChangingFile(Uint8List(0));
    await expectLater(
      pickUpload('photo', imageOnly: true),
      throwsA(isA<BackendException>()),
    );
  });
  test(
    'a growing file is bounded while reading rather than read completely',
    () async {
      final file = GrowingFile();
      picker.next = file;
      await expectLater(
        pickUpload('photo', imageOnly: true),
        throwsA(isA<BackendException>()),
      );
      expect(file.streamed, lessThanOrEqualTo(5 * 1024 * 1024 + 65536));
    },
  );
  test(
    'unreadable selection has recoverable feedback without leaking a path',
    () async {
      picker.select = () => throw const FileSystemException(
        'Permission denied',
        '/private/person/photo.png',
      );
      await expectLater(
        pickUpload('photo'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message.contains('/private/'),
            'private path leak',
            false,
          ),
        ),
      );
    },
  );
  test('native picker failure is translated to recoverable feedback', () async {
    picker.select = () => throw PlatformException(
      code: 'permission_denied',
      message: 'Private operating-system detail',
    );
    await expectLater(pickUpload('photo'), throwsA(isA<BackendException>()));
  });
}
