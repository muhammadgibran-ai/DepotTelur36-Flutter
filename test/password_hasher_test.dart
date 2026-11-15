import 'package:depot_telur_36/core/utils/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordHasher', () {
    test('hashPassword menghasilkan salt acak unik untuk password yang sama', () {
      final hashA = PasswordHasher.hashPassword('Rahasia123');
      final hashB = PasswordHasher.hashPassword('Rahasia123');

      expect(hashA, contains(':'));
      expect(hashB, contains(':'));
      expect(hashA, isNot(equals(hashB)));
      expect(hashA, isNot(contains('Rahasia123')));
    });

    test('hashPassword dengan customSalt bersifat deterministik & terverifikasi', () {
      final hashA = PasswordHasher.hashPassword(
        'DepotTelur36!',
        customSalt: 'garamTetap',
      );
      final hashB = PasswordHasher.hashPassword(
        'DepotTelur36!',
        customSalt: 'garamTetap',
      );

      expect(hashA, equals(hashB));
      expect(PasswordHasher.verify('DepotTelur36!', hashA), isTrue);
      expect(PasswordHasher.verify('SalahPassword', hashA), isFalse);
    });

    test('verify menolak hash kosong atau format rusak secara aman', () {
      expect(PasswordHasher.verify('abc', ''), isFalse);
      expect(PasswordHasher.verify('', 'salt:digest'), isFalse);
      expect(PasswordHasher.verify('abc', 'tanpa_pemisah'), isFalse);
      expect(PasswordHasher.verify('abc', ':kosongSalt'), isFalse);
      expect(PasswordHasher.verify('abc', 'kosongDigest:'), isFalse);
      expect(PasswordHasher.verify('abc', 'a:b:c'), isFalse);
      expect(PasswordHasher.verify('1234', '__OAUTH_GOOGLE_LINKED__'), isFalse);
    });

    test('mendukung passphrase berspasi, simbol, unicode & password panjang', () {
      const passphrase = '  Depot Telur 36 🥚!@#  ';
      final hash = PasswordHasher.hashPassword(passphrase);

      expect(PasswordHasher.verify(passphrase, hash), isTrue);
      expect(PasswordHasher.verify(passphrase.trim(), hash), isFalse);
      expect(PasswordHasher.verify('  depot telur 36 🥚!@#  ', hash), isFalse);

      final longPass = 'aB1!' * 60;
      final longHash = PasswordHasher.hashPassword(longPass);
      expect(PasswordHasher.verify(longPass, longHash), isTrue);
      expect(PasswordHasher.verify('${longPass}x', longHash), isFalse);
    });

    test('hashPassword menolak customSalt kosong atau mengandung pemisah ":"', () {
      expect(
        () => PasswordHasher.hashPassword('Rahasia123', customSalt: ''),
        throwsArgumentError,
      );
      expect(
        () => PasswordHasher.hashPassword('Rahasia123', customSalt: 'a:b'),
        throwsArgumentError,
      );
    });
  });
}
