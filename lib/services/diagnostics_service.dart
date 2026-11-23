import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/operation_history_entry.dart';
import 'sensitive_data_redactor.dart';

class DiagnosticsService({Directory? logDirectory}) : _logDirectoryOverride = logDirectory;
  final Directory? _logDirectoryOverride;

  static const maxLogBytes = 2 * 1024 * 1024;
  static const retainedArchives = 3;

  Future<Directory> _logDirectory() async {
    if (_logDirectoryOverride != null) {
      if (!await _logDirectoryOverride!.exists()) await _logDirectoryOverride!.create(recursive: true);
      return _logDirectoryOverride!;
    }
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'logs'));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<void> log(String level, String message) async {
    try {
      final directory = await _logDirectory();
      final file = File(p.join(directory.path, 'application.log'));
      if (await file.exists() && await file.length() >= maxLogBytes) {
        final oldest = File('${file.path}.$retainedArchives');
        if (await oldest.exists()) await oldest.delete();
        for (var i = retainedArchives - 1; i >= 1; i--) {
          final source = File('${file.path}.$i');
          if (await source.exists()) {
            await source.rename('${file.path}.${i + 1}');
          }
        }
        if (await file.exists()) await file.rename('${file.path}.1');
      }
      final safe = SensitiveDataRedactor.redact(message);
      final line = '${DateTime.now().toUtc().toIso8601String()} [${level.toUpperCase()}] $safe\n';
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Diagnostics must never interrupt discovery or camera operations.
    }
  }

  Future<String> buildSupportBundle({
    required List<OperationHistoryEntry> history,
    required int deviceCount,
  }) async {
    final out = StringBuffer()
      ..writeln('OXITA CAMERA IP SEARCH MOBILE - DIAGNOSTIC BUNDLE')
      ..writeln('Generated UTC: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln('Application: Oxita Camera IP Search Mobile 0.3.0')
      ..writeln('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
      ..writeln('Dart: ${Platform.version}')
      ..writeln('Architecture: ${Platform.version.split(' ').first}')
      ..writeln()
      ..writeln('PRIVACY')
      ..writeln('This bundle excludes the inventory database, camera credentials and ONVIF interface tokens.')
      ..writeln('It may include local interface addresses, camera target IPs, timestamps and operation details.')
      ..writeln('Redaction is best-effort. Inspect this file before sharing.')
      ..writeln()
      ..writeln('NETWORK INTERFACES (IPv4 ONLY)');

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: true,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          out.writeln('- ${interface.name}: ${address.address}');
        }
      }
    } catch (error) {
      out.writeln('Interface enumeration unavailable: ${SensitiveDataRedactor.redact(error.toString())}');
    }

    out
      ..writeln()
      ..writeln('INVENTORY SUMMARY')
      ..writeln('Saved devices: $deviceCount')
      ..writeln()
      ..writeln('RECENT OPERATIONS (MAX 250)');
    for (final item in history) {
      out.writeln([
        item.occurredAt.toIso8601String(),
        item.operation,
        item.target,
        item.outcome,
        item.details,
      ].map((v) => SensitiveDataRedactor.redact(v, maxLength: 2000)).join(' | '));
    }

    out
      ..writeln()
      ..writeln('RECENT REDACTED APPLICATION LOGS');
    try {
      final directory = await _logDirectory();
      for (final name in [
        'application.log',
        'application.log.1',
        'application.log.2',
        'application.log.3',
      ]) {
        final file = File(p.join(directory.path, name));
        if (!await file.exists()) continue;
        final lines = await file.readAsLines();
        out.writeln('--- $name ---');
        for (final line in lines.skip(lines.length > 250 ? lines.length - 250 : 0)) {
          out.writeln(SensitiveDataRedactor.redact(line));
        }
      }
    } catch (error) {
      out.writeln('Log collection unavailable: ${SensitiveDataRedactor.redact(error.toString())}');
    }
    return out.toString();
  }
}