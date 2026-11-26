import 'package:fl_clash/xboard/qndxx_config_service.dart';
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
    expect(QndxxConfigService.remoteConfigUrl,
        'https://img.toufq.com/speed/blob/main/url/config.json');
    expect(config.localConfig, isNotEmpty);
    expect(config.panelType, 'xboard');
    expect(config.remoteConfig, isEmpty);
  });

  test('uses QNDXX authentication and domain-racing user agents', () {
    expect(config.apiUserAgent, 'QNDXX/6.6.6');
    expect(config.subscriptionUserAgent, 'QNDXX/6.6.6');
    expect(config.domainRacingUserAgent,
        'QNDXX/6.6.6 (Domain Racing Test)');
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
}
