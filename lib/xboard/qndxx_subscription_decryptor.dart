import 'dart:convert';
import 'dart:typed_data';

/// Orange-compatible XBoard subscription decryption (Base64 -> XOR -> Base64).
class QndxxSubscriptionDecryptor {
  const QndxxSubscriptionDecryptor._();

  static String? decrypt(String encrypted, String key) {
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

  static bool looksLikeClash(String content) {
    final normalized = content
        .replaceFirst('\uFEFF', '')
        .trimLeft();
    // A valid Mihomo profile does not have to contain proxies/rules (for
    // example, a DNS-only or TUN-only profile). Accept its standard root keys.
    const keys = [
      'proxies:',
      'proxy-groups:',
      'proxy-providers:',
      'rules:',
      'rule-providers:',
      'port:',
      'mixed-port:',
      'socks-port:',
      'redir-port:',
      'tproxy-port:',
      'tun:',
      'dns:',
      'listeners:',
      'external-controller:',
      'mode:',
    ];
    return keys.any(
      (key) =>
          normalized.startsWith(key) ||
          normalized.contains('\n$key'),
    );
  }

  /// Returns plain YAML candidates from raw, Base64-wrapped, and encrypted
  /// subscription payloads. A candidate is accepted only after the caller
  /// verifies that it has a recognizable Mihomo root key.
  static List<String> decodeCandidates(String response, String key) {
    final source = response.replaceFirst('\uFEFF', '').trim();
    if (source.isEmpty) return const [];

    final candidates = <String>[];
    void add(String? value) {
      if (value == null) return;
      final normalized = value.replaceFirst('\uFEFF', '').trim();
      if (normalized.isNotEmpty && !candidates.contains(normalized)) {
        candidates.add(normalized);
      }
    }

    add(source);
    add(decrypt(source, key));

    final compact = source.replaceAll(RegExp(r'\\s+'), '');
    if (compact.isNotEmpty) {
      final base64Text = compact.replaceAll('-', '+').replaceAll('_', '/');
      final padded = base64Text.padRight(
        base64Text.length + ((4 - base64Text.length % 4) % 4),
        '=',
      );
      try {
        final decoded = utf8.decode(
          base64.decode(padded),
          allowMalformed: true,
        );
        add(decoded);
        add(decrypt(decoded, key));
      } catch (_) {
        // Not a Base64 subscription; keep trying the raw and encrypted forms.
      }
    }
    return candidates;
  }
}
