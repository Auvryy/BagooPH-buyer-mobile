import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bagoo_buyer_mobile/core/uploads.dart';
import 'package:bagoo_buyer_mobile/core/web_session.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';

import 'controlled_web_session.dart';
import 'fake_buyer_repository.dart' show buyer;

typedef ReturnSubmission = ({
  String path,
  String method,
  Map<String, dynamic> values,
  List<UploadPart> files,
});

class ReturnSession extends ControlledWebSession {
  final submissions = <ReturnSubmission>[];
  final documentRequests = <String>[];
  Future<WebPage> Function(ReturnSubmission)? onSubmit;
  Future<RemoteDocument> Function(String)? onDocument;

  @override
  Future<WebPage> submit(
    String path,
    Map<String, dynamic> values, {
    String method = 'POST',
    String? referer,
    List<UploadPart>? files,
  }) async {
    final request = (
      path: path,
      method: method,
      values: Map<String, dynamic>.from(jsonDecode(jsonEncode(values)) as Map),
      files: List<UploadPart>.of(files ?? const []),
    );
    submissions.add(request);
    if (onSubmit == null) throw StateError('Unexpected return mutation: $path');
    return onSubmit!(request);
  }

  @override
  Future<RemoteDocument> documentBytes(String path) async {
    documentRequests.add(path);
    if (onDocument == null) throw StateError('Unexpected document read: $path');
    return onDocument!(path);
  }
}

class FixtureFileSelector extends FileSelectorPlatform {
  XFile? next;
  Future<XFile?> Function()? select;
  int calls = 0;
  List<XTypeGroup>? lastTypes;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls++;
    lastTypes = acceptedTypeGroups;
    return select == null ? next : await select!();
  }
}

Uint8List returnPhotoBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN4wOv0HwAFLwIvfpkhFAAAAABJRU5ErkJggg==',
);

XFile returnPhoto() =>
    XFile.fromData(returnPhotoBytes(), path: '/qa/photo.png');

WebPage returnForm({int order = 11, int owner = 7}) =>
    WebPage('Returns/Create', {
      'auth': {
        'user': {...buyer, 'id': owner},
      },
      'order': {'id': order, 'order_number': 'TEST-$order'},
      'items': [
        {
          'id': 101,
          'name': 'Test purchase',
          'quantity': 3,
          'available_quantity': 2,
        },
      ],
      'requestUntil': '2026-11-10T12:00:00Z',
      'reasons': {'damaged': 'Item damaged', 'wrong_item': 'Wrong item'},
      'requestToken': 'v1.aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.${'a' * 64}',
    });

WebPage returnDetail({
  int owner = 7,
  int id = 4,
  int order = 11,
  String description = 'Private return details for the original buyer.',
  String status = 'requested',
  int version = 1,
  List<String> actions = const ['withdraw'],
  String? success,
}) => WebPage('Returns/Show', {
  'auth': {
    'user': {...buyer, 'id': owner},
  },
  if (success != null) 'flash': {'success': success},
  'returnCase': {
    'id': id,
    'reference': 'RETURN-TEST-$id',
    'order': {'id': order, 'order_number': 'TEST-$order'},
    'status': status,
    'version': version,
    'reason': 'Item damaged',
    'description': description,
    'items': [],
    'actions': actions,
    'evidence': [],
    'history': [],
    'custody': {},
    'money': {'mode': 'cod', 'history': [], 'actions': []},
  },
});
