import 'package:flutter/foundation.dart';

import '../../core/web_session.dart';
import 'tracking_repository.dart';

class TrackingController extends ChangeNotifier {
  TrackingController(this.repository);

  final TrackingRepository repository;
  TrackingLookup? result;
  String? problem;
  String? fieldError;
  bool loading = false;
  String? _activeNumber;
  int _generation = 0;
  bool _disposed = false;

  void edited() {
    if (_disposed) return;
    _generation++;
    _activeNumber = null;
    result = null;
    problem = null;
    fieldError = null;
    loading = false;
    notifyListeners();
  }

  Future<void> lookup(String input, {bool refresh = false}) async {
    if (_disposed) return;
    String number;
    try {
      number = normalizeTrackingNumber(input);
    } on BackendException catch (error) {
      edited();
      fieldError = error.fields['number'] ?? error.message;
      notifyListeners();
      return;
    }
    if (loading && _activeNumber == number) return;
    final previous = refresh && result?.number == number ? result : null;
    final generation = ++_generation;
    _activeNumber = number;
    result = previous;
    problem = null;
    fieldError = null;
    loading = true;
    notifyListeners();
    try {
      final confirmed = await repository.lookup(number);
      if (_disposed || generation != _generation) return;
      result = confirmed;
    } on BackendException catch (error) {
      if (_disposed || generation != _generation) return;
      fieldError = error.fields['number'] ?? error.fields['tracking_number'];
      if (fieldError == null) {
        problem = error.message;
      } else {
        result = null;
      }
    } catch (_) {
      if (_disposed || generation != _generation) return;
      problem =
          'Tracking could not be loaded. Check your connection and try again.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final number = result?.number;
    if (number != null) await lookup(number, refresh: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
