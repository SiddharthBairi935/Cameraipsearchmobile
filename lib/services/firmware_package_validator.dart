import 'package:crypto/crypto.dart';

class FirmwareDeviceIdentity {
  const FirmwareDeviceIdentity({required this.vendor, required this.productSeries, required this.model, required this.hardwareRevision, required this.region});
  final String vendor, productSeries, model, hardwareRevision, region;
}

class FirmwarePackageManifest {
  const FirmwarePackageManifest({required this.vendor, required this.productSeries, required this.model, required this.hardwareRevision, required this.region, required this.version, required this.sha256});
  final String vendor, productSeries, model, hardwareRevision, region, version, sha256;

  factory FirmwarePackageManifest.fromJson(Map<String, dynamic> json) => FirmwarePackageManifest(
    vendor: json['vendor'] as String? ?? '',
    productSeries: json['productSeries'] as String? ?? '',
    model: json['model'] as String? ?? '',
    hardwareRevision: json['hardwareRevision'] as String? ?? '',
    region: json['region'] as String? ?? '',
    version: json['version'] as String? ?? '',
    sha256: json['sha256'] as String? ?? '',
  );
}

enum FirmwareValidationState { candidateValidated, missingMetadata, targetMismatch, invalidPackageHash, packageHashMismatch, emptyPackage }
class FirmwareValidationResult {
  const FirmwareValidationResult(this.state, this.message);
  final FirmwareValidationState state;
  final String message;
  bool get candidateValidated => state == FirmwareValidationState.candidateValidated;
}

class FirmwarePackageValidator {
  const FirmwarePackageValidator._();

  static FirmwareValidationResult validateCandidate({
    required FirmwarePackageManifest manifest,
    required FirmwareDeviceIdentity target,
    required List<int> packageBytes,
  }) {
    final values = [manifest.vendor, manifest.productSeries, manifest.model, manifest.hardwareRevision, manifest.region, manifest.version,
      target.vendor, target.productSeries, target.model, target.hardwareRevision, target.region];
    if (values.any((v) => v.trim().isEmpty)) {
      return const FirmwareValidationResult(FirmwareValidationState.missingMetadata,
        'Vendor, series, model, hardware revision, region and version are required for both package and target.');
    }
    bool same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();
    if (!same(manifest.vendor, target.vendor) || !same(manifest.productSeries, target.productSeries) ||
        !same(manifest.model, target.model) || !same(manifest.hardwareRevision, target.hardwareRevision) ||
        !same(manifest.region, target.region)) {
      return const FirmwareValidationResult(FirmwareValidationState.targetMismatch,
        'Firmware package does not exactly match the target vendor, series, model, hardware revision and region.');
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(manifest.sha256.trim())) {
      return const FirmwareValidationResult(FirmwareValidationState.invalidPackageHash,
        'Manifest SHA-256 must contain exactly 64 hexadecimal characters.');
    }
    if (packageBytes.isEmpty) {
      return const FirmwareValidationResult(FirmwareValidationState.emptyPackage, 'Firmware package is empty.');
    }
    final actual = sha256.convert(packageBytes).toString();
    if (actual.toLowerCase() != manifest.sha256.trim().toLowerCase()) {
      return const FirmwareValidationResult(FirmwareValidationState.packageHashMismatch,
        'Firmware package SHA-256 does not match its manifest.');
    }
    return const FirmwareValidationResult(FirmwareValidationState.candidateValidated,
      'Metadata and package hash match. Signature verification and an authorized update transport are still required; flashing is not enabled.');
  }
}
