import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    if (body['success'] == true || body['status'] == true) return true;
    final data = body['data'];
    return data == true || data != null;
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
        final baseUrl = _normalizeBaseUrl(candidate);
        final response = await _dio.post<Object?>(
          '$baseUrl$path',
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
    throw StateError('QNDXX 面板请求失败：${_safeError(lastError)}');
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
    if (body['data'] != true) {
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
    return (await _ensurePublicSdk()).auth.register(
      email,
      password,
      emailCode: emailCode,
      inviteCode: inviteCode,
    );
  }

  Future<bool> sendEmailVerifyCode(String email) async {
    return (await _ensurePublicSdk()).auth.sendEmailVerifyCode(email);
  }

  Future<bool> forgotPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    return (await _ensurePublicSdk()).auth.forgotPassword(email, code, newPassword);
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
  void dispose() {
    _dio.close(force: true);
  }
}
