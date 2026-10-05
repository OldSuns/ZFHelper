import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/pkcs1.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

import 'login_gateway.dart';
import 'login_models.dart';

/// Encrypts UTF-8 passwords using the login endpoint's RSA/PKCS1 v1.5 key.
final class RsaPasswordCipher implements PasswordCipher {
  const RsaPasswordCipher();

  @override
  String encrypt({
    required String modulus,
    required String exponent,
    required String password,
  }) {
    final n = _unsignedKeyPart(modulus);
    final e = _unsignedKeyPart(exponent);
    if (n <= e || n.isEven || e < BigInt.from(3) || e.isEven) {
      throw const LoginFailure(LoginFailureCode.protocol, '学校返回的 RSA 公钥无效');
    }
    if (password.isEmpty) {
      throw const LoginFailure(LoginFailureCode.invalidCredentials, '请输入密码');
    }

    final encoded = Uint8List.fromList(utf8.encode(password));
    try {
      // PointyCastle seeds PKCS1 padding from its platform entropy source.
      final cipher = PKCS1Encoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(RSAPublicKey(n, e)));
      if (cipher.inputBlockSize <= 0) {
        throw const LoginFailure(LoginFailureCode.protocol, '学校返回的 RSA 公钥长度无效');
      }
      if (encoded.length > cipher.inputBlockSize) {
        throw const LoginFailure(
          LoginFailureCode.invalidCredentials,
          '密码长度超过学校 RSA 公钥的支持范围，请使用网页登录',
        );
      }
      return base64Encode(cipher.process(encoded));
    } on ArgumentError {
      throw const LoginFailure(LoginFailureCode.protocol, '学校返回的 RSA 公钥无法使用');
    } finally {
      encoded.fillRange(0, encoded.length, 0);
    }
  }

  BigInt _unsignedKeyPart(String source) {
    try {
      final bytes = base64Decode(source.replaceAll(RegExp(r'\s'), ''));
      if (bytes.isEmpty) throw const FormatException();
      return bytes.fold(
        BigInt.zero,
        (value, byte) => (value << 8) | BigInt.from(byte),
      );
    } on FormatException {
      throw const LoginFailure(LoginFailureCode.protocol, '学校返回的 RSA 公钥格式无效');
    }
  }
}
