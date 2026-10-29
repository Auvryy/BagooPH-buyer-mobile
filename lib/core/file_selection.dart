import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'uploads.dart';
import 'web_session.dart';

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
    return UploadPart(field, file.name, bytes, mime);
  } on BackendException {
    rethrow;
  } on Exception {
    throw const BackendException(
      'The selected file could not be opened. Choose a file you can access and try again.',
    );
  }
}
