import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/onvif_device_service.dart';

String _soapResponse(String operation) {
  if (operation == 'GetDeviceInformation') {
    return '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:GetDeviceInformationResponse><tds:Manufacturer>Oxita</tds:Manufacturer><tds:Model>Authenticated camera</tds:Model></tds:GetDeviceInformationResponse></s:Body></s:Envelope>';
  }
  if (operation == 'GetCapabilities') {
    return '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:GetCapabilitiesResponse/></s:Body></s:Envelope>';
  }
  if (operation == 'GetNetworkInterfaces') {
    return '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:GetNetworkInterfacesResponse/></s:Body></s:Envelope>';
  }
  return '<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:GetDNSResponse><tds:DNSInformation/></tds:GetDNSResponse></s:Body></s:Envelope>';
}

void main() {
  test('replays the SOAP POST body after an HTTP Basic challenge', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var prompts = 0;
    var authenticated = 0;
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final authorization = request.headers.value(HttpHeaders.authorizationHeader);
      if (authorization == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.add(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="Oxita"');
        await request.response.close();
        return;
      }
      authenticated++;
      expect(authorization, 'Basic ${base64Encode(utf8.encode('admin:secret'))}');
      expect(body, contains('<tds:'));
      final operation = RegExp(r'<tds:(GetDeviceInformation|GetCapabilities|GetNetworkInterfaces|GetDNS)>')
          .firstMatch(body)!.group(1)!;
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.response.write(_soapResponse(operation));
      await request.response.close();
    });
    try {
      final service = OnvifDeviceService(requestCredentials: (host, realm, scheme) async {
        prompts++;
        expect(host, '127.0.0.1');
        expect(realm, 'Oxita');
        expect(scheme, 'basic');
        return OnvifCredentials('admin', 'secret', realm: realm, scheme: scheme);
      });
      final device = CameraDevice(
        id: '127.0.0.1', ipAddress: '127.0.0.1',
        deviceServiceUrl: 'http://127.0.0.1:${server.port}/onvif/device_service',
        discoverySources: const ['ONVIF WS-Discovery'],
      );
      final result = await service.refresh(device);
      expect(result.model, 'Authenticated camera');
      expect(prompts, 1);
      expect(authenticated, 4);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('computes HTTP Digest MD5 qop=auth and replays the SOAP body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var prompts = 0;
    var authenticated = 0;
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final authorization = request.headers.value(HttpHeaders.authorizationHeader);
      if (authorization == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.add(
          HttpHeaders.wwwAuthenticateHeader,
          'Digest realm="Oxita", nonce="nonce-123", qop="auth", algorithm=MD5, opaque="opaque-1"',
        );
        await request.response.close();
        return;
      }
      authenticated++;
      expect(authorization, startsWith('Digest '));
      final parameters = <String, String>{};
      final pattern = RegExp(r'(\w+)=("[^"]*"|[^, ]+)');
      for (final match in pattern.allMatches(authorization.substring(7))) {
        final raw = match.group(2) ?? '';
        parameters[match.group(1)!] = raw.startsWith('"') ? raw.substring(1, raw.length - 1) : raw;
      }
      expect(parameters['username'], 'admin');
      expect(parameters['realm'], 'Oxita');
      expect(parameters['nonce'], 'nonce-123');
      expect(parameters['uri'], '/onvif/device_service');
      expect(parameters['qop'], 'auth');
      expect(parameters['opaque'], 'opaque-1');
      final ha1 = md5.convert(utf8.encode('admin:Oxita:secret')).toString();
      final ha2 = md5.convert(utf8.encode('POST:/onvif/device_service')).toString();
      final expected = md5.convert(utf8.encode(
        '$ha1:nonce-123:${parameters['nc']}:${parameters['cnonce']}:auth:$ha2',
      )).toString();
      expect(parameters['response'], expected);
      expect(body, contains('<tds:'));
      final operation = RegExp(r'<tds:(GetDeviceInformation|GetCapabilities|GetNetworkInterfaces|GetDNS)>')
          .firstMatch(body)!.group(1)!;
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.response.write(_soapResponse(operation));
      await request.response.close();
    });
    try {
      final service = OnvifDeviceService(requestCredentials: (host, realm, scheme) async {
        prompts++;
        expect(host, '127.0.0.1');
        expect(realm, 'Oxita');
        expect(scheme, 'digest');
        return OnvifCredentials('admin', 'secret', realm: realm, scheme: scheme);
      });
      final device = CameraDevice(
        id: '127.0.0.1', ipAddress: '127.0.0.1',
        deviceServiceUrl: 'http://127.0.0.1:${server.port}/onvif/device_service',
        discoverySources: const ['ONVIF WS-Discovery'],
      );
      final result = await service.refresh(device);
      expect(result.model, 'Authenticated camera');
      expect(prompts, 1);
      expect(authenticated, 4);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
