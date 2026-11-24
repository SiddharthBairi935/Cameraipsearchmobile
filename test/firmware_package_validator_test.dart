import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:camera_ip_search_mobile/services/firmware_package_validator.dart';

void main() {
  const target = FirmwareDeviceIdentity(vendor: 'Acme', productSeries: 'Pro', model: 'AC-200', hardwareRevision: 'Rev B', region: 'IN');
  const bytes = [1, 2, 3, 4, 5];
  FirmwarePackageManifest manifest(List<int> data) => FirmwarePackageManifest(
    vendor: 'Acme', productSeries: 'Pro', model: 'AC-200', hardwareRevision: 'Rev B', region: 'IN',
    version: '2.4.1', sha256: sha256.convert(data).toString(),
  );
  test('accepts exact target metadata and matching SHA-256 without enabling flashing', () {
    final result = FirmwarePackageValidator.validateCandidate(manifest: manifest(bytes), target: target, packageBytes: bytes);
    expect(result.candidateValidated, isTrue);
    expect(result.message, contains('flashing is not enabled'));
  });
  test('rejects hardware revision, region or model mismatch', () {
    final wrong = FirmwareDeviceIdentity(vendor: 'Acme', productSeries: 'Pro', model: 'AC-200', hardwareRevision: 'Rev A', region: 'IN');
    expect(FirmwarePackageValidator.validateCandidate(manifest: manifest(bytes), target: wrong, packageBytes: bytes).state, FirmwareValidationState.targetMismatch);
  });
  test('rejects malformed hash, empty package and hash mismatch', () {
    final good = manifest(bytes);
    expect(FirmwarePackageValidator.validateCandidate(manifest: FirmwarePackageManifest(
      vendor: good.vendor, productSeries: good.productSeries, model: good.model, hardwareRevision: good.hardwareRevision,
      region: good.region, version: good.version, sha256: 'bad'), target: target, packageBytes: bytes).state,
      FirmwareValidationState.invalidPackageHash);
    expect(FirmwarePackageValidator.validateCandidate(manifest: good, target: target, packageBytes: []).state, FirmwareValidationState.emptyPackage);
    expect(FirmwarePackageValidator.validateCandidate(manifest: good, target: target, packageBytes: [9]).state, FirmwareValidationState.packageHashMismatch);
  });
}
