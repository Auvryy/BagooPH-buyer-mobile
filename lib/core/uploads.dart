import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

class UploadPart {
  const UploadPart(this.field, this.name, this.bytes, this.mime);
  final String field;
  final String name;
  final Uint8List bytes;
  final String mime;
}

class RemoteDocument {
  const RemoteDocument(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

class MultipartPayload {
  MultipartPayload(Map<String, dynamic> values, List<UploadPart> files) {
    final random = Random.secure();
    boundary =
        'bagoo${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final body = BytesBuilder(copy: false);
    void text(String value) => body.add(utf8.encode(value));
    String safe(String value) => value.replaceAll(RegExp(r'[\r\n"\\]'), '_');
    void value(String key, dynamic item) {
      if (item is Map) {
        for (final entry in item.entries) {
          value('$key[${entry.key}]', entry.value);
        }
      } else if (item is List) {
        for (var i = 0; i < item.length; i++) {
          value('$key[$i]', item[i]);
        }
      } else {
        text(
          '--$boundary\r\nContent-Disposition: form-data; name="${safe(key)}"\r\n\r\n',
        );
        text(item is bool ? (item ? '1' : '0') : item?.toString() ?? '');
        text('\r\n');
      }
    }

    for (final entry in values.entries) {
      value(entry.key, entry.value);
    }
    for (final file in files) {
      text(
        '--$boundary\r\nContent-Disposition: form-data; name="${safe(file.field)}"; filename="${safe(file.name)}"\r\nContent-Type: ${safe(file.mime)}\r\n\r\n',
      );
      body.add(file.bytes);
      text('\r\n');
    }
    text('--$boundary--\r\n');
    bytes = body.takeBytes();
  }
  late final String boundary;
  late final Uint8List bytes;
}
