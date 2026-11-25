import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'qndxx_config_service.dart';

class QndxxAccount {
  const QndxxAccount({
    required this.email,
    required this.panelUrl,
    this.userInfo = const {},
  });

  final String email;
  final String panelUrl;
  final Map<String, dynamic> userInfo;
}

class QndxxSubscription {
  const QndxxSubscription({
    required this.bytes,
    required this.sourceUrl,
    this.userInfo,
  });

  final Uint8List bytes;
  final String sourceUrl;
  final String? userInfo;
}

/// XBoard authentication and subscription bridge for FlClash profiles.
class QndxxXboardService {
  QndxxXboardService._();

  static final QndxxXboardService instance = QndxxXboardService._();

  static const _tokenKey = 'qndxx.xboard.token';
  static const _panelKey = 'qndxx.xboard.panel';
  static const _emailKey = 'qndxx.xboard.email';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 15),
    responseType: ResponseType.plain,
    headers: const {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'User-Agent': 'QNDXX/6.6.6',
    },
  ));

  String? _token;
  String? _panelUrl;
  String? _email;

  String _normalizeBaseUrl(String value) {
    final uri = Uri.parse(value.trim());
    if (!uri.hasScheme || uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('面板地址必须是有效的 HTTP/HTTPS URL');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  dynamic _decode(dynamic value) {
    if (value is! String) return value;
    final text = value.trim();
    if (text.startsWith('{') || text.startsWith('[')) return jsonDecode(text);
    return value;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String? _message(Map<String, dynamic> body) =>
      (body['message'] ?? body['msg'] ?? body['error'])?.toString();

  Future<QndxxAccount> login({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('请输入邮箱和密码');
    }

    final config = QndxxConfigService.instance;
    if (config.localConfig.isEmpty) {
      await config.initialize(refreshRemote: true);
    } else {
      await config.refresh();
    }
    final candidates = config.rankedPanelUrls.isNotEmpty
        ? config.rankedPanelUrls
        : config.panelUrls;
    if (candidates.isEmpty) {
      throw StateError('远程配置没有 panels.QNDXX 面板地址');
    }

    Object? lastError;
    for (final candidate in candidates) {
      final baseUrl = _normalizeBaseUrl(candidate);
      try {
        final response = await _dio.post<Object?>(
          '$baseUrl/api/v1/passport/auth/login',
          data: {'email': email.trim(), 'password': password},
          options: Options(responseType: ResponseType.plain),
        );
        final body = _map(_decode(response.data));
        final data = _map(body['data']);
        final token = (data['token'] ?? data['auth_data'])?.toString().trim();
        if (response.statusCode != 200 ||
            (body['status'] != null &&
                body['status'] != 1 &&
                body['status'] != true) ||
            token == null ||
            token.isEmpty) {
          throw StateError(_message(body) ?? '登录失败：面板没有返回有效 Token');
        }

        _token = token.startsWith('Bearer ') ? token.substring(7) : token;
        _panelUrl = baseUrl;
        _email = email.trim();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_panelKey, baseUrl);
        await prefs.setString(_emailKey, _email!);

        final userResponse = await _authorizedGet('/api/v1/user/info');
        final userBody = _map(_decode(userResponse.data));
        return QndxxAccount(
          email: _email!,
          panelUrl: baseUrl,
          userInfo: _map(userBody['data']),
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('所有 QNDXX 面板登录均失败：$lastError');
  }

  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _panelUrl = prefs.getString(_panelKey);
    _email = prefs.getString(_emailKey);
    if (_token == null || _panelUrl == null) {
      throw StateError('尚未登录 QNDXX 账号');
    }
  }

  Future<void> logout() async {
    try {
      if (_token != null && _panelUrl != null) {
        await _authorizedPost('/api/v1/passport/auth/logout', const {});
      }
    } catch (_) {
      // Local logout must still succeed when the panel is unreachable.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_panelKey);
    await prefs.remove(_emailKey);
    _token = null;
    _panelUrl = null;
    _email = null;
  }

  Future<Response<Object?>> _authorizedGet(String path) async {
    if (_token == null || _panelUrl == null) await restoreSession();
    try {
      return await _dio.get<Object?>(
        '$_panelUrl$path',
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Authorization': 'Bearer $_token'},
        ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401 &&
          error.response?.statusCode != 403) {
        rethrow;
      }
      // Older XBoard installations expect the raw token without "Bearer ".
      return _dio.get<Object?>(
        '$_panelUrl$path',
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Authorization': _token!},
        ),
      );
    }
  }

  Future<Response<Object?>> _authorizedPost(
    String path,
    Map<String, dynamic> data,
  ) async {
    if (_token == null || _panelUrl == null) await restoreSession();
    try {
      return await _dio.post<Object?>(
        '$_panelUrl$path',
        data: data,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Authorization': 'Bearer $_token'},
        ),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 401 &&
          error.response?.statusCode != 403) {
        rethrow;
      }
      return _dio.post<Object?>(
        '$_panelUrl$path',
        data: data,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Authorization': _token!},
        ),
      );
    }
  }

  String? _extractToken(String subscribeUrl, Map<String, dynamic> data) {
    final fromData = data['token']?.toString();
    if (fromData != null && fromData.isNotEmpty) return fromData;
    try {
      final uri = Uri.parse(subscribeUrl);
      final queryToken = uri.queryParameters['token'];
      if (queryToken != null && queryToken.isNotEmpty) return queryToken;
      if (uri.pathSegments.isNotEmpty) {
        final last = uri.pathSegments.last;
        if (last.length >= 16) return last;
      }
    } catch (_) {}
    return null;
  }

  List<String> _subscriptionCandidates(
    String subscribeUrl,
    String token,
    bool preferEncrypt,
  ) {
    final config = QndxxConfigService.instance;
    final candidates = <String>[];
    for (final item in config.subscriptionUrls) {
      final base = item['url']?.toString() ?? '';
      final endpoints = _map(item['endpoints']);
      final ordered = endpoints.entries.toList()
        ..sort((a, b) {
          bool encrypted(Map value) => value['isEncrypt'] == true;
          final ae = encrypted(_map(a.value));
          final be = encrypted(_map(b.value));
          if (ae == be) return a.key.compareTo(b.key);
          return preferEncrypt ? (be ? 1 : -1) : (ae ? 1 : -1);
        });
      for (final entry in ordered) {
        final endpoint = _map(entry.value);
        final path = endpoint['path']?.toString() ?? '';
        if (base.isEmpty || path.isEmpty) continue;
        final resolved = path.replaceAll('{token}', token);
        final joined = base.endsWith('/')
            ? '$base' + (resolved.startsWith('/') ? resolved.substring(1) : resolved)
            : '$base' + (resolved.startsWith('/') ? resolved : '/$resolved');
        final uri = Uri.parse(joined);
        final query = Map<String, String>.from(uri.queryParameters);
        query.putIfAbsent('flag', () => 'flclash');
        candidates.add(uri.replace(queryParameters: query).toString());
      }
    }
    if (subscribeUrl.isNotEmpty) candidates.add(subscribeUrl);
    return candidates.toSet().toList(growable: false);
  }

  String? _decrypt(String encrypted, String key) {
    if (key.isEmpty) return null;
    try {
      final decoded = base64.decode(encrypted.trim());
      final keyBytes = utf8.encode(key);
      if (keyBytes.isEmpty) return null;
      final xored = Uint8List(decoded.length);
      for (var i = 0; i < decoded.length; i++) {
        xored[i] = decoded[i] ^ keyBytes[i % keyBytes.length];
      }
      final stage = utf8.decode(xored);
      final plain = utf8.decode(base64.decode(stage));
      try {
        return utf8.decode(base64.decode(plain));
      } catch (_) {
        return plain;
      }
    } catch (_) {
      return null;
    }
  }

  bool _looksLikeClash(String content) {
    final normalized = content.trimLeft();
    return normalized.contains('\nproxies:') ||
        normalized.startsWith('proxies:') ||
        normalized.contains('\nproxy-groups:') ||
        normalized.startsWith('proxy-groups:');
  }

  Future<QndxxSubscription> downloadSubscription() async {
    if (_token == null || _panelUrl == null) await restoreSession();
    final response = await _authorizedGet('/api/v1/user/getSubscribe');
    final body = _map(_decode(response.data));
    final data = _map(body['data']);
    final subscribeUrl = (data['subscribe_url'] ?? data['subscribeUrl'])
        ?.toString() ?? '';
    if (subscribeUrl.isEmpty) {
      throw StateError(_message(body) ?? '账号没有返回订阅地址');
    }

    final token = _extractToken(subscribeUrl, data);
    if (token == null || token.isEmpty) {
      throw StateError('无法从订阅信息中提取订阅 Token');
    }

    final config = QndxxConfigService.instance;
    final candidates = _subscriptionCandidates(
      subscribeUrl,
      token,
      config.preferEncrypt,
    );
    Object? lastError;
    for (final url in candidates) {
      try {
        Response<Object?>? result;
        Object? requestError;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            result = await _dio.get<Object?>(
              url,
              options: Options(
                responseType: ResponseType.plain,
                headers: {
                  'User-Agent': config.subscriptionUserAgent,
                  'Accept': '*/*',
                },
              ),
            );
            break;
          } catch (error) {
            requestError = error;
            if (attempt < 2) {
              await Future<void>.delayed(Duration(seconds: attempt + 1));
            }
          }
        }
        if (result == null) {
          lastError = requestError ?? StateError('订阅请求失败');
          continue;
        }
        var text = result.data?.toString() ?? '';
        if (text.isEmpty) continue;
        try {
          final json = _map(jsonDecode(text));
          if (json['data'] is String) {
            text = json['data'] as String;
          }
        } catch (_) {
          // Plain-text subscription bodies are expected for many panels.
        }
        final decrypted = _decrypt(text, config.decryptKey);
        final content = decrypted != null && _looksLikeClash(decrypted)
            ? decrypted
            : text;
        if (!_looksLikeClash(content)) {
          lastError = StateError('订阅响应不是有效的 Clash YAML，且解密未成功');
          continue;
        }
        return QndxxSubscription(
          bytes: Uint8List.fromList(utf8.encode(content)),
          sourceUrl: url,
          userInfo: result.headers.value('subscription-userinfo'),
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('获取订阅失败：$lastError');
  }

  void dispose() {
    _dio.close(force: true);
  }
}
