import 'dart:convert';

class CameraSimulatorFixtures {
  static const sequence = 7;
  static const sender = '192.0.2.50';

  static String contractB({
    int seq = sequence,
    String advertisedIp = sender,
    String scenario = 'normal',
    bool includeMac = true,
  }) {
    if (scenario == 'malformed-json') return '{"magic":"CAM_DISCOVER","version":1,';
    final device = <String, Object?>{
      'ipv4': scenario == 'advertised-mismatch' ? '192.0.2.253' : advertisedIp,
      'netmask': '255.255.255.0',
      'gateway': '192.0.2.1',
      'dns': '1.1.1.1',
      'dhcp': scenario == 'dhcp',
      'http_port': scenario == 'invalid-port' ? 70000 : 18080,
      'rtsp_port': 554,
      'soc': 'SIMULATED-SOC',
      'sensor': 'SIMULATED-SENSOR',
      'firmware_version': 'sim-1.0.0',
      'activated': true,
    };
    if (includeMac && scenario != 'missing-mac') {
      device['mac'] = '02:00:00:00:00:01';
    }
    return jsonEncode({
      'magic': 'CAM_DISCOVER',
      'version': 1,
      'seq': scenario == 'wrong-sequence' ? seq + 1 : seq,
      'cmd': 'PROBE_RESPONSE',
      'device': device,
    });
  }

  static String onvifProbeMatch({
    String senderIp = sender,
    String scenario = 'normal',
  }) {
    var xaddrs = 'http://$senderIp:18080/onvif/device_service';
    if (scenario == 'unsafe-xaddr') {
      xaddrs = 'http://user:pass@$senderIp:18080/onvif/device_service?token=bad';
    } else if (scenario == 'multiple-xaddrs') {
      xaddrs = 'http://198.51.100.7/onvif/device_service $xaddrs';
    }
    return '''<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
 xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
 <e:Body><d:ProbeMatches><d:ProbeMatch>
  <w:EndpointReference><w:Address>urn:uuid:simulated-oxita-camera-0001</w:Address></w:EndpointReference>
  <d:Types>dn:NetworkVideoTransmitter</d:Types>
  <d:Scopes>onvif://www.onvif.org/name/Oxita%20Simulator onvif://www.onvif.org/manufacturer/Oxita onvif://www.onvif.org/hardware/Simulated</d:Scopes>
  <d:XAddrs>$xaddrs</d:XAddrs><d:MetadataVersion>1</d:MetadataVersion>
 </d:ProbeMatch></d:ProbeMatches></e:Body></e:Envelope>''';
  }

  static String soapDeviceInformation({
    String manufacturer = 'Oxita',
    String model = 'Simulator',
    String firmware = 'sim-1.0.0',
    String serial = 'SIM-0001',
  }) => '''<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><s:Body><tds:GetDeviceInformationResponse><tds:Manufacturer>$manufacturer</tds:Manufacturer><tds:Model>$model</tds:Model><tds:FirmwareVersion>$firmware</tds:FirmwareVersion><tds:SerialNumber>$serial</tds:SerialNumber><tds:HardwareId>SIM-HW-1</tds:HardwareId></tds:GetDeviceInformationResponse></s:Body></s:Envelope>''';

  static const soapFault = '''<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><s:Fault><s:Reason><s:Text>Simulated device fault</s:Text></s:Reason></s:Fault></s:Body></s:Envelope>''';
}