import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_xboard_sdk/flutter_xboard_sdk.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  const _SubscriptionCandidate(this.url, this.method, this.isEncrypted);

  final String url;
  final String method;
  final bool isEncrypted;
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
  XBoardSDK? _sdk;

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

  Future<XBoardSDK> _ensureSdk() async {
    if (_token == null || _panelUrl == null) await restoreSession();
    final current = _sdk ?? XBoardSDK.instance;
    if (current.isInitialized && current.baseUrl != _panelUrl) {
      current.dispose();
    }
    if (!current.isInitialized) {
      final config = QndxxConfigService.instance;
      await current.initialize(
        _panelUrl!,
        panelType: config.panelType,
        httpConfig: HttpConfig.production(
          userAgent: config.apiUserAgent,
          obfuscationPrefix: config.obfuscationPrefix.isEmpty
              ? null
              : config.obfuscationPrefix,
        ),
        enableLogging: false,
      );
    }
    await current.saveToken(_token!);
    _sdk = current;
    return current;
  }

  Future<Map<String, dynamic>> getAccountInfo() async {
    final model = await (await _ensureSdk()).user.getUserInfo();
    return Map<String, dynamic>.from(model.toJson());
  }

  Future<List<Map<String, dynamic>>> getPlans() async {
    final models = await (await _ensureSdk()).plan.getPlans();
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<Map<String, dynamic>?> getPlan(int id) async {
    final model = await (await _ensureSdk()).plan.getPlan(id);
    return model == null ? null : Map<String, dynamic>.from(model.toJson());
  }

  Future<Map<String, dynamic>> getSubscriptionInfo() async {
    final model = await (await _ensureSdk()).subscription.getSubscription();
    return Map<String, dynamic>.from(model.toJson());
  }

  Future<String> getSubscriptionUrl() async {
    return (await _ensureSdk()).subscription.getSubscribeUrl();
  }

  Future<List<Map<String, dynamic>>> getOrders({
    int page = 1,
    int pageSize = 10,
  }) async {
    final models = await (await _ensureSdk()).order.getOrders(
      page: page,
      pageSize: pageSize,
    );
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<String> createOrder(int planId, String period, {String? couponCode}) {
    return _ensureSdk().then(
      (sdk) => sdk.order.createOrder(planId, period, couponCode: couponCode),
    );
  }

  Future<Map<String, dynamic>> checkoutOrder(
    String tradeNo,
    String method,
  ) async {
    final model = await (await _ensureSdk()).order.checkoutOrder(tradeNo, method);
    return Map<String, dynamic>.from(model.toJson());
  }

  Future<bool> cancelOrder(String tradeNo) async {
    return (await _ensureSdk()).order.cancelOrder(tradeNo);
  }

  Future<List<Map<String, dynamic>>> getPaymentMethods([String? tradeNo]) async {
    final sdk = await _ensureSdk();
    final models = tradeNo == null
        ? await sdk.payment.getPaymentMethods()
        : await sdk.order.getPaymentMethods(tradeNo);
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<List<Map<String, dynamic>>> getNotices({
    int page = 1,
    int pageSize = 10,
  }) async {
    final models = await (await _ensureSdk()).notice.getNotices(
      page: page,
      pageSize: pageSize,
    );
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<Map<String, dynamic>> getInviteInfo() async {
    final model = await (await _ensureSdk()).invite.getInviteInfo();
    return Map<String, dynamic>.from(model.toJson());
  }

  Future<List<Map<String, dynamic>>> getInviteCodes() async {
    final models = await (await _ensureSdk()).invite.getInviteCodes();
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<String> generateInviteCode() async {
    return (await _ensureSdk()).invite.generateInviteCode();
  }

  Future<List<Map<String, dynamic>>> getCommissionDetails({
    int page = 1,
    int pageSize = 10,
  }) async {
    final models = await (await _ensureSdk()).invite.getCommissionDetails(
      page: page,
      pageSize: pageSize,
    );
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<List<Map<String, dynamic>>> getTickets({
    int page = 1,
    int pageSize = 10,
  }) async {
    final models = await (await _ensureSdk()).ticket.getTickets(
      page: page,
      pageSize: pageSize,
    );
    return models.map((item) => Map<String, dynamic>.from(item.toJson())).toList();
  }

  Future<Map<String, dynamic>> getTicket(int id) async {
    final model = await (await _ensureSdk()).ticket.getTicket(id);
    return Map<String, dynamic>.from(model.toJson());
  }

  Future<bool> createTicket(String subject, String message, int level) async {
    return (await _ensureSdk()).ticket.createTicket(subject, message, level);
  }

  Future<bool> replyTicket(int id, String message) async {
    return (await _ensureSdk()).ticket.replyTicket(id, message);
  }

  Future<bool> closeTicket(int id) async {
    return (await _ensureSdk()).ticket.closeTicket(id);
  }

  Future<void> logout() async {
    try {
      if (_token != null && _panelUrl != null) {
        await _authorizedPost('/api/v1/passport/auth/logout', const {});
      }
    } catch (_) {
      // Local logout must still succeed when the panel is unreachable.
    }
    try {
      final sdk = _sdk;
      if (sdk != null && sdk.isInitialized) {
        try { await sdk.clearToken(); } finally { sdk.dispose(); }
      }
    } catch (_) {
      _sdk?.dispose();
    }
    _sdk = null;
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
            endpoint['isEncrypt'] == true || entry.key.toLowerCase() == 'v2',
          ),
        );
      }
    }
    if (subscribeUrl.isNotEmpty) {
      final path = Uri.tryParse(subscribeUrl)?.path.toLowerCase() ?? '';
      candidates.add(_SubscriptionCandidate(
        subscribeUrl,
        'GET',
        path.contains('encrypt'),
      ));
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

  Future<QndxxSubscription> _downloadSubscriptionCandidate(
    _SubscriptionCandidate candidate,
    String token,
    QndxxConfigService config,
    CancelToken cancelToken,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final options = Options(
          responseType: ResponseType.plain,
          cancelToken: cancelToken,
          headers: {
            'User-Agent': config.subscriptionUserAgent,
            'Accept': '*/*',
          },
        );
        final result = candidate.method == 'POST'
            ? await _dio.post<Object?>(
                candidate.url,
                data: {'token': token},
                options: options,
              )
            : await _dio.get<Object?>(candidate.url, options: options);
        var text = result.data?.toString() ?? '';
        final prefix = config.obfuscationPrefix;
        if (prefix.isNotEmpty && text.startsWith(prefix)) {
          text = text.substring(prefix.length);
        }
        if (text.isEmpty) throw StateError('订阅响应为空');
        try {
          final json = _map(jsonDecode(text));
          if (json['data'] is String) text = json['data'] as String;
        } catch (_) {
          // Plain-text subscription bodies are expected for many panels.
        }
        final decrypted = _decrypt(text, config.decryptKey);
        final content = decrypted != null && _looksLikeClash(decrypted)
            ? decrypted
            : text;
        if (!_looksLikeClash(content)) {
          throw StateError('订阅响应不是有效的 Clash YAML，且解密未成功');
        }
        return QndxxSubscription(
          bytes: Uint8List.fromList(utf8.encode(content)),
          sourceUrl: candidate.url,
          userInfo: result.headers.value('subscription-userinfo'),
        );
      } catch (error) {
        if (CancelToken.isCancel(error)) rethrow;
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    throw StateError('订阅源失败：${_safeError(lastError)}');
  }

  Future<QndxxSubscription> _raceSubscriptionCandidates(
    List<_SubscriptionCandidate> candidates,
    String token,
    QndxxConfigService config,
  ) async {
    if (candidates.isEmpty) throw StateError('没有可用的订阅地址');
    if (candidates.length == 1) {
      return _downloadSubscriptionCandidate(
        candidates.single,
        token,
        config,
        CancelToken(),
      );
    }
    final completer = Completer<QndxxSubscription>();
    final cancelTokens = List.generate(candidates.length, (_) => CancelToken());
    var remaining = candidates.length;
    Object? lastError;
    for (var index = 0; index < candidates.length; index++) {
      _downloadSubscriptionCandidate(
        candidates[index],
        token,
        config,
        cancelTokens[index],
      ).then((result) {
        if (completer.isCompleted) return;
        completer.complete(result);
        for (var other = 0; other < cancelTokens.length; other++) {
          if (other != index) {
            cancelTokens[other].cancel('another subscription endpoint won');
          }
        }
      }).catchError((Object error) {
        lastError = error;
        remaining--;
        if (remaining == 0 && !completer.isCompleted) {
          completer.completeError(
            StateError('所有订阅地址均失败：${_safeError(lastError)}'),
          );
        }
      });
    }
    return completer.future;
  }

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
    final preferred = candidates
        .where((item) => item.isEncrypted == config.preferEncrypt)
        .toList(growable: false);
    final fallback = candidates
        .where((item) => item.isEncrypted != config.preferEncrypt)
        .toList(growable: false);
    try {
      return await _raceSubscriptionCandidates(
        preferred.isEmpty ? candidates : preferred,
        token,
        config,
      );
    } catch (error) {
      if (fallback.isEmpty || preferred.isEmpty) rethrow;
      return _raceSubscriptionCandidates(fallback, token, config);
    }
  }

  Future<Map<String, dynamic>> checkForUpdates() async {
    final urls = QndxxConfigService.instance.updateUrls;
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
      final normalized = baseUrl.replaceFirst(RegExp(r'/+
    return (await _ensureSdk()).user.updateUserInfo(data);
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    return (await _ensureSdk()).user.changePassword(oldPassword, newPassword);
  }

  Future<bool> resetAccountSecurity() async {
    return (await _ensureSdk()).user.resetSecurity();
  }

  Future<bool> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    return (await _ensureSdk()).auth.register(
      email,
      password,
      emailCode: emailCode,
      inviteCode: inviteCode,
    );
  }

  Future<bool> sendEmailVerifyCode(String email) async {
    return (await _ensureSdk()).auth.sendEmailVerifyCode(email);
  }

  Future<bool> forgotPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    return (await _ensureSdk()).auth.forgotPassword(email, code, newPassword);
  }

  Future<Map<String, dynamic>?> getOrder(String tradeNo) async {
    final model = await (await _ensureSdk()).order.getOrder(tradeNo);
    return model == null ? null : Map<String, dynamic>.from(model.toJson());
  }

  Future<Map<String, dynamic>?> checkCoupon(
    String code,
    int planId,
  ) async {
    final model = await (await _ensureSdk()).order.checkCoupon(code, planId);
    return model == null ? null : Map<String, dynamic>.from(model.toJson());
  }

  Future<bool> withdrawCommission({
    required double amount,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    return (await _ensureSdk()).invite.withdrawCommission(
      amount: amount,
      method: method,
      params: params,
    );
  }

  Future<bool> transferCommissionToBalance(double amount) async {
    return (await _ensureSdk()).invite.transferCommissionToBalance(amount);
  }

  void dispose() {
    _dio.close(force: true);
  }
}
), '');
      try {
        final response = await _dio.get<Object?>(
          '$normalized/api/v1/check-update',
          queryParameters: {
            'version': packageInfo.version,
            'platform': platform,
          },
          options: Options(
            responseType: ResponseType.plain,
            headers: {
              'Accept': 'application/json',
              'User-Agent': QndxxConfigService.instance.apiUserAgent,
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
    throw StateError('所有 QNDXX 更新服务器均不可用：${_safeError(lastError)}');
  }

  Future<bool> updateAccountInfo(Map<String, dynamic> data) async {
    return (await _ensureSdk()).user.updateUserInfo(data);
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    return (await _ensureSdk()).user.changePassword(oldPassword, newPassword);
  }

  Future<bool> resetAccountSecurity() async {
    return (await _ensureSdk()).user.resetSecurity();
  }

  Future<bool> register({
    required String email,
    required String password,
    String? emailCode,
    String? inviteCode,
  }) async {
    return (await _ensureSdk()).auth.register(
      email,
      password,
      emailCode: emailCode,
      inviteCode: inviteCode,
    );
  }

  Future<bool> sendEmailVerifyCode(String email) async {
    return (await _ensureSdk()).auth.sendEmailVerifyCode(email);
  }

  Future<bool> forgotPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    return (await _ensureSdk()).auth.forgotPassword(email, code, newPassword);
  }

  Future<Map<String, dynamic>?> getOrder(String tradeNo) async {
    final model = await (await _ensureSdk()).order.getOrder(tradeNo);
    return model == null ? null : Map<String, dynamic>.from(model.toJson());
  }

  Future<Map<String, dynamic>?> checkCoupon(
    String code,
    int planId,
  ) async {
    final model = await (await _ensureSdk()).order.checkCoupon(code, planId);
    return model == null ? null : Map<String, dynamic>.from(model.toJson());
  }

  Future<bool> withdrawCommission({
    required double amount,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    return (await _ensureSdk()).invite.withdrawCommission(
      amount: amount,
      method: method,
      params: params,
    );
  }

  Future<bool> transferCommissionToBalance(double amount) async {
    return (await _ensureSdk()).invite.transferCommissionToBalance(amount);
  }

  void dispose() {
    _dio.close(force: true);
  }
}
