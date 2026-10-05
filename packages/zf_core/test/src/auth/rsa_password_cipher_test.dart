import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:zf_core/src/auth/login_models.dart';
import 'package:zf_core/src/auth/rsa_password_cipher.dart';

void main() {
  late RSAPublicKey publicKey;
  late RSAPrivateKey privateKey;
  late String modulus;
  late String exponent;
  const cipher = RsaPasswordCipher();

  setUpAll(() {
    final entropy = Random.secure();
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(
            List<int>.generate(32, (_) => entropy.nextInt(256)),
          ),
        ),
      );
    final generator = RSAKeyGenerator()
      ..init(
        ParametersWithRandom<RSAKeyGeneratorParameters>(
          RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 32),
          random,
        ),
      );
    final keys = generator.generateKeyPair();
    publicKey = keys.publicKey;
    privateKey = keys.privateKey;
    modulus = base64Encode(_unsignedBytes(publicKey.modulus!));
    exponent = base64Encode(_unsignedBytes(publicKey.exponent!));
  });

  String decrypt(String encrypted) {
    final decoder = PKCS1Encoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return utf8.decode(decoder.process(base64Decode(encrypted)));
  }

  test('round trips UTF-8 text through RSA/PKCS1 v1.5', () {
    const password = '中文密码🔑abc-123';
    final encrypted = cipher.encrypt(
      modulus: modulus,
      exponent: exponent,
      password: password,
    );

    expect(decrypt(encrypted), password);
    expect(base64Decode(encrypted), hasLength(128));
  });

  test('uses fresh randomized padding for repeated passwords', () {
    final first = cipher.encrypt(
      modulus: modulus,
      exponent: exponent,
      password: 'same-password',
    );
    final second = cipher.encrypt(
      modulus: modulus,
      exponent: exponent,
      password: 'same-password',
    );

    expect(first, isNot(second));
    expect(decrypt(first), 'same-password');
    expect(decrypt(second), 'same-password');
  });

  test('accepts unsigned base64 key parts with leading zero bytes', () {
    final paddedModulus = base64Encode([
      0,
      ..._unsignedBytes(publicKey.modulus!),
    ]);
    final paddedExponent = base64Encode([
      0,
      ..._unsignedBytes(publicKey.exponent!),
    ]);
    final encrypted = cipher.encrypt(
      modulus: paddedModulus,
      exponent: paddedExponent,
      password: 'zero-prefix',
    );

    expect(decrypt(encrypted), 'zero-prefix');
  });

  test('accepts the maximum single-block password size', () {
    final password = 'a' * 117;
    final encrypted = cipher.encrypt(
      modulus: modulus,
      exponent: exponent,
      password: password,
    );

    expect(decrypt(encrypted), password);
  });

  test('rejects overlong UTF-8 input without truncating or splitting it', () {
    expect(
      () => cipher.encrypt(
        modulus: modulus,
        exponent: exponent,
        password: '密' * 40,
      ),
      throwsA(
        isA<LoginFailure>().having(
          (failure) => failure.code,
          'code',
          LoginFailureCode.invalidCredentials,
        ),
      ),
    );
  });

  test(
    'reports malformed or mathematically invalid public keys explicitly',
    () {
      for (final invalidModulus in [
        'not base64!',
        '',
        base64Encode([0]),
      ]) {
        expect(
          () => cipher.encrypt(
            modulus: invalidModulus,
            exponent: exponent,
            password: 'test',
          ),
          throwsA(
            isA<LoginFailure>().having(
              (failure) => failure.code,
              'code',
              LoginFailureCode.protocol,
            ),
          ),
        );
      }
    },
  );
}

Uint8List _unsignedBytes(BigInt value) {
  final hex = value.toRadixString(16);
  final padded = hex.length.isOdd ? '0$hex' : hex;
  return Uint8List.fromList([
    for (var index = 0; index < padded.length; index += 2)
      int.parse(padded.substring(index, index + 2), radix: 16),
  ]);
}
