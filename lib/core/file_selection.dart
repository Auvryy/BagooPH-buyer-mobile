import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'uploads.dart';
import 'web_session.dart';

bool _startsWith(Uint8List bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return false;
  }
  return true;
}

bool _matchesFileSignature(String extension, Uint8List bytes) =>
    switch (extension) {
      'jpg' || 'jpeg' =>
        bytes.length >= 3 &&
            bytes[0] == 0xff &&
            bytes[1] == 0xd8 &&
            bytes[2] == 0xff,
      'png' => _startsWith(bytes, const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      'webp' =>
        _startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
            bytes.length >= 12 &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50,
      'gif' =>
        _startsWith(bytes, const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
            _startsWith(bytes, const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
      'pdf' => _startsWith(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2d]),
      _ => false,
    };

Future<UploadPart?> pickUpload(
  String field, {
  bool avatar = false,
  bool imageOnly = false,
}) async {
  try {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: avatar ? 'Profile photo' : 'Evidence',
          extensions: [
            'jpg',
            'jpeg',
            'png',
            'webp',
            if (avatar) 'gif',
            if (!avatar && !imageOnly) 'pdf',
          ],
          uniformTypeIdentifiers: [
            'public.jpeg',
            'public.png',
            'org.webmproject.webp',
            if (avatar) 'com.compuserve.gif',
            if (!avatar && !imageOnly) 'com.adobe.pdf',
          ],
        ),
      ],
    );
    if (file == null) return null;
    final maximum = (avatar ? 3 : 5) * 1024 * 1024;
    final length = await file.length();
    if (length < 1 || length > maximum) {
      throw BackendException(
        'Choose a ${avatar ? 'photo up to 3 MB' : 'document up to 5 MB'}.',
      );
    }
    final extension = file.name.split('.').last.toLowerCase();
    final mime = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      if (avatar) 'gif': 'image/gif',
      if (!avatar && !imageOnly) 'pdf': 'application/pdf',
    }[extension];
    if (mime == null) {
      throw const BackendException('Choose a supported file type.');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (buffer.length + chunk.length > maximum) {
        throw const BackendException('The selected file is too large.');
      }
      buffer.add(chunk);
    }
    final bytes = buffer.takeBytes();
    if (bytes.isEmpty) {
      throw const BackendException(
        'The selected file is empty. Choose another file.',
      );
    }
    if (!_matchesFileSignature(extension, bytes)) {
      throw const BackendException(
        'The selected file contents do not match its file type. Choose another file.',
      );
    }
    return UploadPart(field, file.name, bytes, mime);
  } on BackendException {
    rethrow;
  } on Exception {
    throw const BackendException(
      'The selected file could not be opened. Choose a file you can access and try again.',
    );
  }
}
