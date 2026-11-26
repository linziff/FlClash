import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'qndxx_config_service.dart';
import 'qndxx_subscription_decryptor.dart';

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

class _SubscriptionCandidate {
  const _SubscriptionCandidate(this.url, this.method);

  final String url;
  final String method;
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
  static const _profileIdKey = 'qndxx.xboard.profile_id';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      headers: const {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'User-Agent': 'QNDXX/6.6.6',
      },
    ),
  );

  String? _token;
  String? _panelUrl;
  String? _email;

  String _normalizeBaseUrl(String value) {
    final uri = Uri.parse(value.trim());
    if (!uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('面板地址必须是有效的 HTTP/HTTPS URL');
    }
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  dynamic _decode(dynamic value) {
    if (value is! String) return value;
    var text = value.trim();
    final prefix = QndxxConfigService.instance.obfuscationPrefix;
    if (prefix.isNotEmpty && text.startsWith(prefix)) {
      text = text.substring(prefix.length);
    }
    if (text.startsWith('{') || text.startsWith('[')) return jsonDecode(text);
    return text;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String _safeError(Object? error) {
    return (error?.toString() ?? 'unknown error').replaceAll(
      RegExp(r'([?&]token=)[^&\s]+', caseSensitive: false),
      r'$1[redacted]',
    );
  }

  String? _message(Map<String, dynamic> body) => body['message'] == null
      ? (body['msg'] ?? body['error'])?.toString()
      : _safeError(body['message']!);

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
          options: Options(
            responseType: ResponseType.plain,
            headers: {'User-Agent': config.apiUserAgent},
          ),
        );
        final body = _map(_decode(response.data));
        final data = _map(body['data']);
        final token = (data['token'] ?? data['auth_data'])?.toString().trim();
        final status = body['status'];
        final rejected =
            status == false ||
            status == 0 ||
            status == 'error' ||
            status == 'failed' ||
            body['success'] == false;
        if (response.statusCode != 200 ||
            rejected ||
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

  Future<int?> get boundProfileId async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_profileIdKey);
  }

  Future<void> bindProfile(int profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_profileIdKey, profileId);
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

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is List) {
      return value.whereType<Map>().map(_map).toList(growable: false);
    }
    if (value is Map && value['data'] is List) {
      return (value['data'] as List)
          .whereType<Map>()
          .map(_map)
          .toList(growable: false);
    }
    return const [];
  }

  Map<String, dynamic> _responseData(Response<Object?> response) {
    final body = _map(_decode(response.data));
    final data = body['data'];
    return data is Map ? _map(data) : body;
  }

  bool _responseSucceeded(Map<String, dynamic> body) {
    final status = body['status'];
    if (status == false || status == 0 || status == 'error') return false;
    if (body['success'] == true || status == true || status == 1) return true;
    final data = body['data'];
    if (data is bool) return data;
    return data != null;
  }

  Future<Response<Object?>> _publicPost(
    String path,
    Map<String, dynamic> data,
  ) async {
    final config = QndxxConfigService.instance;
    if (config.localConfig.isEmpty) {
      await config.initialize(refreshRemote: true);
    } else if (config.remoteConfig.isEmpty) {
      await config.refresh();
    }
    final candidates = config.rankedPanelUrls.isNotEmpty
        ? config.rankedPanelUrls
        : config.panelUrls;
    final urls = _panelUrl != null ? [_panelUrl!] : candidates;
    if (urls.isEmpty) throw StateError('远程配置没有可用的 QNDXX 面板地址');
    Object? lastError;
    for (final candidate in urls) {
      try {
        final response = await _dio.post<Object?>(
          _normalizeBaseUrl(candidate) + path,
          data: data,
          options: Options(
            responseType: ResponseType.plain,
            headers: {'User-Agent': config.apiUserAgent},
          ),
        );
        final body = _map(_decode(response.data));
        if (response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 300 &&
            _responseSucceeded(body)) {
          return response;
        }
        lastError = StateError(_message(body) ?? '面板拒绝请求');
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('QNDXX 面板请求失败：' + _safeError(lastError));
  }

  Future<Map<String, dynamic>> getAccountInfo() async {
    return _responseData(await _authorizedGet('/api/v1/user/info'));
  }

  Future<List<Map<String, dynamic>>> getPlans() async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/plan/fetch')).data,
    ));
    return _list(body['data']);
  }

  Future<Map<String, dynamic>?> getPlan(int id) async {
    for (final plan in await getPlans()) {
      if (plan['id']?.toString() == id.toString()) return plan;
    }
    return null;
  }

  Future<Map<String, dynamic>> getSubscriptionInfo() async {
    return _responseData(await _authorizedGet('/api/v1/user/getSubscribe'));
  }

  Future<String> getSubscriptionUrl() async {
    final data = await getSubscriptionInfo();
    final url = data['subscribe_url']?.toString() ?? '';
    if (url.isEmpty) throw StateError('面板没有返回订阅链接');
    return url;
  }

  Future<List<Map<String, dynamic>>> getOrders({
    int page = 1,
    int pageSize = 10,
  }) async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/order/fetch')).data,
    ));
    return _list(body['data']);
  }

  Future<String> createOrder(
    int planId,
    String period, {
    String? couponCode,
  }) async {
    final data = <String, dynamic>{
      'plan_id': planId,
      'period': period,
      if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
    };
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/order/save',
      data,
    )).data));
    final value = body['data'];
    if (value is String && value.isNotEmpty) return value;
    if (value is Map) {
      final tradeNo = value['trade_no'] ?? value['tradeNo'];
      if (tradeNo != null) return tradeNo.toString();
    }
    throw StateError(_message(body) ?? '面板没有返回订单号');
  }

  Future<Map<String, dynamic>> checkoutOrder(
    String tradeNo,
    String method,
  ) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/order/checkout',
      {'trade_no': tradeNo, 'method': method},
    )).data));
    final value = body['data'];
    if (value is Map) {
      final data = _map(value);
      return {
        ...data,
        'type': data['type'] ?? body['type'],
        if (data['data'] is String && data['url'] == null) 'url': data['data'],
      };
    }
    return {
      'type': body['type'],
      'data': value,
      if (value is String) 'url': value,
    };
  }

  Future<bool> cancelOrder(String tradeNo) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/order/cancel',
      {'trade_no': tradeNo},
    )).data));
    return _responseSucceeded(body);
  }

  Future<List<Map<String, dynamic>>> getPaymentMethods([String? tradeNo]) async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/order/getPaymentMethod')).data,
    ));
    return _list(body['data']);
  }

  Future<List<Map<String, dynamic>>> getNotices({
    int page = 1,
    int pageSize = 10,
  }) async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/notice/fetch')).data,
    ));
    return _list(body['data']);
  }

  Future<Map<String, dynamic>> getInviteInfo() async {
    return _responseData(await _authorizedGet('/api/v1/user/invite/fetch'));
  }

  Future<List<Map<String, dynamic>>> getInviteCodes() async {
    final info = await getInviteInfo();
    return _list(info['codes']);
  }

  Future<String> generateInviteCode() async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/invite/save')).data,
    ));
    final data = body['data'];
    if (data is String && data.isNotEmpty) return data;
    if (data is Map && data['code'] != null) return data['code'].toString();
    if (!_responseSucceeded(body)) {
      throw StateError(_message(body) ?? '生成邀请码失败');
    }
    final codes = await getInviteCodes();
    if (codes.isEmpty) throw StateError('面板未返回新邀请码');
    return codes.first['code']?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> getCommissionDetails({
    int page = 1,
    int pageSize = 10,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final body = _map(_decode((await _authorizedGet(
      '/api/v1/user/invite/details?current=$page&page_size=$pageSize&t=$timestamp',
    )).data));
    return _list(body['data']);
  }

  Future<List<Map<String, dynamic>>> getTickets({
    int page = 1,
    int pageSize = 10,
  }) async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/ticket/fetch')).data,
    ));
    return _list(body['data']);
  }

  Future<Map<String, dynamic>> getTicket(int id) async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/ticket/fetch?id=$id')).data,
    ));
    final data = body['data'];
    return data is Map ? _map(data) : body;
  }

  Future<bool> createTicket(String subject, String message, int level) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/ticket/withdraw',
      {'subject': subject, 'message': message, 'level': level},
    )).data));
    return _responseSucceeded(body);
  }

  Future<bool> replyTicket(int id, String message) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/ticket/reply',
      {'id': id, 'message': message},
    )).data));
    return _responseSucceeded(body);
  }

  Future<bool> closeTicket(int id) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/ticket/close',
      {'id': id},
    )).data));
    return _responseSucceeded(body);
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
    await prefs.remove(_profileIdKey);
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
          headers: {
            'Authorization': 'Bearer $_token',
            'User-Agent': QndxxConfigService.instance.apiUserAgent,
          },
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
          headers: {
            'Authorization': _token!,
            'User-Agent': QndxxConfigService.instance.apiUserAgent,
          },
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
          headers: {
            'Authorization': 'Bearer $_token',
            'User-Agent': QndxxConfigService.instance.apiUserAgent,
          },
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
          headers: {
            'Authorization': _token!,
            'User-Agent': QndxxConfigService.instance.apiUserAgent,
          },
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

  List<_SubscriptionCandidate> _subscriptionCandidates(
    String subscribeUrl,
    String token,
    bool preferEncrypt,
  ) {
    final config = QndxxConfigService.instance;
    final candidates = <_SubscriptionCandidate>[];
    for (final item in config.subscriptionUrls) {
      final base = item['url']?.toString() ?? '';
      final endpoints = _map(item['endpoints']);
      final ordered = endpoints.entries.toList()
        ..sort((a, b) {
          bool encrypted(Map value, String key) =>
              value['isEncrypt'] == true || key.toLowerCase() == 'v2';
          final ae = encrypted(_map(a.value), a.key);
          final be = encrypted(_map(b.value), b.key);
          if (ae == be) return a.key.compareTo(b.key);
          return preferEncrypt ? (be ? 1 : -1) : (ae ? 1 : -1);
        });
      for (final entry in ordered) {
        final endpoint = _map(entry.value);
        final path = endpoint['path']?.toString() ?? '';
        if (base.isEmpty || path.isEmpty) continue;
        final resolved = path.replaceAll('{token}', token);
        final joined = base.endsWith('/')
            ? '$base${resolved.startsWith('/') ? resolved.substring(1) : resolved}'
            : '$base${resolved.startsWith('/') ? resolved : '/$resolved'}';
        final uri = Uri.parse(joined);
        final query = Map<String, String>.from(uri.queryParameters);
        query.putIfAbsent('flag', () => 'flclash');
        candidates.add(
          _SubscriptionCandidate(
            uri.replace(queryParameters: query).toString(),
            endpoint['method']?.toString().toUpperCase() ?? 'GET',
          ),
        );
      }
    }
    if (subscribeUrl.isNotEmpty) {
      candidates.add(_SubscriptionCandidate(subscribeUrl, 'GET'));
    }
    final unique = <String, _SubscriptionCandidate>{};
    for (final candidate in candidates) {
      unique.putIfAbsent(candidate.url, () => candidate);
    }
    return unique.values.toList(growable: false);
  }

  String? _decrypt(String encrypted, String key) =>
      QndxxSubscriptionDecryptor.decrypt(encrypted, key);

  bool _looksLikeClash(String content) =>
      QndxxSubscriptionDecryptor.looksLikeClash(content);

  Future<QndxxSubscription> downloadSubscription() async {
    if (_token == null || _panelUrl == null) await restoreSession();
    final response = await _authorizedGet('/api/v1/user/getSubscribe');
    final body = _map(_decode(response.data));
    final data = _map(body['data']);
    final subscribeUrl =
        (data['subscribe_url'] ?? data['subscribeUrl'])?.toString() ?? '';
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
    for (final candidate in candidates) {
      final url = candidate.url;
      try {
        Response<Object?>? result;
        Object? requestError;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final options = Options(
              responseType: ResponseType.plain,
              headers: {
                'User-Agent': config.subscriptionUserAgent,
                'Accept': '*/*',
              },
            );
            result = candidate.method == 'POST'
                ? await _dio.post<Object?>(
                    url,
                    data: {'token': token},
                    options: options,
                  )
                : await _dio.get<Object?>(url, options: options);
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
        final obfuscationPrefix = config.obfuscationPrefix;
        if (obfuscationPrefix.isNotEmpty &&
            text.startsWith(obfuscationPrefix)) {
          text = text.substring(obfuscationPrefix.length);
        }
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
    throw StateError('获取订阅失败：${_safeError(lastError)}');
  }

  Future<bool> updateAccountInfo(Map<String, dynamic> data) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/update',
      data,
    )).data));
    return _responseSucceeded(body);
  }

  Future<bool> resetAccountSecurity() async {
    final body = _map(_decode(
      (await _authorizedGet('/api/v1/user/resetSecurity')).data,
    ));
    return _responseSucceeded(body);
  }

  Future<bool> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    final data = <String, dynamic>{
      'email': email,
      'password': password,
      if (emailCode != null && emailCode.isNotEmpty) 'email_code': emailCode,
      if (inviteCode != null && inviteCode.isNotEmpty) 'invite_code': inviteCode,
    };
    final body = _map(_decode((await _publicPost(
      '/api/v1/passport/auth/register',
      data,
    )).data));
    return _responseSucceeded(body);
  }

  Future<bool> sendEmailVerifyCode(String email) async {
    final body = _map(_decode((await _publicPost(
      '/api/v1/passport/comm/sendEmailVerify',
      {'email': email},
    )).data));
    return body['data'] == true;
  }

  Future<bool> forgotPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    final body = _map(_decode((await _publicPost(
      '/api/v1/passport/auth/forget',
      {'email': email, 'password': newPassword, 'email_code': code},
    )).data));
    return _responseSucceeded(body);
  }

  Future<Map<String, dynamic>?> getOrder(String tradeNo) async {
    final body = _map(_decode((await _authorizedGet(
      '/api/v1/user/order/detail?trade_no=$tradeNo',
    )).data));
    final data = body['data'];
    return data is Map ? _map(data) : null;
  }

  Future<Map<String, dynamic>?> checkCoupon(
    String code,
    int planId,
  ) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/coupon/check',
      {'code': code, 'plan_id': planId},
    )).data));
    final data = body['data'];
    return data is Map ? _map(data) : null;
  }

  Future<bool> withdrawCommission({
    required double amount,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/invite/withdraw',
      {'amount': amount, 'method': method, ...params},
    )).data));
    return _responseSucceeded(body);
  }

  Future<bool> transferCommissionToBalance(double amount) async {
    final body = _map(_decode((await _authorizedPost(
      '/api/v1/user/invite/transfer',
      {'amount': amount},
    )).data));
    return _responseSucceeded(body);
  }

  Future<Map<String, dynamic>> checkForUpdates() async {
    final config = QndxxConfigService.instance;
    if (config.localConfig.isEmpty) {
      await config.initialize(refreshRemote: true);
    } else {
      await config.refresh();
    }
    final urls = config.updateUrls;
    if (urls.isEmpty) throw StateError('远程配置没有 update 更新服务器');
    final packageInfo = await PackageInfo.fromPlatform();
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
            ? 'windows'
            : Platform.isMacOS
                ? 'macos'
                : Platform.isIOS
                    ? 'ios'
                    : Platform.isLinux
                        ? 'linux'
                        : 'unknown';
    Object? lastError;
    for (final baseUrl in urls) {
      final normalized = baseUrl.replaceFirst(RegExp(r'/+$'), '');
      try {
        final response = await _dio.get<Object?>(
          normalized + '/api/v1/check-update',
          queryParameters: {
            'version': packageInfo.version,
            'platform': platform,
          },
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Accept': 'application/json',
              'User-Agent': config.apiUserAgent,
            },
            validateStatus: (status) => status == 200,
          ),
        );
        final body = _map(_decode(response.data));
        final data = _map(body['data']).isNotEmpty ? _map(body['data']) : body;
        return {
          'currentVersion': packageInfo.version,
          'latestVersion': data['latest_version']?.toString() ?? '',
          'hasUpdate': data['update_available'] == true,
          'updateUrl': data['download_url']?.toString() ?? '',
          'releaseNotes': data['release_notes']?.toString() ?? '',
          'forceUpdate': data['force_update'] == true,
          'source': normalized,
        };
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('所有 QNDXX 更新服务器均不可用：' + _safeError(lastError));
  }

  void dispose() {
    _dio.close(force: true);
  }
}
