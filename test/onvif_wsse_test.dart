import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/onvif_device_service.dart';
import 'package:camera_ip_search_mobile/services/onvif_wsse.dart';

void main() {
  test('builds a standards-shaped UsernameToken PasswordDigest header', () {
    final nonce = [1, 2, 3, 4, 5];
    const created = '2026-11-27T03:00:00.000Z';
    const password = 'secret';
    final expected = base64Encode(sha1.convert([
      ...nonce, ...utf8.encode(created), ...utf8.encode(password),
    ]).bytes);
    final envelope = OnvifWsse.addUsernameToken(
      '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><x:Probe/></s:Body></s:Envelope>',
      username: 'admin<&',
      password: password,
      nonce: nonce,
      createdUtc: created,
    );
    expect(envelope, contains('<wsse:Username>admin&lt;&amp;</wsse:Username>'));
    expect(envelope, contains('Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">$expected</wsse:Password>'));
    expect(envelope, contains('<wsse:Nonce'));
    expect(envelope, contains('<wsu:Created>$created</wsu:Created>'));
    expect(envelope.indexOf('<s:Header>'), lessThan(envelope.indexOf('<s:Body>')));
  });

  test('retries an authentication SOAP fault with WS-Security PasswordDigest', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var prompted = 0;
    var wsseRequests = 0;
    var authenticated = false;
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final operation = RegExp(r'<tds:(GetDeviceInformation|GetCapabilities|GetNetworkInterfaces|GetDNS)>').firstMatch(body)?.group(1) ?? 'GetDeviceInformation';
      if (body.contains('<wsse:Security')) {
        wsseRequests++;
        authenticated = true;
        final nonceText = RegExp(r'<wsse:Nonce[^>]*>([^<]+)</wsse:Nonce>').firstMatch(body)!.group(1)!;
        final created = RegExp(r'<wsu:Created>([^<]+)</wsu:Created>').firstMatch(body)!.group(1)!;
        final passwordDigest = RegExp(r'<wsse:Password[^>]*>([^<]+)</wsse:Password>').firstMatch(body)!.group(1)!;
        final expected = base64Encode(sha1.convert([
          ...base64Decode(nonceText), ...utf8.encode(created), ...utf8.encode('secret'),
        ]).bytes);
        expect(passwordDigest, expected);
        expect(body, contains('<wsse:Username>admin</wsse:Username>'));
      } else if (!authenticated) {
        request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
        request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><s:Fault><s:Code><s:Value>wsse:FailedAuthentication</s:Value></s:Code><s:Reason><s:Text>Authentication required</s:Text></s:Reason></s:Fault></s:Body></s:Envelope>');
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      final responseBody = operation == 'GetDeviceInformation'
          ? '<tds:Manufacturer>Oxita</tds:Manufacturer><tds:Model>WSSE camera</tds:Model>'
          : '';
      request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:${operation}Response>$responseBody</tds:${operation}Response></s:Body></s:Envelope>');
      await request.response.close();
    });
    try {
      final service = OnvifDeviceService(requestCredentials: (host, realm, scheme, endpoint) async {
        prompted++;
        expect(scheme, 'wsse');
        return const OnvifCredentials('admin', 'secret', scheme: 'wsse');
      });
      final device = CameraDevice(
        id: '127.0.0.1', ipAddress: '127.0.0.1',
        deviceServiceUrl: 'http://127.0.0.1:${server.port}/onvif/device_service',
        discoverySources: const ['ONVIF WS-Discovery'],
      );
      final result = await service.refresh(device);
      expect(result.model, 'WSSE camera');
      expect(prompted, 1);
      expect(wsseRequests, 1);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
