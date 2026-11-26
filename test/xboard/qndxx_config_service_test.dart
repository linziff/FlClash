import 'dart:convert';

import 'package:fl_clash/common/package.dart';
import 'package:fl_clash/xboard/qndxx_config_service.dart';
import 'package:fl_clash/xboard/qndxx_subscription_decryptor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final config = QndxxConfigService.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await config.initialize(refreshRemote: false);
  });

  test('loads the QNDXX provider and pinned remote configuration', () {
    expect(QndxxConfigService.provider, 'QNDXX');
    expect(
      QndxxConfigService.remoteConfigUrl,
      'https://img.toufq.com/speed/blob/main/url/config.json',
    );
    expect(config.localConfig, isNotEmpty);
    expect(config.panelType, 'xboard');
    expect(config.remoteConfig, isEmpty);
  });

  test('uses QNDXX authentication and domain-racing user agents', () {
    expect(config.apiUserAgent, 'QNDXX/6.6.6');
    expect(config.subscriptionUserAgent, 'QNDXX/6.6.6');
    expect(config.domainRacingUserAgent, 'QNDXX/6.6.6 (Domain Racing Test)');
  });

  test('loads Crisp site configuration and subscription policy', () {
    expect(config.crispWebsiteId, '92f20590-a75f-4b50-a521-6d5fc7a356dd');
    expect(config.preferEncrypt, isTrue);
    expect(config.decryptKey, isEmpty);
    expect(config.obfuscationPrefix, isEmpty);
  });

  test('does not invent panel endpoints before remote config is loaded', () {
    expect(config.panelUrls, isEmpty);
    expect(config.rankedPanelUrls, isEmpty);
    expect(config.fastestPanelUrl, isNull);
  });

  test('keeps HTTP User-Agent ASCII while preserving QNDXX branding', () {
    final userAgent = qndxxUserAgent('6.6.6', platform: 'windows');
    expect(userAgent, 'QNDXX/v6.6.6 clash-verge Platform/windows');
    expect(userAgent.codeUnits.every((unit) => unit < 128), isTrue);
  });

  test('decrypts Orange-compatible Base64/XOR/Base64 subscriptions', () {
    const key = 'qndxx-test-key';
    const yaml = 'proxies:\n  - name: test-node\n' +
        'rules:\n  - MATCH,DIRECT\n';
    final stage = base64.encode(utf8.encode(yaml));
    final stageBytes = utf8.encode(stage);
    final keyBytes = utf8.encode(key);
    final encrypted = base64.encode([
      for (var i = 0; i < stageBytes.length; i++)
        stageBytes[i] ^ keyBytes[i % keyBytes.length],
    ]);

    expect(QndxxSubscriptionDecryptor.decrypt(encrypted, key), yaml);
    expect(QndxxSubscriptionDecryptor.looksLikeClash(yaml), isTrue);
    expect(QndxxSubscriptionDecryptor.decrypt(encrypted, 'wrong-key'), isNull);
  });

  test('supports an additional Base64 layer used by some XBoard panels', () {
    const key = 'qndxx-test-key';
    const yaml = 'proxies:\n  - name: test-node\n';
    final doubleEncoded = base64.encode(
      utf8.encode(base64.encode(utf8.encode(yaml))),
    );
    final bytes = utf8.encode(doubleEncoded);
    final keyBytes = utf8.encode(key);
    final encrypted = base64.encode([
      for (var i = 0; i < bytes.length; i++)
        bytes[i] ^ keyBytes[i % keyBytes.length],
    ]);

    expect(QndxxSubscriptionDecryptor.decrypt(encrypted, key), yaml);
  });
}
