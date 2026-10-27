import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/buyer_repository.dart';
import '../../core/web_session.dart';

class PushNotifications {
  PushNotifications._();

  static final PushNotifications instance = PushNotifications._();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  final ValueNotifier<String?> openedNotificationId = ValueNotifier(null);
  final ValueNotifier<int> foregroundRefresh = ValueNotifier(0);
  final ValueNotifier<int> registrationRevision = ValueNotifier(0);

  FirebaseMessaging? _messaging;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<String>? _tokenSubscription;
  BuyerRepository? _activeRepository;
  bool _initialized = false;
  bool _configured = false;

  bool get isSupported => Platform.isAndroid || Platform.isIOS;
  bool get isConfigured => _configured;
  bool isEnabledFor(BuyerRepository repository) =>
      identical(_activeRepository, repository);

  Future<bool> initialize() async {
    if (_initialized) return _configured;
    _initialized = true;
    if (!isSupported) return false;

    const projectId = String.fromEnvironment('BAGOO_FIREBASE_PROJECT_ID');
    const senderId = String.fromEnvironment(
      'BAGOO_FIREBASE_MESSAGING_SENDER_ID',
    );
    const androidApiKey = String.fromEnvironment(
      'BAGOO_FIREBASE_ANDROID_API_KEY',
    );
    const androidAppId = String.fromEnvironment(
      'BAGOO_FIREBASE_ANDROID_APP_ID',
    );
    const iosApiKey = String.fromEnvironment('BAGOO_FIREBASE_IOS_API_KEY');
    const iosAppId = String.fromEnvironment('BAGOO_FIREBASE_IOS_APP_ID');
    const iosBundleId = String.fromEnvironment('BAGOO_FIREBASE_IOS_BUNDLE_ID');

    final apiKey = Platform.isAndroid ? androidApiKey : iosApiKey;
    final appId = Platform.isAndroid ? androidAppId : iosAppId;
    if (projectId.isEmpty ||
        senderId.isEmpty ||
        apiKey.isEmpty ||
        appId.isEmpty ||
        (Platform.isIOS && iosBundleId.isEmpty)) {
      return false;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: senderId,
            projectId: projectId,
            iosBundleId: Platform.isIOS ? iosBundleId : null,
          ),
        );
      }
      _messaging = FirebaseMessaging.instance;
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _receiveOpen,
      );
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((_) {
        foregroundRefresh.value++;
      });
      _receiveOpen(await _messaging!.getInitialMessage());
      _configured = true;
      return true;
    } catch (_) {
      _messaging = null;
      return false;
    }
  }

  Future<void> enable(BuyerRepository repository, int userId) async {
    if (!await initialize() || _messaging == null) {
      throw const BackendException(
        'Push alerts are not configured for this build. You can still check every update in Notifications.',
      );
    }
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw const BackendException(
        'Allow notifications in your device settings to receive Bagoo alerts.',
      );
    }
    final token = await _messaging!.getToken();
    if (token == null || token.isEmpty) {
      throw const BackendException(
        'This device has not received a push token yet. Check your connection and try again.',
      );
    }
    await _register(repository, token);
    await _preferences.setBool(_preferenceKey(userId), true);
    _listenForTokenChanges(repository);
  }

  Future<void> syncIfAuthorized(BuyerRepository repository, int userId) async {
    if (userId <= 0) return;
    if (!await initialize() || _messaging == null) return;
    try {
      if (await _preferences.getBool(_preferenceKey(userId)) != true) return;
      final settings = await _messaging!.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        await _preferences.setBool(_preferenceKey(userId), false);
        try {
          await _removeDevice(repository);
        } on Object {
          _clearActive(repository);
          await _stopListening();
        }
        return;
      }
      final token = await _messaging!.getToken();
      if (token == null || token.isEmpty) return;
      await _register(repository, token);
      _listenForTokenChanges(repository);
    } on Object {
      // Push setup is optional and must never interrupt buyer sign-in.
    }
  }

  Future<void> disable(BuyerRepository repository, int userId) async {
    if (userId > 0) {
      await _preferences.setBool(_preferenceKey(userId), false);
    }
    try {
      await _removeDevice(repository);
    } on Object {
      _clearActive(repository);
      await _stopListening();
      rethrow;
    }
  }

  Future<void> _removeDevice(BuyerRepository repository) async {
    final messaging = _messaging;
    final token = await messaging?.getToken();
    if (token != null && token.isNotEmpty) {
      final result = await repository.session.jsonPost('/buyer/push-device', {
        'token': token,
      }, method: 'DELETE');
      if (result['removed'] != true) {
        throw const BackendException(
          'Bagoo did not confirm that push alerts were turned off.',
        );
      }
    }
    _clearActive(repository);
    await _stopListening();
  }

  void _clearActive(BuyerRepository repository) {
    if (identical(_activeRepository, repository)) {
      _activeRepository = null;
      registrationRevision.value++;
    }
  }

  Future<void> unregister(BuyerRepository repository) async {
    try {
      await _removeDevice(repository);
    } on Object {
      _clearActive(repository);
      await _stopListening();
    }
  }

  void _listenForTokenChanges(BuyerRepository repository) {
    if (identical(_activeRepository, repository) &&
        _tokenSubscription != null) {
      return;
    }
    _activeRepository = repository;
    registrationRevision.value++;
    unawaited(_tokenSubscription?.cancel());
    _tokenSubscription = _messaging?.onTokenRefresh.listen((token) {
      if (identical(_activeRepository, repository)) {
        unawaited(_register(repository, token).catchError((Object _) {}));
      }
    });
  }

  Future<void> _stopListening() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }

  Future<void> _register(BuyerRepository repository, String token) async {
    final result = await repository.session.jsonPost('/buyer/push-device', {
      'token': token,
      'platform': Platform.isAndroid ? 'android' : 'ios',
    });
    if (result['registered'] != true) {
      throw const BackendException(
        'Bagoo did not confirm push setup. You can still check every update in Notifications.',
      );
    }
    _activeRepository = repository;
    registrationRevision.value++;
  }

  String _preferenceKey(int userId) => 'bagoo.push.enabled.$userId';

  void _receiveOpen(RemoteMessage? message) {
    final id = message?.data['notification_id'];
    if (id is String &&
        RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
        ).hasMatch(id)) {
      openedNotificationId.value = id;
    }
  }

  Future<void> dispose() async {
    await _openedSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _tokenSubscription?.cancel();
  }
}
