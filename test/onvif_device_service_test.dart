import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:camera_ip_search_mobile/models/camera_device.dart';
import 'package:camera_ip_search_mobile/services/onvif_device_service.dart';

void main() {
  test('refresh reads ONVIF identity, capabilities, interfaces and manual DNS', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      String response;
      if (body.contains('GetDeviceInformation')) {
        response = '''
          <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
            <s:Body><tds:GetDeviceInformationResponse>
              <tds:Manufacturer>Oxita</tds:Manufacturer><tds:Model>Camera X</tds:Model>
              <tds:FirmwareVersion>2.0.1</tds:FirmwareVersion><tds:SerialNumber>SERIAL-X</tds:SerialNumber>
              <tds:HardwareId>HW-X</tds:HardwareId>
            </tds:GetDeviceInformationResponse></s:Body>
          </s:Envelope>
        ''';
      } else if (body.contains('GetCapabilities')) {
        response = '''
          <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">
            <s:Body><tds:GetCapabilitiesResponse><tds:Capabilities><tt:Device/><tt:Media/><tt:PTZ/></tds:Capabilities></tds:GetCapabilitiesResponse></s:Body>
          </s:Envelope>
        ''';
      } else if (body.contains('GetNetworkInterfaces')) {
        response = '''
          <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">
            <s:Body><tds:GetNetworkInterfacesResponse><tds:NetworkInterfaces token="if0">
              <tt:Info><tt:Name>eth0</tt:Name><tt:HwAddress>AA:BB:CC:DD:EE:FF</tt:HwAddress></tt:Info>
              <tt:IPv4><tt:Config><tt:Manual><tt:Address>127.0.0.1</tt:Address><tt:PrefixLength>8</tt:PrefixLength></tt:Manual>
                <tt:DHCP>false</tt:DHCP><tt:Gateway><tt:IPv4Address>127.0.0.254</tt:IPv4Address></tt:Gateway>
              </tt:Config></tt:IPv4>
            </tds:NetworkInterfaces></tds:GetNetworkInterfacesResponse></s:Body>
          </s:Envelope>
        ''';
      } else if (body.contains('GetDNS')) {
        response = '''
          <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:tt="http://www.onvif.org/ver10/schema">
            <s:Body><tds:GetDNSResponse><tds:DNSInformation>
              <tt:DNSFromDHCP><tt:IPv4Address>8.8.8.8</tt:IPv4Address></tt:DNSFromDHCP>
              <tt:DNSManual><tt:IPv4Address>1.1.1.1</tt:IPv4Address></tt:DNSManual>
            </tds:DNSInformation></tds:GetDNSResponse></s:Body>
          </s:Envelope>
        ''';
      } else {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('application', 'soap+xml', charset: 'utf-8');
      request.response.write(response);
      await request.response.close();
    });

    try {
      final device = CameraDevice(
        id: '127.0.0.1',
        ipAddress: '127.0.0.1',
        deviceServiceUrl: 'http://127.0.0.1:${server.port}/onvif/device_service',
        discoverySources: const ['ONVIF WS-Discovery'],
      );
      final refreshed = await OnvifDeviceService().refresh(device);
      expect(refreshed.manufacturer, 'Oxita');
      expect(refreshed.model, 'Camera X');
      expect(refreshed.firmwareVersion, '2.0.1');
      expect(refreshed.serialNumber, 'SERIAL-X');
      expect(refreshed.hardwareId, 'HW-X');
      expect(refreshed.capabilities, containsAll(['Device', 'Media', 'PTZ']));
      expect(refreshed.networkInterfaceToken, 'if0');
      expect(refreshed.ipv4Address, '127.0.0.1');
      expect(refreshed.ipv4SubnetMask, '255.0.0.0');
      expect(refreshed.ipv4Gateway, '127.0.0.254');
      expect(refreshed.ipv4ConfigurationKnown, isTrue);
      expect(refreshed.ipv4DnsServer, '1.1.1.1');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
