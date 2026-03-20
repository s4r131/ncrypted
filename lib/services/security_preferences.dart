import 'package:shared_preferences/shared_preferences.dart';

class SecuritySettings {
  const SecuritySettings({
    required this.rsaKeyBits,
    required this.rsaPublicExponent,
    required this.requireVerifiedSender,
  });

  final int rsaKeyBits;
  final int rsaPublicExponent;
  final bool requireVerifiedSender;
}

class SecurityPreferences {
  static const _rsaKeyBitsKey = 'security_rsa_key_bits';
  static const _rsaExponentKey = 'security_rsa_public_exponent';
  static const _requireVerifiedSenderKey = 'security_require_verified_sender';

  static const defaultRsaKeyBits = 2048;
  static const defaultRsaPublicExponent = 65537;
  static const defaultRequireVerifiedSender = false;
  static const maxRsaKeyBits = 4096;
  static const maxRsaPublicExponent = 262147;

  static Future<SecuritySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SecuritySettings(
      rsaKeyBits: prefs.getInt(_rsaKeyBitsKey) ?? defaultRsaKeyBits,
      rsaPublicExponent: prefs.getInt(_rsaExponentKey) ?? defaultRsaPublicExponent,
      requireVerifiedSender: prefs.getBool(_requireVerifiedSenderKey) ?? defaultRequireVerifiedSender,
    );
  }

  static Future<void> saveRsaKeyBits(int bits) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rsaKeyBitsKey, bits);
  }

  static Future<void> saveRsaPublicExponent(int exponent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rsaExponentKey, exponent);
  }

  static Future<void> saveRequireVerifiedSender(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_requireVerifiedSenderKey, value);
  }

  static bool isMaxProfile(SecuritySettings settings) {
    return settings.rsaKeyBits == maxRsaKeyBits &&
        settings.rsaPublicExponent == maxRsaPublicExponent;
  }

  static bool isMaxProfileValues({
    required int rsaKeyBits,
    required int rsaPublicExponent,
  }) {
    return rsaKeyBits == maxRsaKeyBits &&
        rsaPublicExponent == maxRsaPublicExponent;
  }
}
