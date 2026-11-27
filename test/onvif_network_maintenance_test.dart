import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/onvif_device_service.dart';
import 'package:camera_ip_search_mobile/services/operation_compatibility.dart';

CameraDevice device(int port, {bool dhcp = false}) => CameraDevice(
  id: '127.0.0.1', ipAddress: '127.0.0.1',
  deviceServiceUrl: 'http://127.0.0.1:$port/onvif/device_service',
  discoverySources: const ['ONVIF WS-Discovery'],
  networkInterfaceToken: 'if0', ipv4ConfigurationKnown: true,
  ipv4Address: '127.0.0.1', ipv4SubnetMask: '255.0.0.0',
  ipv4DhcpEnabled: dhcp,
);

void main() {
  test('DHCP change is accepted only after interface read-back confirms it', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      if (body.contains('SetNetworkInterfaces')) {
        expect(body, contains('<tt:DHCP>true</tt:DHCP>'));
        request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:SetNetworkInterfacesResponse><tds:RebootNeeded>false</tds:RebootNeeded></tds:SetNetworkInterfacesResponse></s:Body></s:Envelope>');
      } else if (body.contains('GetNetworkInterfaces')) {
        request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema"><s:Body><tds:GetNetworkInterfacesResponse><tds:NetworkInterfaces token="if0"><tt:IPv4><tt:Config><tt:DHCP>true</tt:DHCP><tt:FromDHCP><tt:Address>127.0.0.1</tt:Address><tt:PrefixLength>8</tt:PrefixLength></tt:FromDHCP></tt:Config></tt:IPv4></tds:NetworkInterfaces></tds:GetNetworkInterfacesResponse></s:Body></s:Envelope>');
      } else { request.response.statusCode = 400; }
      await request.response.close();
    });
    try {
      final result = await OnvifDeviceService().setDhcp(device(server.port), enabled: true);
      expect(result.verified, isTrue);
      expect(result.device.ipv4DhcpEnabled, isTrue);
      expect(result.device.networkInterfaceToken, 'if0');
    } finally { await subscription.cancel(); await server.close(force: true); }
  });

  test('manual DNS change is verified using GetDNS read-back', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      if (body.contains('SetDNS')) {
        expect(body, contains('<tt:IPv4Address>1.1.1.1</tt:IPv4Address>'));
        request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:SetDNSResponse/></s:Body></s:Envelope>');
      } else if (body.contains('GetDNS')) {
        request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema"><s:Body><tds:GetDNSResponse><tds:DNSInformation><tt:FromDHCP>false</tt:FromDHCP><tt:DNSManual><tt:Type>IPv4</tt:Type><tt:IPv4Address>1.1.1.1</tt:IPv4Address></tt:DNSManual></tds:DNSInformation></tds:GetDNSResponse></s:Body></s:Envelope>');
      } else { request.response.statusCode = 400; }
      await request.response.close();
    });
    try {
      final result = await OnvifDeviceService().setDns(device(server.port), fromDhcp: false, servers: const ['1.1.1.1']);
      expect(result.verified, isTrue);
      expect(result.device.ipv4DnsServer, '1.1.1.1');
    } finally { await subscription.cancel(); await server.close(force: true); }
  });

  test('reboot reports only accepted request and sends no follow-up write', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    final subscription = server.listen((request) async {
      calls++;
      final body = await utf8.decoder.bind(request).join();
      expect(body, contains('SystemReboot'));
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.response.write('<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:SystemRebootResponse><tds:Message>Rebooting</tds:Message></tds:SystemRebootResponse></s:Body></s:Envelope>');
      await request.response.close();
    });
    try {
      final message = await OnvifDeviceService().reboot(device(server.port));
      expect(message, contains('accepted'));
      expect(calls, 1);
    } finally { await subscription.cancel(); await server.close(force: true); }
  });

  test('compatibility evidence separates response, advertised and unimplemented operations', () {
    final entries = OperationCompatibility.evaluate(
      discoverySources: const ['ONVIF GetDeviceInformation'],
      capabilities: const ['Device', 'Media'],
    );
    OperationEvidence find(String label) => entries.singleWhere((e) => e.operation == label);
    expect(find('Read device information').status, OperationEvidenceStatus.deviceResponded);
    expect(find('Configure DHCP').status, OperationEvidenceStatus.authenticationNotVerified);
    expect(find('Preview stream / RTSP URI').status, OperationEvidenceStatus.serviceAdvertisedNotVerified);
    expect(find('Firmware upgrade').status, OperationEvidenceStatus.authenticationNotVerified);
    expect(find('NVR channel management').status, OperationEvidenceStatus.notImplemented);
  });
}
