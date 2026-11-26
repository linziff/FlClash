import 'dart:convert';

import 'package:fl_clash/xboard/qndxx_subscription_decryptor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QNDXX subscription response normalization', () {
    test('accepts standard Mihomo root keys including mixed-port', () {
      for (final yaml in [
        'mixed-port: 7890\nmode: rule\n',
        'socks-port: 7891\ndns:\n  enable: true\n',
        'tun:\n  enable: true\n',
        'proxies:\n  - name: node\n',
      ]) {
        expect(
          QndxxSubscriptionDecryptor.looksLikeClash(yaml),
          isTrue,
          reason: yaml,
        );
      }
    });

    test('rejects HTML and unrelated plain text', () {
      expect(
        QndxxSubscriptionDecryptor.looksLikeClash('<html>login</html>'),
        isFalse,
      );
      expect(
        QndxxSubscriptionDecryptor.looksLikeClash('subscription expired'),
        isFalse,
      );
    });

    test('decodes Base64-wrapped Mihomo YAML', () {
      const yaml = 'mixed-port: 7890\nmode: rule\n';
      final encoded = base64.encode(utf8.encode(yaml));
      final candidates = QndxxSubscriptionDecryptor.decodeCandidates(
        encoded,
        '',
      );

      expect(candidates, contains(yaml.trim()));
      expect(candidates.any(QndxxSubscriptionDecryptor.looksLikeClash), isTrue);
    });

    test('decodes URL-safe Base64 with whitespace and missing padding', () {
      const yaml = 'proxies:\n  - name: node\n';
      final encoded = base64Url.encode(utf8.encode(yaml)).replaceAll('=', '');
      final wrapped = '${encoded.substring(0, 8)}\n${encoded.substring(8)}';
      final candidates = QndxxSubscriptionDecryptor.decodeCandidates(
        wrapped,
        '',
      );

      expect(
        candidates.any(
          (candidate) =>
              candidate == yaml.trim() &&
              QndxxSubscriptionDecryptor.looksLikeClash(candidate),
        ),
        isTrue,
      );
    });
  });
}
