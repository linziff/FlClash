import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import 'qndxx_xboard_service.dart';

/// Optional, authenticated status channel. Remote arbitrary HTTP tasks are
/// deliberately not executed; only heartbeat and identity events are handled.
class QndxxRemoteStatusService extends ChangeNotifier {
  QndxxRemoteStatusService._();

  static final instance = QndxxRemoteStatusService._();

  static const _enabledKey = 'qndxx.remote_status.enabled';
  static const _nodeIdKey = 'qndxx.remote_status.node_id';

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnect;
  bool _enabled = false;
  bool _connected = false;
  bool _connecting = false;
  bool _disposed = false;

  bool get isEnabled => _enabled;
  bool get isConnected => _connected;

  Future<String> _nodeId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_nodeIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final value = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString(_nodeIdKey, value);
    return value;
  }

  Future<void> startIfEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    notifyListeners();
    if (_enabled) await start();
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    _enabled = value;
    notifyListeners();
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (!_enabled || _connected || _connecting || _disposed) return;
    _connecting = true;
    _reconnect?.cancel();
    Object? lastError;
    try {
      final (token, urls) =
          await QndxxXboardService.instance.getRemoteStatusCredentials();
      final nodeId = await _nodeId();
      final secureUrls = urls.where((value) {
        return Uri.tryParse(value)?.scheme.toLowerCase() == 'wss';
      }).toList(growable: false);
      if (secureUrls.isEmpty) {
        throw StateError('远程状态服务没有配置 WSS 安全地址');
      }

      for (final base in secureUrls) {
        IOWebSocketChannel? candidate;
        try {
          final uri = Uri.parse(base);
          final basePath = uri.path.replaceFirst(RegExp(r'/+$'), '');
          final endpoint = uri.replace(path: '$basePath/$nodeId');
          candidate = IOWebSocketChannel.connect(
            endpoint,
            headers: {'Authorization': 'Bearer $token'},
          );
          await candidate.ready.timeout(const Duration(seconds: 12));
          if (!_enabled || _disposed) {
            await candidate.sink.close();
            return;
          }
          _channel = candidate;
          _subscription = candidate.stream.listen(
            _handleMessage,
            onDone: _handleDisconnect,
            onError: (Object error, [StackTrace? stackTrace]) =>
                _handleDisconnect(),
            cancelOnError: true,
          );
          _connected = true;
          notifyListeners();
          _send({
            'event': 'identify',
            'payload': {'nodeId': nodeId},
          });
          _startHeartbeat();
          return;
        } catch (error) {
          lastError = error;
          try {
            await candidate?.sink.close();
          } catch (_) {}
        }
      }
      throw StateError('所有 WSS 状态服务器连接失败：$lastError');
    } catch (error) {
      if (lastError != null) _scheduleReconnect();
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (!_enabled || _disposed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 5), start);
  }

  void _handleMessage(dynamic message) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      final event = decoded['event']?.toString();
      if (event == 'ping') {
        _send({'event': 'pong'});
      }
      // Unknown remote tasks are intentionally ignored. In particular, this
      // client never performs server-supplied arbitrary HTTP requests.
    } catch (_) {
      // Ignore malformed status frames without terminating the connection.
    }
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (!_connected || channel == null) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _send({'event': 'ping'});
    });
  }

  void _handleDisconnect() {
    if (!_connected && _channel == null) return;
    _connected = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    notifyListeners();
    _scheduleReconnect();
  }

  Future<void> stop() async {
    _reconnect?.cancel();
    _reconnect = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    _connected = false;
    notifyListeners();
    await channel?.sink.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnect?.cancel();
    _heartbeat?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
