import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

/// Loads the QNDXX XBoard routing configuration without replacing FlClash's
/// v0.9.4 profile/core lifecycle. Remote configuration is optional at boot:
/// an unavailable config endpoint must never prevent the native core starting.
class QndxxConfigService {
  QndxxConfigService._();

  static final QndxxConfigService instance = QndxxConfigService._();

  static const assetPath = 'assets/config/xboard.config.yaml';
  static const provider = 'QNDXX';
  static const remoteConfigUrl =
      'https://img.toufq.com/speed/blob/main/url/config.json';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ),
  );

  Map<String, dynamic> _local = const {};
  Map<String, dynamic> _remote = const {};
  String? _fastestPanel;
  List<String> _rankedPanels = const [];
  DateTime? _lastRefresh;

  Map<String, dynamic> get localConfig => Map.unmodifiable(_local);
  Map<String, dynamic> get remoteConfig => Map.unmodifiable(_remote);
  String? get fastestPanelUrl => _fastestPanel;
  DateTime? get lastRefresh => _lastRefresh;
  List<String> get rankedPanelUrls => List.unmodifiable(_rankedPanels);
  String get decryptKey =>
      (_local['subscription'] as Map?)?['decrypt_key']?.toString() ?? '';
  bool get preferEncrypt =>
      (_local['subscription'] as Map?)?['prefer_encrypt'] == true;
  String get obfuscationPrefix =>
      (_local['security'] as Map?)?['obfuscation_prefix']?.toString() ?? '';
  String get apiUserAgent {
    final agents = (_local['security'] as Map?)?['user_agents'] as Map?;
    return agents?['api_encrypted']?.toString() ?? 'QNDXX/6.6.6';
  }

  String get domainRacingUserAgent {
    final agents = (_local['security'] as Map?)?['user_agents'] as Map?;
    return agents?['domain_racing_test']?.toString() ??
        'QNDXX/6.6.6 (Domain Racing Test)';
  }

  String get crispWebsiteId =>
      (_local['customer_service'] as Map?)?['crisp_website_id']?.toString() ??
      '92f20590-a75f-4b50-a521-6d5fc7a356dd';
  String get subscriptionUserAgent {
    final security = _local['security'] as Map?;
    final agents = security?['user_agents'] as Map?;
    return agents?['subscription']?.toString() ??
        agents?['api_encrypted']?.toString() ??
        'QNDXX/6.6.6';
  }

  String get panelType => _remote['panelType']?.toString() ?? 'xboard';

  List<String> get proxyUrls => _stringUrls(_remote['proxy']);
  List<String> get websocketUrls => _stringUrls(_remote['ws']);
  List<String> get updateUrls => _stringUrls(_remote['update']);

  List<Map<String, dynamic>> get onlineSupport =>
      _mapList(_remote['onlineSupport']);
  List<Map<String, dynamic>> get subscriptionUrls =>
      _mapList((_remote['subscription'] as Map?)?['urls']);

  List<String> _stringUrls(dynamic source) => _mapList(source)
      .map((item) => item['url']?.toString() ?? '')
      .where((url) => url.isNotEmpty)
      .toList(growable: false);

  List<Map<String, dynamic>> _mapList(dynamic source) {
    if (source is! List) return const [];
    return source
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<String> get panelUrls {
    final panels = _remote['panels'];
    if (panels is! Map) return const [];
    final selected =
        panels[provider] ?? panels[provider.toLowerCase()] ?? const <dynamic>[];
    if (selected is! List) return const [];
    return selected
        .whereType<Map>()
        .map((item) => item['url']?.toString() ?? '')
        .where((url) => url.startsWith('https://') || url.startsWith('http://'))
        .toList(growable: false);
  }

  Future<void> initialize({bool refreshRemote = true}) async {
    final source = await rootBundle.loadString(assetPath);
    final parsed = loadYaml(source);
    final normalized = _toMap(parsed);
    final xboard = normalized['xboard'];
    _local = xboard is Map<String, dynamic> ? xboard : const {};
    if (refreshRemote) {
      await refresh();
    }
  }

  Future<bool> refresh() async {
    final remoteSettings = _local['remote_config'];
    final settings = remoteSettings is Map ? remoteSettings : const {};
    final sources =
        (settings['sources'] is List
              ? (settings['sources'] as List).whereType<Map>().toList()
              : <Map>[])
          ..sort(
            (a, b) => (int.tryParse('${b['priority'] ?? 0}') ?? 0).compareTo(
              int.tryParse('${a['priority'] ?? 0}') ?? 0,
            ),
          );
    final retries = int.tryParse('${settings['max_retries'] ?? 3}') ?? 3;
    final candidates = sources.isEmpty
        ? <String>[remoteConfigUrl]
        : sources
              .map((source) => source['url']?.toString() ?? '')
              .where(
                (url) =>
                    url.startsWith('https://') || url.startsWith('http://'),
              )
              .toList(growable: false);

    for (final url in candidates) {
      for (var attempt = 0; attempt <= retries; attempt++) {
        try {
          final response = await _dio.get<Object?>(url);
          final body = response.data;
          final decoded = body is String ? jsonDecode(body) : body;
          if (decoded is! Map) {
            throw const FormatException(
              'QNDXX remote config must be a JSON object',
            );
          }
          final panels = decoded['panels'];
          if (panels is! Map ||
              (panels[provider] is! List &&
                  panels[provider.toLowerCase()] is! List)) {
            throw const FormatException(
              'QNDXX remote config must define panels.QNDXX',
            );
          }
          _remote = Map<String, dynamic>.from(decoded);
          _lastRefresh = DateTime.now();
          await racePanelDomains();
          return true;
        } catch (_) {
          if (attempt < retries) {
            final delaySeconds =
                int.tryParse('${settings['retry_delay_seconds'] ?? 2}') ?? 2;
            await Future<void>.delayed(Duration(seconds: delaySeconds));
          }
        }
      }
    }
    return false;
  }

  /// Probes configured panel endpoints concurrently and keeps the first
  /// successful response by elapsed time. A failed race leaves the previous
  /// successful endpoint untouched.
  Future<String?> racePanelDomains() async {
    final candidates = panelUrls;
    if (candidates.isEmpty) return _fastestPanel;
    final results = await Future.wait(candidates.map(_probe));
    final reachable =
        results.whereType<({String url, Duration latency})>().toList()
          ..sort((a, b) => a.latency.compareTo(b.latency));
    if (reachable.isNotEmpty) {
      _rankedPanels = reachable.map((item) => item.url).toList(growable: false);
      _fastestPanel = _rankedPanels.first;
    }
    return _fastestPanel;
  }

  Future<({String url, Duration latency})?> _probe(String url) async {
    final stopwatch = Stopwatch()..start();
    try {
      await _dio.get<Object?>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: {'User-Agent': domainRacingUserAgent},
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );
      stopwatch.stop();
      return (url: url, latency: stopwatch.elapsed);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is YamlMap) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _normalize(entry.value),
      };
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _normalize(entry.value),
      };
    }
    return const {};
  }

  dynamic _normalize(dynamic value) {
    if (value is YamlMap || value is Map) return _toMap(value);
    if (value is YamlList || value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    return value;
  }

  void dispose() {
    _dio.close(force: true);
  }
}
