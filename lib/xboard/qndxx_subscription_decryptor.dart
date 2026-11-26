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
    final normalized = content.trimLeft();
    return normalized.startsWith('proxies:') ||
        normalized.contains('\nproxies:') ||
        normalized.startsWith('proxy-groups:') ||
        normalized.contains('\nproxy-groups:') ||
        normalized.startsWith('proxy-providers:') ||
        normalized.contains('\nproxy-providers:') ||
        normalized.startsWith('port:') ||
        normalized.contains('\nport:') ||
        normalized.startsWith('rules:') ||
        normalized.contains('\nrules:');
  }
}
