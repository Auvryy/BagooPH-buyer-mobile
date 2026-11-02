import 'web_session.dart';

int? positiveInt32ResourceId(Object? value) =>
    value is int && value > 0 && value <= 2147483647 ? value : null;

int? positiveResourceId(Object? value) =>
    value is int && value > 0 ? value : null;

Set<int> positiveResourceIds(Object? value) => value is List
    ? value.whereType<int>().where((id) => id > 0).toSet()
    : <int>{};

List<Map<String, dynamic>> requireRowsWithIds(
  dynamic value, {
  required String idKey,
  required String error,
}) {
  if (value is! List ||
      value.any(
        (row) => row is! Map || row.keys.any((key) => key is! String),
      )) {
    throw BackendException(error);
  }
  final rows = mapsOf(value);
  final ids = <int>{};
  if (rows.length != value.length ||
      rows.any((row) {
        final id = positiveResourceId(row[idKey]);
        return id == null || !ids.add(id);
      })) {
    throw BackendException(error);
  }
  return rows;
}
