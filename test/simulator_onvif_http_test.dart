import 'dart:io';

import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/onvif_device_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/camera_simulator_fixtures.dart';

void main() {
  Future<void> serve(HttpServer server, String payload, {int status = HttpStatus.ok}) async {
    await for (final request in server) {
      await request.drain<void>();
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      try {
        request.response.write(payload);
        await request.response.close();
      } on SocketException {
        // The ONVIF client intentionally aborts an oversized response stream.
      } on HttpException {
        // The HTTP server may report the same expected client-side abort.
      }
    }
  }

  CameraDevice deviceFor(HttpServer server) => CameraDevice(
    id: '127.0.0.1',
    ipAddress: '127.0.0.1',
    deviceServiceUrl: 'http://127.0.0.1:${server.port}/onvif/device_service',
    discoverySources: const ['ONVIF WS-Discovery'],
  );

  test('rejects simulator SOAP faults without reporting refresh success', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = serve(server, CameraSimulatorFixtures.soapFault);
    try {
      await expectLater(
        OnvifDeviceService().refresh(deviceFor(server)),
        throwsA(isA<OnvifException>().having((e) => e.message, 'message', contains('SOAP fault'))),
      );
    } finally {
      await server.close(force: true);
      await serving;
    }
  });

  test('aborts simulator SOAP responses larger than one MiB', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final oversized = '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">${'x' * (2 * 1024 * 1024)}</s:Envelope>';
    final serving = serve(server, oversized);
    try {
      await expectLater(
        OnvifDeviceService().refresh(deviceFor(server)),
        throwsA(isA<OnvifException>().having((e) => e.message, 'message', contains('exceeds 1 MB'))),
      );
    } finally {
      await server.close(force: true);
      await serving;
    }
  });

  test('accepts valid simulator SOAP identity response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = serve(server, CameraSimulatorFixtures.soapDeviceInformation());
    try {
      final result = await OnvifDeviceService().refresh(deviceFor(server));
      expect(result.manufacturer, 'Oxita');
      expect(result.model, 'Simulator');
      expect(result.serialNumber, 'SIM-0001');
    } finally {
      await server.close(force: true);
      await serving;
    }
  });
}