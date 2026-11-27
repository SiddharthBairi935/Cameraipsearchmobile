import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterCredentialStorage implements CredentialStorage {
  FlutterCredentialStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class CredentialAccount {
  const CredentialAccount({required this.endpoint, required this.realm, required this.scheme, required this.username});
  final String endpoint, realm, scheme, username;
  Map<String, Object?> toJson() => {'endpoint': endpoint, 'realm': realm, 'scheme': scheme, 'username': username};
  factory CredentialAccount.fromJson(Map<String, dynamic> json) => CredentialAccount(
    endpoint: json['endpoint'] as String, realm: json['realm'] as String,
    scheme: json['scheme'] as String, username: json['username'] as String,
  );
  String get passwordKey => 'oxita.onvif.password.v1.${sha256.convert(utf8.encode(identity))}';
  String get identity => [endpoint.trim(), realm.trim(), scheme.trim().toLowerCase(), username.trim()].join('|');
}

class CredentialVault {
  CredentialVault({CredentialStorage? storage}) : _storage = storage ?? FlutterCredentialStorage();
  final CredentialStorage _storage;
  static const indexKey = 'oxita.onvif.credential-index.v1';

  String _normalizeEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
      throw ArgumentError('A verified HTTP(S) ONVIF endpoint is required.');
    }
    return uri.replace(scheme: uri.scheme.toLowerCase(), host: uri.host.toLowerCase()).toString();
  }

  Future<List<CredentialAccount>> listAccounts() async {
    final encoded = await _storage.read(indexKey);
    if (encoded == null || encoded.isEmpty) return const [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) throw const FormatException('Secure credential index is malformed.');
    final accounts = decoded.map((item) {
      if (item is! Map<String, dynamic>) throw const FormatException('Secure credential index contains an invalid entry.');
      return CredentialAccount.fromJson(item);
    }).toList();
    accounts.sort((a, b) {
      final endpointOrder = a.endpoint.compareTo(b.endpoint);
      return endpointOrder != 0 ? endpointOrder : a.username.compareTo(b.username);
    });
    return List.unmodifiable(accounts);
  }

  Future<List<CredentialAccount>> accountsFor({required String endpoint, required String realm, required String scheme}) async {
    final normalized = _normalizeEndpoint(endpoint);
    return (await listAccounts()).where((a) => a.endpoint == normalized && a.realm == realm &&
      a.scheme.toLowerCase() == scheme.toLowerCase()).toList(growable: false);
  }

  Future<String?> readPassword(CredentialAccount account) => _storage.read(account.passwordKey);

  Future<void> save({required String endpoint, required String realm, required String scheme,
    required String username, required String password}) async {
    final normalized = _normalizeEndpoint(endpoint);
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) throw ArgumentError('A non-empty username and password are required.');
    final account = CredentialAccount(endpoint: normalized, realm: realm, scheme: scheme.toLowerCase(), username: cleanUsername);
    final existing = await listAccounts();
    final next = existing.where((item) => item.identity != account.identity).toList()..add(account);
    final previousPassword = await _storage.read(account.passwordKey);
    await _storage.write(account.passwordKey, password);
    try {
      await _storage.write(indexKey, jsonEncode(next.map((item) => item.toJson()).toList()));
    } catch (_) {
      if (previousPassword == null) {
        await _storage.delete(account.passwordKey);
      } else {
        await _storage.write(account.passwordKey, previousPassword);
      }
      rethrow;
    }
  }

  Future<void> delete(CredentialAccount account) async {
    final existing = await listAccounts();
    final next = existing.where((item) => item.identity != account.identity).toList();
    await _storage.write(indexKey, jsonEncode(next.map((item) => item.toJson()).toList()));
    await _storage.delete(account.passwordKey);
  }
}