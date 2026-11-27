import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/services/credential_vault.dart';

class MemoryCredentialStorage implements CredentialStorage {
  final values = <String, String>{};
  @override Future<String?> read(String key) async => values[key];
  @override Future<void> write(String key, String value) async { values[key] = value; }
  @override Future<void> delete(String key) async { values.remove(key); }
}

void main() {
  group('CredentialVault', () {
    late MemoryCredentialStorage storage;
    late CredentialVault vault;
    setUp(() { storage = MemoryCredentialStorage(); vault = CredentialVault(storage: storage); });

    test('stores and retrieves opt-in credentials without exposing password in index', () async {
      await vault.save(endpoint: 'HTTP://192.0.2.10:8080/onvif/device_service', realm: 'camera',
        scheme: 'basic', username: 'installer', password: 'secret-value');
      final accounts = await vault.accountsFor(endpoint: 'http://192.0.2.10:8080/onvif/device_service',
        realm: 'camera', scheme: 'BASIC');
      expect(accounts, hasLength(1));
      expect(accounts.single.username, 'installer');
      expect(await vault.readPassword(accounts.single), 'secret-value');
      expect(storage.values[CredentialVault.indexKey], isNot(contains('secret-value')));
    });

    test('isolates by endpoint including port, realm, scheme and account', () async {
      await vault.save(endpoint: 'http://192.0.2.10/onvif', realm: 'a', scheme: 'digest', username: 'admin', password: 'one');
      await vault.save(endpoint: 'http://192.0.2.10:8080/onvif', realm: 'a', scheme: 'digest', username: 'admin', password: 'two');
      await vault.save(endpoint: 'http://192.0.2.10/onvif', realm: 'b', scheme: 'digest', username: 'admin', password: 'three');
      expect((await vault.listAccounts()).length, 3);
      final first = await vault.accountsFor(endpoint: 'http://192.0.2.10/onvif', realm: 'a', scheme: 'digest');
      expect(await vault.readPassword(first.single), 'one');
    });

    test('supports multiple accounts and removal', () async {
      await vault.save(endpoint: 'https://192.0.2.10/device', realm: 'camera', scheme: 'digest', username: 'admin', password: 'one');
      await vault.save(endpoint: 'https://192.0.2.10/device', realm: 'camera', scheme: 'digest', username: 'operator', password: 'two');
      final accounts = await vault.accountsFor(endpoint: 'https://192.0.2.10/device', realm: 'camera', scheme: 'digest');
      expect(accounts.map((a) => a.username), containsAll(['admin', 'operator']));
      await vault.delete(accounts.first);
      expect(await vault.accountsFor(endpoint: 'https://192.0.2.10/device', realm: 'camera', scheme: 'digest'), hasLength(1));
    });

    test('rejects unsafe endpoints and empty credentials', () async {
      expect(() => vault.save(endpoint: 'file:///tmp/x', realm: '', scheme: 'basic', username: 'admin', password: 'x'), throwsArgumentError);
      expect(() => vault.save(endpoint: 'http://user:pass@192.0.2.10/onvif', realm: '', scheme: 'basic', username: 'admin', password: 'x'), throwsArgumentError);
      expect(() => vault.save(endpoint: 'http://192.0.2.10/onvif', realm: '', scheme: 'basic', username: ' ', password: 'x'), throwsArgumentError);
    });
  });
}