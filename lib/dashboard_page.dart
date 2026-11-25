import 'dart:async';
import 'dart:convert';
import 'dart:io';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/camera_device.dart';
import 'models/operation_history_entry.dart';
import 'services/device_discovery_service.dart';
import 'services/device_classifier.dart';
import 'services/inventory_store.dart';
import 'services/diagnostics_service.dart';
import 'services/onvif_device_service.dart';
import 'services/network_config_validator.dart';
import 'services/ip_assignment_planner.dart';
import 'services/ip_assignment_preflight.dart';
import 'services/batch_operation_service.dart';
import 'services/firmware_package_validator.dart';

class _FirmwareDigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

const red = Color(0xFFC62836), canvas = Color(0xFF171717), surface = Color(0xFF292929), muted = Color(0xFFBDBDBD);

class CameraIpSearchApp extends StatelessWidget {
  const CameraIpSearchApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Oxita Camera Device Manager', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark, surface: surface),
      appBarTheme: AppBarTheme(backgroundColor: surface, foregroundColor: Color(0xFFF4F4F4), elevation: 0, centerTitle: false),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF454545)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Color(0xFF5A252B),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1D1D1D),
        hintStyle: const TextStyle(color: Color(0xFFBDBDBD)),
        labelStyle: const TextStyle(color: Color(0xFFBDBDBD)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFF626262))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: Color(0xFF626262))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: red, width: 1.4)),
      ),
    ),
    home: const DashboardPage(),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with WidgetsBindingObserver {
  late final DeviceDiscoveryService discovery;
  final store = InventoryStore();
  final diagnostics = DiagnosticsService();
  final batchRunner = BatchOperationRunner();
  List<OperationHistoryEntry> historyEntries = [];
  final search = TextEditingController();
  final selected = <String>{};
  List<NetworkInterface> interfaces = [];
  Map<String, dynamic>? nativeInterfaceDetails;
  int tab = 1;
  bool loading = true, checking = false, batchRunning = false;
  String batchProgress = '';
  String databaseIntegrity = 'Checking…';
  String? interfaceName, focusedDeviceKey;
  String manufacturerFilter = 'All manufacturers', statusFilter = 'All statuses', deviceTypeFilter = 'All device types';
  String reachabilityProgress = '', subnetProgress = '';
  String? _lastInventorySnapshot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    discovery = DeviceDiscoveryService(
      onvifService: OnvifDeviceService(requestCredentials: _credentials),
      onOperation: (operation, target, outcome, details) =>
          unawaited(_record(operation, target, outcome, details)),
    );
    discovery.addListener(_changed);
    unawaited(_load());
  }

  Future<OnvifCredentials?> _credentials(String host, String realm, String scheme) async {
    final user = TextEditingController(), pass = TextEditingController();
    final value = await showDialog<OnvifCredentials>(context: context, builder: (context) => AlertDialog(
      title: const Text('Camera authentication'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$scheme authentication requested by $host. Credentials remain in memory for this app session only.'),
        TextField(controller: user, decoration: const InputDecoration(labelText: 'Username')),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, OnvifCredentials(user.text, pass.text, realm: realm, scheme: scheme)), child: const Text('Continue'))],
    ));
    user.dispose(); pass.dispose(); return value;
  }

  Future<void> _load() async {
    try {
      final saved = await store.load();
      final integrity = await store.integrityCheck();
      if (integrity.toLowerCase() != 'ok') throw StateError('SQLite integrity check failed: $integrity');
      final history = await store.loadHistory();
      final found = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: true);
      if (!mounted) return;
      for (final d in saved) { discovery.restoreDevice(d); }
      _lastInventorySnapshot = jsonEncode(discovery.devices.map((d) => d.toJson()).toList());
      setState(() { interfaces = found; interfaceName = found.isEmpty ? null : found.first.name; historyEntries = history; databaseIntegrity = integrity; loading = false; });
      await _loadNativeInterfaceDetails(interfaceName);
    } catch (e) { if (mounted) setState(() { loading = false; databaseIntegrity = 'Check failed'; }); _msg('Inventory load failed: $e'); }
  }

  void _changed() {
    if (mounted) setState(() {});
    if (loading) return;
    final snapshot = jsonEncode(discovery.devices.map((d) => d.toJson()).toList());
    if (snapshot != _lastInventorySnapshot) {
      _lastInventorySnapshot = snapshot;
      unawaited(store.save(discovery.devices));
    }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (discovery.isScanning) unawaited(discovery.cancelDiscovery());
      if (discovery.isSubnetScanning) discovery.cancelSubnetScan();
      if (checking) discovery.cancelReachability();
    }
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); discovery.removeListener(_changed); discovery.dispose(); unawaited(store.close()); search.dispose(); super.dispose(); }
  NetworkInterface? get activeInterface {
    for (final item in interfaces) {
      if (item.name == interfaceName) return item;
    }
    return null;
  }

  Future<void> _loadNativeInterfaceDetails(String? name) async {
    if (name == null || name.isEmpty) {
      if (mounted) setState(() => nativeInterfaceDetails = null);
      return;
    }
    try {
      final details = await const MethodChannel(
        'com.oxita.camera_ip_search_mobile/local_network',
      ).invokeMapMethod<String, dynamic>(
        'getNetworkInterfaceDetails',
        {'interfaceName': name},
      );
      if (mounted) setState(() => nativeInterfaceDetails = details);
    } catch (error) {
      if (mounted) {
        setState(() => nativeInterfaceDetails = {
          'available': false,
          'error': error.toString(),
        });
      }
      await diagnostics.log('warning', 'Native interface diagnostics unavailable: $error');
    }
  }

  String _defaultSubnetCidr() {
    final network = activeInterface;
    if (network == null) return '';
    for (final address in network.addresses) {
      if (address.type != InternetAddressType.IPv4) continue;
      try {
        final dynamic details = address;
        final prefix = details.prefixLength;
        if (prefix is int && prefix >= 1 && prefix <= 30) return '${address.address}/$prefix';
      } on NoSuchMethodError {
        // Older Dart SDKs do not expose InterfaceAddress.prefixLength.
      }
    }
    return '';
  }

  String _interfaceAddressSummary(NetworkInterface? network) {
    if (network == null) return 'Select an active IPv4 interface';
    return network.addresses.map((address) {
      final fields = <String>[address.address];
      try {
        final dynamic details = address;
        fields.add('/${details.prefixLength}');
        final broadcast = details.broadcast;
        if (broadcast is InternetAddress) fields.add('broadcast ${broadcast.address}');
      } on NoSuchMethodError {
        // Older supported Dart SDKs expose only the interface IP.
      }
      return fields.join(' ');
    }).join(' · ');
  }

  String _key(CameraDevice d) => d.macAddress.isNotEmpty ? d.macAddress : d.id;
  void _msg(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  Future<void> _record(String operation, String target, String outcome, String details) async {
    try {
      await store.recordOperation(operation: operation, target: target, outcome: outcome, details: details);
      await diagnostics.log(outcome.toLowerCase() == 'failed' ? 'error' : 'info',
          '$operation | $target | $outcome | $details');
      final entries = await store.loadHistory();
      if (mounted) setState(() => historyEntries = entries);
    } catch (error) {
      await diagnostics.log('error', 'Operation history write failed: $error');
    }
  }

  Future<void> _refreshHistory() async {
    try {
      final entries = await store.loadHistory();
      if (mounted) setState(() => historyEntries = entries);
    } catch (error) {
      _msg('Could not load operation history: $error');
    }
  }

  Future<void> _refreshDevice(CameraDevice device) async {
    try {
      await discovery.refreshDeviceInfo(device);    } catch (error) {
      _msg('Device refresh failed: $error');
    }
  }

  List<CameraDevice> get visible => discovery.devices.where((d) {
    final q = search.text.trim().toLowerCase();
    final match = q.isEmpty || [d.ipAddress,d.macAddress,d.manufacturer,d.model,d.serialNumber,d.hardwareId,d.userLabel,d.firmwareVersion].any((v)=>v.toLowerCase().contains(q));
    final vendor = switch (manufacturerFilter) {
      'ONVIF devices' => d.discoverySources.any((s)=>s.startsWith('ONVIF')),
      'Oxita devices' => d.manufacturer.toLowerCase() == 'oxita',
      'Other / unknown' => !d.discoverySources.any((s)=>s.startsWith('ONVIF')) && d.manufacturer.toLowerCase() != 'oxita',
      _ => true,
    };
    final classification = DeviceClassifier.classify(d);
    final typeMatch = deviceTypeFilter == 'All device types' || classification.key == deviceTypeFilter.toLowerCase();
    final status = switch (statusFilter) {
      'Online' => d.reachabilityStatus == 'Reachable',
      'Activated' => d.activationState == 'Activated',
      'Not activated' => d.activationState == 'Not activated',
      'Unverified candidates' => d.isCandidate,
      _ => true,
    };
    return match && vendor && status && typeMatch;
  }).toList();

  Future<void> _discover() async {
    if (discovery.isScanning) { await discovery.cancelDiscovery(); return; }
    await discovery.startDiscovery(interfaceName: interfaceName ?? '');
  }

  Future<String?> _ask(String title, String label, {String initial = '', String hint = ''}) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: label, hintText: hint)),
      actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: ()=>Navigator.pop(context,c.text.trim()), child: const Text('Continue'))]));
    c.dispose(); return value;
  }

  Future<void> _manual() async {
    final value = await _ask('Add device manually','Camera IP address or hostname',hint:'192.168.1.100 or camera.local');
    if (value == null || !mounted) return;
    try {
      await discovery.addManualDevice(value);
      await _record('Manual device entry', value, 'Completed', 'Device added to local inventory.');
    } on FormatException catch(e) {
      await _record('Manual device entry', value, 'Failed', e.message);
      _msg(e.message);
    }
  }

  Future<void> _subnet() async {
    if (discovery.isSubnetScanning) { discovery.cancelSubnetScan(); return; }
    final value = await _ask('Scan selected subnet','Selected interface IPv4 / prefix',initial:_defaultSubnetCidr(),hint:'192.168.1.20/24');
    if (value == null || !mounted) return;
    try {
      final p = value.split('/'), ip = InternetAddress.tryParse(p.first), prefix = p.length == 2 ? int.tryParse(p[1]) : null;
      if (activeInterface == null) throw const FormatException('Select an active network interface first.');
      if (ip == null || ip.type != InternetAddressType.IPv4 || ip.isLoopback || ip.isMulticast || prefix == null || prefix < 1 || prefix > 30) throw const FormatException('Enter a valid IPv4 CIDR, e.g. 192.168.1.20/24.');
      if (!activeInterface!.addresses.any((a) => a.address == ip.address)) throw const FormatException('The CIDR address must belong to the selected network interface.');
      final m = (0xffffffff << (32-prefix)) & 0xffffffff;
      final mask = InternetAddress.fromRawAddress(Uint8List.fromList([(m>>24)&255,(m>>16)&255,(m>>8)&255,m&255]));
      await discovery.scanSubnet(ip,mask,interfaceName: interfaceName ?? '',onProgress:(done,total,candidates){ if(mounted)setState(()=>subnetProgress='Subnet: $done/$total · $candidates candidates'); });
      if(mounted)setState(()=>subnetProgress='');
    } on FormatException catch(e) {
      await _record('Subnet scan', interfaceName ?? '', 'Failed', e.message);
      _msg(e.message);
    }
  }

  Future<void> _reachability() async {
    if (checking) { discovery.cancelReachability(); return; }
    final targets = selected.isEmpty ? visible : discovery.devices.where((d)=>selected.contains(_key(d))).toList();
    if (targets.isEmpty) { _msg('Add or discover devices first.'); return; }
    setState(()=>checking=true);
    final count = await discovery.checkReachabilityBatch(targets,onProgress:(done,total,d){if(mounted)setState(()=>reachabilityProgress='Reachability: $done/$total · ${d.ipAddress}');});
    if(mounted)setState(() { checking=false; reachabilityProgress=''; selected.clear(); });
    _msg('Checked $count device(s).');
  }

  Future<void> _rename(CameraDevice d) async {
    final value = await _ask('Rename device label','Device label',initial:d.userLabel,hint:'Front gate camera');
    if(value != null && mounted) {
      discovery.updateDevice(d.copyWith(userLabel:value));
      await _record('Device label', d.ipAddress, 'Completed', 'Local device label updated.');
    }
  }

  Future<void> _export() async {
    final exportDevices = List<CameraDevice>.unmodifiable(discovery.devices);
    final rows = <List<String>>[
      ['IP ADDRESS','DESCRIPTION','MANUFACTURER','MODEL','MAC','FIRMWARE','STATUS','SOURCE','SERIAL','HARDWARE ID','REACHABILITY','INTERFACES','CAPABILITIES','OPEN PORTS','CAMERA IPV4','MASK','GATEWAY','DNS','DHCP','ONVIF ENDPOINT','SERVICE URL'],
      ...exportDevices.map((d)=>[d.ipAddress,d.userLabel,d.manufacturer,d.model,d.macAddress,d.firmwareVersion,d.activationState,d.discoverySources.join('; '),d.serialNumber,d.hardwareId,d.reachabilityStatus,d.networkSummary,d.capabilities.join('; '),d.openPorts.join('; '),d.ipv4Address,d.ipv4SubnetMask,d.ipv4Gateway,d.ipv4DnsServer,d.ipv4DhcpEnabled.toString(),d.onvifEndpoint,d.deviceServiceUrl])
    ];
    String field(String v)=>'"${v.replaceAll('"','""')}"';
    final dir=await getTemporaryDirectory(), file=File('${dir.path}/oxita-camera-inventory.csv');
    await file.writeAsString('\uFEFF${rows.map((r)=>r.map(field).join(',')).join('\r\n')}\r\n',flush:true);
    await Share.shareXFiles([XFile(file.path)],text:'Oxita camera inventory');
    await _record('Inventory export', 'oxita-camera-inventory.csv', 'Prepared', '${exportDevices.length} device row(s) from the complete inventory exported.');
  }

  Future<void> _previewStaticIpv4(CameraDevice d) async {
    if (!d.ipv4ConfigurationKnown || d.networkInterfaceToken.isEmpty) {
      _msg('Refresh this camera first. A verified ONVIF interface token and current IPv4 details are required.');
      return;
    }
    final ip = TextEditingController(text: d.ipv4Address);
    final mask = TextEditingController(text: d.ipv4SubnetMask);
    final gateway = TextEditingController(text: d.ipv4Gateway);
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(
      title: const Text('Preview static IPv4'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Current camera IP: ${d.ipAddress}', style: const TextStyle(color: muted)),
        TextField(controller: ip, decoration: const InputDecoration(labelText: 'Proposed IPv4 address')),
        TextField(controller: mask, decoration: const InputDecoration(labelText: 'Subnet mask')),
        TextField(controller: gateway, decoration: const InputDecoration(labelText: 'Gateway (optional)')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, [ip.text, mask.text, gateway.text]), child: const Text('Validate preview')),
      ],
    ));
    ip.dispose(); mask.dispose(); gateway.dispose();
    if (values == null) return;
    final error = NetworkConfigValidator.validateStaticIpv4(
      address: values[0], subnetMask: values[1], gateway: values[2],
    );
    if (error != null) { _msg(error); return; }
    final proposed = InternetAddress.tryParse(values[0]);
    if (proposed != null) {
      final reserved = <String>{};
      for (final network in interfaces) {
        for (final address in network.addresses) { if (address.type == InternetAddressType.IPv4) reserved.add(address.address); }
      }
      for (final other in discovery.devices) {
        if (_key(other) == _key(d)) continue;
        if (other.ipAddress.isNotEmpty) reserved.add(other.ipAddress);
        if (other.ipv4Gateway.isNotEmpty) reserved.add(other.ipv4Gateway);
        if (other.ipv4DnsServer.isNotEmpty) reserved.add(other.ipv4DnsServer);
      }
      if (reserved.contains(proposed.address) && proposed.address != d.ipAddress) {
        _msg('The proposed address is already reserved by a local interface or another inventory device, gateway or DNS server.');
        return;
      }
    }
    if (!mounted) return;
    await _record('Static IPv4 preview', d.ipAddress, 'Validated', 'Local validation passed for proposed address ${values[0]}; no camera request was sent.');
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Static IPv4 preview'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _detail('Current IP', d.ipAddress),
        _detail('Proposed IP', values[0]),
        _detail('Subnet mask', values[1]),
        _detail('Gateway', values[2].isEmpty ? 'Unchanged' : values[2]),
        _detail('Interface token', d.networkInterfaceToken),
        const SizedBox(height: 8),
        const Text('The values passed local validation. No ONVIF request was sent and the camera has not been changed. DNS is not modified by this operation.', style: TextStyle(color: muted, fontSize: 12)),
      ]),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Future<void> _help() async {
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Camera Device Manager help'),
      content: const SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Discovery', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('ONVIF WS-Discovery and Oxita Contract B run on the selected local IPv4 interface. Discovery may not find every camera on segmented networks.'),
        SizedBox(height: 10),
        Text('Subnet scan', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('The bounded TCP scan finds candidate hosts. An open port is reachability evidence, not proof of camera identity or ONVIF support.'),
        SizedBox(height: 10),
        Text('Device information', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('Refresh device info queries the camera ONVIF service. Authentication credentials are session-only.'),
        SizedBox(height: 10),
        Text('Network configuration', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('Static IPv4 changes require a verified ONVIF interface token. Preview validates values without sending a request. Applying may interrupt connectivity; there is no automatic rollback.'),
        SizedBox(height: 10),
        Text('Camera maintenance', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('ONVIF factory reset supports explicit Soft/Hard requests when the camera exposes and authorizes SetSystemFactoryDefault. It can erase settings and change the camera IP. Reboot, activation, NVR channels and firmware flashing remain unavailable.'),
        SizedBox(height: 10),
        Text('Bulk IPv4', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('Desktop main supports sequential bulk static IPv4 assignment after a complete preview and per-camera conflict checks. Mobile keeps execution blocked unless a platform probe can positively establish that each address is clear; unknown is never treated as free.'),
      ])),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  Future<void> _factoryReset(CameraDevice device) async {
    if (!device.discoverySources.any((source) => source.startsWith('ONVIF')) ||
        device.deviceServiceUrl.isEmpty) {
      _msg('Factory reset requires a verified ONVIF camera. Refresh device information first.');
      return;
    }
    var mode = 'Soft';
    final selectedMode = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Choose factory-reset mode'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Target: ${device.ipAddress} · ${device.manufacturer} · ${device.model}'),
          const SizedBox(height: 12),
          RadioGroup<String>(
            groupValue: mode,
            onChanged: (value) => setDialogState(() => mode = value ?? 'Soft'),
            child: Column(
              children: const [
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'Soft',
                  title: Text('Soft reset'),
                  subtitle: Text('Restore device settings while retaining factory-default behavior defined by the camera'),
                ),
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: 'Hard',
                  title: Text('Hard reset'),
                  subtitle: Text('Request the camera’s hard factory-default mode; support varies by model'),
                ),
              ],
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, mode), child: const Text('Continue')),
        ],
      )),
    );
    if (selectedMode == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm destructive camera reset'),
        content: Text(
          'Send ONVIF SetSystemFactoryDefault ($selectedMode) to ${device.ipAddress}? '
          'This may erase configuration, reset credentials, interrupt video and change the camera IP. '
          'There is no automatic rollback. The camera must explicitly support and authorize this ONVIF operation.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC62836)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send reset request'),
          ),
        ],
      ),    );
    if (confirmed != true || !mounted) return;
    try {
      final message = await discovery.factoryReset(device, factoryDefaultType: selectedMode);
      await _record('Factory reset', device.ipAddress, 'Accepted', message);
      _msg(message);
    } on OnvifException catch (error) {
      await _record('Factory reset', device.ipAddress, 'Failed', error.message);
      _msg(error.message);
    } catch (error) {
      await _record('Factory reset', device.ipAddress, 'Failed', error.toString());
      _msg('Factory reset request failed: $error');
    }
  }

  Future<void> _staticIp(CameraDevice d) async {
    if (!d.ipv4ConfigurationKnown || d.networkInterfaceToken.isEmpty) { _msg('No verified matching ONVIF interface token.'); return; }
    final ip=TextEditingController(text:d.ipv4Address), mask=TextEditingController(text:d.ipv4SubnetMask), gw=TextEditingController(text:d.ipv4Gateway);
    final values=await showDialog<List<String>>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Static IPv4 configuration'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        Text('Camera ${d.ipAddress} · interface token ${d.networkInterfaceToken}',style:const TextStyle(color:muted)),
        TextField(controller:ip,decoration:const InputDecoration(labelText:'IPv4 address')),
        TextField(controller:mask,decoration:const InputDecoration(labelText:'Subnet mask')),
        TextField(controller:gw,decoration:const InputDecoration(labelText:'Gateway (optional)')),
        const SizedBox(height:8),const Text('The camera may disconnect. There is no automatic rollback.',style:TextStyle(color:Color(0xFFE6B45D),fontSize:12)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(context,[ip.text,mask.text,gw.text]),child:const Text('Review'))]));
    ip.dispose();mask.dispose();gw.dispose();
    if(values==null || !mounted)return;
    final validation = NetworkConfigValidator.validateStaticIpv4(address: values[0], subnetMask: values[1], gateway: values[2]);
    if (validation != null) { _msg(validation); return; }
    final proposed = InternetAddress.tryParse(values[0]);
    final reserved = <String>{...interfaces.expand((n)=>n.addresses.where((a)=>a.type==InternetAddressType.IPv4).map((a)=>a.address))};
    for (final other in discovery.devices) {
      if (_key(other) == _key(d)) continue;
      if (other.ipAddress.isNotEmpty) reserved.add(other.ipAddress);
      if (other.ipv4Gateway.isNotEmpty) reserved.add(other.ipv4Gateway);
      if (other.ipv4DnsServer.isNotEmpty) reserved.add(other.ipv4DnsServer);
    }
    if (proposed != null && proposed.address != d.ipAddress && reserved.contains(proposed.address)) {
      _msg('Address is already used by a local interface or another inventory device, gateway or DNS server.');
      return;
    }
    final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(
      title:const Text('Confirm network change'),
      content:Text('Apply ${values[0]} / ${values[1]} to ${d.ipAddress}? The app will verify the new IP before updating inventory.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Go back')),
        FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Apply'))]));
    if(ok!=true || !mounted)return;
    try {
      final result=await discovery.applyStaticIpv4(d,address:values[0],subnetMask:values[1],gateway:values[2]);
      await store.save(discovery.devices);
      await _record('Static IPv4', d.ipAddress, result.verified ? 'Verified' : 'Not verified', result.message);
      _msg(result.message);
    } on OnvifException catch(e) {
      await _record('Static IPv4', d.ipAddress, 'Failed', e.message);
      _msg(e.message);
    }
  }

  Future<void> _batchRefresh() async {
    if (batchRunning) {
      batchRunner.cancel();
      if (mounted) setState(() => batchProgress = 'Cancellation requested…');
      return;
    }
    final targets = selected.isEmpty
        ? visible
        : discovery.devices.where((d) => selected.contains(_key(d))).toList();
    if (targets.isEmpty) {
      _msg('Select or discover at least one device first.');
      return;
    }
    final preflight = const BatchOperationPreflight().build(
      targets, DeviceBatchOperation.readDeviceInformation,
    );
    final blocked = preflight.where((r) => r.state != BatchTargetState.ready).length;
    if (blocked == targets.length) {
      _msg('No selected device has a verified ONVIF read adapter. Review device identity and discovery evidence.');
      return;
    }
    setState(() { batchRunning = true; batchProgress = 'Preparing ${targets.length} device(s)…'; });
    await _record('Batch preflight', 'Device information', 'Prepared',
        '${targets.length - blocked} ready; $blocked blocked. Sequential execution only.');
    try {
      final results = await batchRunner.start(
        devices: targets,
        operation: DeviceBatchOperation.readDeviceInformation,
        handler: (device, _) async {
          if (mounted) setState(() => batchProgress = 'Refreshing ${device.ipAddress} · ${batchRunner.completedCount + 1}/${batchRunner.totalCount}');
          try {
            await discovery.refreshDeviceInfo(device);
            await _record('Batch device information', device.ipAddress, 'Completed', 'ONVIF information refresh completed.');
            return null;
          } catch (error) {
            await _record('Batch device information', device.ipAddress, 'Failed', error.toString());
            return error.toString();
          }
        },
      );
      final succeeded = results.where((r) => r.state == BatchTargetState.succeeded).length;
      final failed = results.length - succeeded;
      await _record('Batch device information', 'Selected devices', 'Completed',
          '$succeeded succeeded; $failed skipped or failed.');
      if (mounted) _msg('Batch refresh finished: $succeeded succeeded, $failed skipped or failed.');
    } catch (error) {
      await _record('Batch device information', 'Selected devices', 'Failed', error.toString());
      if (mounted) _msg('Batch refresh failed: $error');
    } finally {
      if (mounted) setState(() { batchRunning = false; batchProgress = ''; selected.clear(); });
    }
  }

  Future<IpAddressProbeResult> _probeIpv4Conflict(String address) async {
    if (Platform.isIOS) {
      return const IpAddressProbeResult(IpAddressProbeState.unknown,
        'No validated iOS interface-scoped conflict-probe backend is available.');
    }
    try {
      final result = await const MethodChannel(
        'com.oxita.camera_ip_search_mobile/local_network',
      ).invokeMapMethod<String, dynamic>('probeIpv4Conflict', {
        'address': address,
        'interfaceName': interfaceName ?? '',
      });
      final state = result?['state'] as String? ?? 'unknown';
      final evidence = result?['evidence'] as String? ?? 'No probe evidence returned.';
      return IpAddressProbeResult(
        state == 'conflict' ? IpAddressProbeState.conflict : IpAddressProbeState.unknown,
        evidence,
      );
    } catch (error) {
      return IpAddressProbeResult(IpAddressProbeState.unknown,
        'Platform conflict probe unavailable: $error');
    }
  }

  Future<void> _previewIpAssignmentPlan() async {
    final targets = discovery.devices.where((d) => selected.contains(_key(d))).toList();
    if (targets.isEmpty) {
      _msg('Select at least one camera in Devices before creating an assignment plan.');
      return;
    }
    if (targets.length > 256) {
      _msg('Bulk IPv4 is limited to 256 cameras per operation.');
      return;
    }
    final start = TextEditingController();
    final end = TextEditingController();
    final mask = TextEditingController(text: '255.255.255.0');
    final values = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(
      title: const Text('Plan multi-camera IPv4 addresses'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Sequential operation for ${targets.length} selected camera(s). Each camera is checked immediately before its own write.', style: const TextStyle(color: muted, fontSize: 12)),
        TextField(controller: start, decoration: const InputDecoration(labelText: 'Range start')),
        TextField(controller: end, decoration: const InputDecoration(labelText: 'Range end')),
        TextField(controller: mask, decoration: const InputDecoration(labelText: 'Subnet mask')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, [start.text.trim(), end.text.trim(), mask.text.trim()]), child: const Text('Build plan')),
      ],
    ));
    start.dispose(); end.dispose(); mask.dispose();
    if (values == null || !mounted) return;
    try {
      final reserved = _reservedIpv4Addresses();
      final plan = IpAssignmentPlanner.build(
        startAddress: values[0], endAddress: values[1], subnetMask: values[2],
        selectedDevices: targets.map((d) => IpAssignmentTarget(deviceId: d.id, currentAddress: d.ipAddress)).toList(),
        reservedAddresses: reserved,
      );
      final preflight = await const IpAssignmentPreflight().evaluate(
        plan: plan.targets, inventoryAddresses: reserved, probe: _probeIpv4Conflict,
      );
      final ready = preflight.where((r) => r.state == IpAssignmentPreflightState.ready).length;
      final allReady = ready == plan.targets.length;
      final report = preflight.map((r) =>
        '${r.target.currentAddress} → ${r.target.proposedAddress}\n${r.state.name}: ${r.message}').join('\n\n');
      await _record('IP assignment plan', 'Selected devices', 'Previewed',
          '${plan.targets.length} proposed address(es); $ready passed preflight. No changes sent.');
      if (!mounted) return;
      final apply = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Assignment plan · preflight'),
        content: SizedBox(width: 560, child: SingleChildScrollView(child: SelectableText(
          '$report\n\n${allReady
            ? 'All targets passed the current preflight. The app will repeat the address check immediately before each sequential camera write. There is no automatic rollback if a camera disconnects.'
            : 'Execution is blocked. Every target must have a verified clear result. An unknown/no-response result is not proof that an address is free.'}',
          style: const TextStyle(fontSize: 12, height: 1.45),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
          if (allReady)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm sequential assignment'),
            ),
        ],
      ));
      if (apply != true || !mounted) return;
      await _applyIpAssignmentPlan(plan, targets);
    } on FormatException catch (error) {
      await _record('IP assignment plan', 'Selected devices', 'Failed', error.message);
      _msg(error.message);
    } catch (error) {
      await _record('IP assignment plan', 'Selected devices', 'Failed', error.toString());
      _msg('Could not build assignment plan: $error');
    }
  }

  Set<String> _reservedIpv4Addresses() {
    final reserved = <String>{};
    for (final device in discovery.devices) {
      if (device.ipAddress.isNotEmpty) reserved.add(device.ipAddress);
      if (device.ipv4Gateway.isNotEmpty) reserved.add(device.ipv4Gateway);
      if (device.ipv4DnsServer.isNotEmpty) reserved.add(device.ipv4DnsServer);
    }
    for (final network in interfaces) {
      for (final address in network.addresses) {
        if (address.type == InternetAddressType.IPv4) reserved.add(address.address);
      }
    }
    return reserved;
  }

  Future<void> _applyIpAssignmentPlan(IpAssignmentPlan plan, List<CameraDevice> originalTargets) async {
    var succeeded = 0;
    var blocked = 0;
    var failed = 0;
    for (var index = 0; index < plan.targets.length; index++) {
      final target = plan.targets[index];
      CameraDevice? device;
      for (final candidate in discovery.devices) {
        if (candidate.id == target.deviceId) {
          device = candidate;
          break;
        }
      }
      if (device == null) {
        for (final candidate in originalTargets) {
          if (candidate.id == target.deviceId) {
            device = candidate;
            break;
          }
        }
      }
      final targetDevice = device;      if (targetDevice == null || !targetDevice.ipv4ConfigurationKnown || targetDevice.networkInterfaceToken.isEmpty) {
        blocked++;
        await _record('Bulk static IPv4', target.currentAddress, 'Blocked',
          'A current device record with a verified ONVIF interface token is required.');
        continue;
      }
      if (mounted) {
        setState(() {
          batchRunning = true;
          batchProgress = 'Rechecking ${target.proposedAddress} · ${index + 1}/${plan.targets.length}';
        });
      }
      final latestReserved = _reservedIpv4Addresses()
        ..remove(targetDevice.ipAddress);
      final check = await const IpAssignmentPreflight().evaluate(
        plan: [target],
        inventoryAddresses: latestReserved,
        probe: _probeIpv4Conflict,
      );
      if (check.single.state != IpAssignmentPreflightState.ready) {
        blocked++;
        await _record('Bulk static IPv4', target.currentAddress, 'Blocked',
          'Last-moment conflict check: ${check.single.message}');
        continue;
      }
      if (mounted) {
        setState(() => batchProgress =
          'Configuring ${targetDevice.ipAddress} → ${target.proposedAddress} · ${index + 1}/${plan.targets.length}');
      }
      try {
        final result = await discovery.applyStaticIpv4(
          targetDevice, address: target.proposedAddress, subnetMask: plan.subnetMask,
        );
        await store.save(discovery.devices);
        if (result.verified) {
          succeeded++;
          await _record('Bulk static IPv4', target.currentAddress, 'Verified', result.message);
        } else {
          failed++;
          await _record('Bulk static IPv4', target.currentAddress, 'Partial', result.message);
        }
      } on OnvifException catch (error) {
        failed++;
        await _record('Bulk static IPv4', target.currentAddress, 'Failed', error.message);
      } catch (error) {
        failed++;
        await _record('Bulk static IPv4', target.currentAddress, 'Failed', error.toString());
      }
    }
    await store.save(discovery.devices);
    await _record('Bulk static IPv4 batch', 'Selected cameras', 'Finished',
      '$succeeded verified; $blocked blocked by preflight; $failed failed or partially applied. No automatic rollback is available.');
    if (mounted) {
      setState(() { batchRunning = false; batchProgress = ''; selected.clear(); });
      _msg('Bulk IPv4 finished: $succeeded verified, $blocked blocked, $failed failed/partial.');
    }
  }

  Future<void> _validateFirmwareCandidate(CameraDevice device) async {
    final manifestPick = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['json'], withData: true,
    );
    if (manifestPick == null || manifestPick.files.isEmpty || !mounted) return;
    final packagePick = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (packagePick == null || packagePick.files.isEmpty || !mounted) return;
    final manifestFile = manifestPick.files.single;
    final packageFile = packagePick.files.single;
    try {
      if (packageFile.size <= 0) throw const FormatException('Firmware package is empty.');
      if (packageFile.size > 64 * 1024 * 1024) throw const FormatException('For safety, candidate validation is limited to 64 MiB per package on mobile.');
      final manifestBytes = manifestFile.bytes ?? (manifestFile.path == null ? null : await File(manifestFile.path!).readAsBytes());
      if (manifestBytes == null || manifestBytes.length > 1024 * 1024) throw const FormatException('Manifest could not be read or exceeds the 1 MiB limit.');
      final decoded = jsonDecode(utf8.decode(manifestBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException('Manifest must be a JSON object.');
      final manifest = FirmwarePackageManifest.fromJson(decoded);
      final series = TextEditingController();
      final revision = TextEditingController();
      final region = TextEditingController();
      if (!mounted) return;
      final targetValues = await showDialog<List<String>>(context: context, builder: (context) => AlertDialog(
        title: const Text('Confirm camera hardware identity'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _detail('Vendor', device.manufacturer), _detail('Model', device.model),
          TextField(controller: series, decoration: const InputDecoration(labelText: 'Product series (verify from label)')),
          TextField(controller: revision, decoration: const InputDecoration(labelText: 'Hardware revision (verify from label)')),
          TextField(controller: region, decoration: const InputDecoration(labelText: 'Region (verify from label)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, [series.text.trim(), revision.text.trim(), region.text.trim()]), child: const Text('Validate candidate')),
        ],
      ));
      series.dispose(); revision.dispose(); region.dispose();
      if (targetValues == null || !mounted) return;
      final stream = packageFile.readStream ??
          (packageFile.path == null ? null : File(packageFile.path!).openRead());
      if (stream == null) throw const FormatException('The selected package does not expose a readable stream on this platform.');
      final digestSink = _FirmwareDigestSink();
      final digestInput = sha256.startChunkedConversion(digestSink);
      var packageLength = 0;
      await for (final chunk in stream) {
        packageLength += chunk.length;
        if (packageLength > 64 * 1024 * 1024) {
          digestInput.close();
          throw const FormatException('Firmware package exceeds the 64 MiB mobile validation limit.');
        }
        digestInput.add(chunk);
      }
      digestInput.close();
      final actualHash = digestSink.value?.toString();
      if (actualHash == null) throw const FormatException('Could not calculate the firmware package digest.');
      final result = FirmwarePackageValidator.validateCandidateHash(
        manifest: manifest,
        target: FirmwareDeviceIdentity(vendor: device.manufacturer, productSeries: targetValues[0],
          model: device.model, hardwareRevision: targetValues[1], region: targetValues[2]),
        packageLength: packageLength,
        actualSha256: actualHash,
      );
      await _record('Firmware candidate validation', device.ipAddress,
        result.candidateValidated ? 'Candidate validated' : 'Rejected',
        '${packageFile.name}: ${result.message}');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text(result.candidateValidated ? 'Candidate integrity matched' : 'Candidate rejected'),
        content: Text('${packageFile.name}\n\n${result.message}\n\nThis validates metadata and SHA-256 only. It does not verify a vendor signature, authorize installation or enable flashing.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } catch (error) {
      await _record('Firmware candidate validation', device.ipAddress, 'Failed', error.toString());
      _msg('Firmware candidate validation failed: $error');
    }
  }

  Future<void> _details(CameraDevice d) async {
    focusedDeviceKey = _key(d);
    final canConfigure = d.ipv4ConfigurationKnown && d.networkInterfaceToken.isNotEmpty;
    final canFactoryReset = d.discoverySources.any((source) => source.startsWith('ONVIF')) && d.deviceServiceUrl.isNotEmpty;
    final deviceHistory = historyEntries.where((entry) =>
      entry.target.contains(d.ipAddress) || (d.userLabel.isNotEmpty && entry.target.contains(d.userLabel))).toList();
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .88,
        child: DefaultTabController(
          length: 3,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 8), child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.userLabel.isEmpty ? d.ipAddress : d.userLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('${d.ipAddress} · ${d.manufacturer} · ${d.model}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11)),
              ])),
              IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
            ])),
            const TabBar(tabs: [
              Tab(icon: Icon(Icons.info_outline), text: 'Details'),
              Tab(icon: Icon(Icons.tune), text: 'Configure'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ]),
            Expanded(child: TabBarView(children: [
              ListView(padding: const EdgeInsets.all(16), children: [
                ...[
                  ['Device type', DeviceClassifier.classify(d).label],
                  ['Confidence', DeviceClassifier.classify(d).confidenceLabel],
                  ['MAC',d.macAddress],['Serial number',d.serialNumber],['Hardware ID',d.hardwareId],
                  ['Firmware',d.firmwareVersion],['Activation',d.activationState],
                  ['Interface',d.interfaceName],['Sources',d.discoverySources.join(', ')],
                  ['Last seen',d.lastSeen?.toLocal().toString() ?? ''],
                  ['Reachability',d.reachabilityStatus],['Checked at',d.reachabilityCheckedAt],
                  ['ONVIF endpoint',d.onvifEndpoint],['Service URL',d.deviceServiceUrl],
                  ['Capabilities',d.capabilities.join(', ')],['Network interfaces',d.networkSummary],
                  ['Camera IPv4',d.ipv4Address],['Subnet mask',d.ipv4SubnetMask],
                  ['Gateway',d.ipv4Gateway],['DNS',d.ipv4DnsServer],
                  ['DHCP',d.ipv4ConfigurationKnown ? (d.ipv4DhcpEnabled ? 'Enabled' : 'Disabled') : 'Unknown'],
                  ['Open TCP ports',d.openPorts.join(', ')],
                ].map((e) => _detail(e[0], e[1])),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(onPressed: () { Navigator.pop(sheetContext); unawaited(_refreshDevice(d)); },
                    icon: const Icon(Icons.refresh), label: const Text('Refresh info')),
                  OutlinedButton.icon(onPressed: () { Navigator.pop(sheetContext); unawaited(_rename(d)); },
                    icon: const Icon(Icons.edit), label: const Text('Rename')),
                  OutlinedButton.icon(onPressed: () async {
                    final u = Uri(scheme: 'http', host: d.ipAddress);
                    final launched = await launchUrl(u, mode: LaunchMode.externalApplication);
                    if (!launched && mounted) _msg('Could not open the camera web interface.');
                  }, icon: const Icon(Icons.open_in_browser), label: const Text('Open web UI')),
                ]),
              ]),
              ListView(padding: const EdgeInsets.all(16), children: [
                _heading('Device', 'Read-only enrichment and supported maintenance'),
                _tool(Icons.refresh, 'Refresh device information', 'Request ONVIF device information, capabilities and network profile.', () { Navigator.pop(sheetContext); unawaited(_refreshDevice(d)); }),
                _tool(Icons.verified_outlined, 'Validate firmware candidate', 'Manifest identity and SHA-256 only. This does not install or flash firmware.', () { Navigator.pop(sheetContext); unawaited(_validateFirmwareCandidate(d)); }),
                _tool(Icons.restore, 'Factory reset', canFactoryReset ? 'ONVIF request only; camera support, credentials and explicit confirmation required.' : 'Unavailable until a compatible ONVIF service is identified.', () { Navigator.pop(sheetContext); unawaited(_factoryReset(d)); }, enabled: canFactoryReset),
                _cap('Reboot', 'Not implemented by desktop main', false),
                const Divider(height: 24),
                _heading('Network', 'Camera-side IPv4 settings reported by ONVIF'),
                _detail('Current IP', d.ipv4Address),
                _detail('Subnet mask', d.ipv4SubnetMask),
                _detail('Gateway', d.ipv4Gateway),
                _detail('DNS', d.ipv4DnsServer),
                _detail('DHCP', d.ipv4ConfigurationKnown ? (d.ipv4DhcpEnabled ? 'Enabled' : 'Disabled') : 'Unknown'),
                _tool(Icons.preview_outlined, 'Preview static IPv4', canConfigure ? 'Validate a proposed address without changing the camera.' : 'Refresh the camera first; a verified interface token is required.', () { Navigator.pop(sheetContext); unawaited(_previewStaticIpv4(d)); }, enabled: canConfigure),
                _tool(Icons.settings_ethernet, 'Apply static IPv4', canConfigure ? 'Send a guarded ONVIF network change after validation and confirmation.' : 'Unavailable until a verified ONVIF interface profile is available.', () { Navigator.pop(sheetContext); unawaited(_staticIp(d)); }, enabled: canConfigure),
                const Divider(height: 24),
                _heading('Storage', 'Local inventory backup and recovery'),
                _tool(Icons.backup_outlined, 'Back up inventory', 'Export a consistent local SQLite inventory and operation-history backup.', () { Navigator.pop(sheetContext); unawaited(_backupInventory()); }),
                _tool(Icons.settings_backup_restore, 'Restore inventory', 'Validate the backup and retain a recovery snapshot before replacement.', () { Navigator.pop(sheetContext); unawaited(_restoreInventory()); }),
                const Text('Mobile backups use the mobile SQLite schema and are not interchangeable with desktop database files.',
                  style: TextStyle(color: muted, fontSize: 11)),
              ]),
              deviceHistory.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No operations recorded for this device yet.', style: TextStyle(color: muted))))
                : ListView(padding: const EdgeInsets.all(16), children: deviceHistory.map((entry) => Card(
                    child: ListTile(
                      dense: true,
                      leading: Icon(entry.outcome.toLowerCase().contains('fail') ? Icons.error_outline : Icons.history,
                        color: entry.outcome.toLowerCase().contains('fail') ? const Color(0xFFE58B82) : red),
                      title: Text(entry.operation),
                      subtitle: Text('${entry.outcome} · ${entry.occurredAt.toLocal()}\n${entry.details}'),
                      isThreeLine: entry.details.isNotEmpty,
                    ),
                  )).toList()),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _detail(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:120,child:Text(label,style:const TextStyle(color:muted,fontSize:12))),
    Expanded(child:SelectableText(value.isEmpty?'Not available':value,style:const TextStyle(fontSize:13))),
  ]));


  Widget _deviceCard(CameraDevice d) {
    final checked = selected.contains(_key(d));
    final classification = DeviceClassifier.classify(d);
    final label = d.userLabel.isEmpty ? d.ipAddress : d.userLabel;
    final state = d.isCandidate ? 'Unverified candidate' : d.reachabilityStatus;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _details(d),
        child: Padding(          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Checkbox(
                visualDensity: VisualDensity.compact,
                value: checked,
                onChanged: (v) => setState(() => v == true ? selected.add(_key(d)) : selected.remove(_key(d))),
              ),
              Icon(d.isCandidate ? Icons.device_unknown : Icons.videocam_outlined,
                  size: 21, color: d.isCandidate ? const Color(0xFFE6B45D) : red),
              const SizedBox(width: 9),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${d.ipAddress}  ·  ${d.manufacturer} ${d.model}'.trim(),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, fontSize: 11)),
                  const SizedBox(height: 3),
                  Wrap(spacing: 6, runSpacing: 3, children: [
                    _statusPill(classification.label, classification.confidenceLabel == 'Verified'
                        ? const Color(0xFF2E7D5B) : const Color(0xFF555555)),
                    _statusPill(state, d.isCandidate ? const Color(0xFF765A2C) :
                        (d.reachabilityStatus == 'Reachable' ? const Color(0xFF2E7D5B) : const Color(0xFF555555))),
                  ]),
                ]),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Rename device',
                onPressed: () => unawaited(_rename(d)),
                icon: const Icon(Icons.edit_outlined, size: 17),
              ),
              const Icon(Icons.chevron_right, color: muted, size: 19),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: .22), borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: TextStyle(color: color == const Color(0xFF555555) ? const Color(0xFFD0D0D0) : const Color(0xFFE8E8E8),
        fontSize: 9, fontWeight: FontWeight.w700)),
  );

  Widget _heading(String title,String subtitle)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(subtitle,style:const TextStyle(color:muted,fontSize:13)),
  ]);

  Widget _overview() => ListView(padding: const EdgeInsets.all(16), children: [
    _heading('Network workspace', 'Local camera discovery and device management'),
    const SizedBox(height: 14),
    DropdownButtonFormField<String>(
      key: ValueKey(interfaceName), initialValue: interfaceName, isExpanded: true,
      decoration: const InputDecoration(labelText: 'Network interface', prefixIcon: Icon(Icons.lan_outlined)),
      items: [const DropdownMenuItem<String>(value: '', child: Text('All active IPv4 interfaces')),
        ...interfaces.map((n) => DropdownMenuItem(value: n.name, child: Text(n.name)))],
      onChanged: (v) { setState(() => interfaceName = v); unawaited(_loadNativeInterfaceDetails(v)); },
    ),
    const SizedBox(height: 8),
    Card(child: ListTile(
      dense: true, leading: const Icon(Icons.router_outlined, color: red),
      title: Text(activeInterface?.name ?? 'All active IPv4 interfaces'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_interfaceAddressSummary(activeInterface)),
        const SizedBox(height: 4),
        Text(nativeInterfaceDetails == null ? 'Native link diagnostics loading…' :
          nativeInterfaceDetails!['available'] == true
            ? "Link: ${nativeInterfaceDetails!['isUp'] == true ? 'Up' : 'Down'} · MTU: ${nativeInterfaceDetails!['mtu'] ?? 'Not exposed by this OS'}"
            : 'Native link details unavailable on this platform build',
          style: const TextStyle(color: muted, fontSize: 11)),
      ]),
    )),
    const SizedBox(height: 12),
    Card(child: ListTile(
      leading: Icon(discovery.isScanning ? Icons.radar : Icons.wifi_tethering, color: discovery.isScanning ? red : const Color(0xFF74C69D)),
      title: Text(discovery.isScanning ? 'Discovery in progress' : 'Discovery status'),
      subtitle: Text(discovery.status),
      trailing: Text('${discovery.devices.length} devices', style: const TextStyle(color: muted, fontWeight: FontWeight.w700)),
    )),
    if (reachabilityProgress.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(reachabilityProgress, style: const TextStyle(color: muted))),
    if (subnetProgress.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(subnetProgress, style: const TextStyle(color: muted))),
    const SizedBox(height: 8),
    _heading('Quick actions', 'Common field workflows'),
    _tool(Icons.radar, 'Discover devices', 'ONVIF, Oxita Contract B and UPnP discovery on the selected interface.', () => unawaited(_discover())),
    _tool(Icons.lan, 'Scan subnet', 'Bounded TCP scan. Responding hosts remain unverified candidates.', () => unawaited(_subnet())),
    _tool(Icons.network_check, 'Check reachability', 'Check selected devices or the visible inventory.', () => unawaited(_reachability())),
    _tool(Icons.add_link, 'Add device manually', 'Add a known camera IP address or hostname.', () => unawaited(_manual())),
    _tool(Icons.devices_outlined, 'Open device inventory', 'Search, filter, select and inspect discovered devices.', () => setState(() => tab = 1)),
  ]);

  Widget _devices() => Column(children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 7),
      child: Column(children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Network inventory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text('${visible.length} matching · ${discovery.devices.length} total',
              style: const TextStyle(color: muted, fontSize: 11)),
          ])),
          IconButton(tooltip: 'Refresh history and inventory', onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'Export CSV', onPressed: () => unawaited(_export()),
            icon: const Icon(Icons.file_download_outlined)),
        ]),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          key: ValueKey(interfaceName), initialValue: interfaceName, isExpanded: true,
          decoration: const InputDecoration(isDense: true, labelText: 'Discovery interface', prefixIcon: Icon(Icons.lan_outlined)),
          items: [const DropdownMenuItem<String>(value: '', child: Text('All active IPv4 interfaces')),
            ...interfaces.map((n) => DropdownMenuItem(value: n.name, child: Text(n.name)))],
          onChanged: (v) { setState(() => interfaceName = v); unawaited(_loadNativeInterfaceDetails(v)); },
        ),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: FilledButton.icon(
            onPressed: () => unawaited(_discover()),
            icon: Icon(discovery.isScanning ? Icons.stop : Icons.radar, size: 17),
            label: Text(discovery.isScanning ? 'Stop' : 'Discover'),
          )),
          const SizedBox(width: 6),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => unawaited(_subnet()),
            icon: const Icon(Icons.lan, size: 17), label: const Text('Subnet scan'),
          )),
          const SizedBox(width: 6),
          Expanded(child: OutlinedButton.icon(
            onPressed: () => unawaited(_reachability()),
            icon: const Icon(Icons.network_check, size: 17), label: const Text('Reachability'),
          )),
        ]),
        if (discovery.status.isNotEmpty)
          Align(alignment: Alignment.centerLeft, child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(discovery.status, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 10)),
          )),
        const SizedBox(height: 7),
        TextField(controller: search, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Search IP, MAC, model, serial or label')),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(
            key: ValueKey(deviceTypeFilter), initialValue: deviceTypeFilter, isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Device type'),
            items: const ['All device types','camera','nvr','router','switch','printer','computer','unknown']
              .map((v) => DropdownMenuItem(value: v, child: Text(v == 'All device types' ? v : '${v[0].toUpperCase()}${v.substring(1)}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => deviceTypeFilter = v ?? 'All device types'),
          )),
          const SizedBox(width: 7),
          Expanded(child: DropdownButtonFormField<String>(
            key: ValueKey(statusFilter), initialValue: statusFilter, isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Status'),
            items: const ['All statuses','Online','Activated','Not activated','Unverified candidates']
              .map((v) => DropdownMenuItem(value: v, child: Text(v, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => statusFilter = v ?? 'All statuses'),
          )),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          TextButton(onPressed: () => setState(() => selected.addAll(visible.map(_key))), child: const Text('Select all')),
          TextButton(onPressed: () => setState(selected.clear), child: const Text('Clear')),
          const Spacer(),
          Text('${selected.length} selected', style: const TextStyle(color: muted, fontSize: 11)),
        ]),
      ]),
    ),
    Expanded(child: loading ? const Center(child: CircularProgressIndicator()) :
      visible.isEmpty ? const Center(child: Text('No matching devices. Discover cameras or adjust your filters.')) :
      ListView.builder(padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        itemCount: visible.length, itemBuilder: (context, index) => _deviceCard(visible[index]))),
  ]);

  Widget _tools()=>ListView(padding:const EdgeInsets.all(18),children:[
    _heading('Network tools','Installer and field-technician workflows'),
    _tool(Icons.radar,'ONVIF + Oxita + UPnP discovery','Discover devices on selected or all active IPv4 interfaces.',()=>unawaited(_discover())),
    _tool(Icons.lan,discovery.isSubnetScanning?'Cancel subnet scan':'Bounded subnet scan','Probe up to 256 IPv4 hosts; TCP responders remain unverified candidates. $subnetProgress',()=>unawaited(_subnet())),
    _tool(Icons.network_check,checking?'Cancel reachability checks':'Check reachability','Checks selected devices or all visible devices when none selected.',()=>unawaited(_reachability())),
    _tool(Icons.add_link,'Add device manually','Add a known camera IPv4 address.',()=>unawaited(_manual())),
    _tool(Icons.file_download,'Export inventory CSV','Share filtered inventory with device, network and capability fields.',()=>unawaited(_export())),
    _tool(Icons.playlist_add_check,'Batch refresh selected cameras',batchRunning ? batchProgress : 'Sequential ONVIF read-only refresh; unsupported targets are skipped.',()=>unawaited(_batchRefresh())),
    _tool(Icons.route,'Multi-camera IPv4 assignment','Plan, preflight and sequentially apply static addresses to selected cameras. Writes remain blocked unless every live conflict probe positively reports clear.',()=>unawaited(_previewIpAssignmentPlan()),enabled: !batchRunning),
    if (_focusedDevice != null) _tool(Icons.verified_outlined,'Validate firmware package candidate','Check manifest identity and SHA-256 for the selected camera. Does not flash.',()=>unawaited(_validateFirmwareCandidate(_focusedDevice!))),
    const SizedBox(height:14),_heading('Feature availability','Unimplemented desktop features stay unavailable'),
    _cap('ONVIF discovery and enrichment','Available when supported',true),
    _cap('TCP reachability and expanded subnet scan','Common camera, management, printer and computer ports; up to 4,096 hosts',true),
    _cap('Static IPv4 over ONVIF','Single-camera workflow · verified interface required',true),
    _cap('Batch read-only refresh','Sequential, per-device preflight and cancellation',true),
    _cap('Multi-camera IPv4 assignment','Sequential ONVIF writes with per-camera immediate preflight; Android/iOS currently fail closed when probe cannot prove clear',true),
    _cap('Firmware package candidate validation','Metadata + SHA-256 only · no signature verification or flashing',true),
    _cap('Bulk image settings','Not implemented',false),
    _cap('Activation / reboot / firmware','Not implemented',false),
    _cap('NVR channels','Not implemented',false),
    _cap('CP Plus / Hikvision / Prama adapters','No verified vendor adapters',false),
  ]);

  Widget _tool(IconData icon, String title, String subtitle, VoidCallback action, {bool enabled = true}) => Card(child: ListTile(leading: Icon(icon, color: enabled ? red : muted), title: Text(title), subtitle: Text(subtitle), trailing: Icon(Icons.chevron_right, color: enabled ? muted : Colors.white24), onTap: enabled ? action : null));
  Widget _cap(String title,String subtitle,bool ok)=>Card(child:ListTile(dense:true,title:Text(title),subtitle:Text(subtitle),trailing:Icon(ok?Icons.check_circle_outline:Icons.lock_outline,color:ok?const Color(0xFF74C69D):muted)));

  CameraDevice? get _focusedDevice {
    for (final device in discovery.devices) {
      if (_key(device) == focusedDeviceKey) return device;
    }
    return null;
  }

  Widget _maintenance() {
    final device = _focusedDevice;
    if (device == null) {
      return ListView(padding: const EdgeInsets.all(18), children: [
        _heading('Maintenance', 'Camera actions and network configuration'),
        const SizedBox(height: 14),
        const Card(child: Padding(padding: EdgeInsets.all(20), child: Text(
          'Select a camera from the Devices page and open its details first. The selected camera will appear here for maintenance actions.',
          style: TextStyle(color: muted, height: 1.45),
        ))),
        _cap('Static IPv4 configuration', 'Requires a refreshed ONVIF interface profile', false),
        _cap('Firmware package validation', 'Candidate metadata and SHA-256 only; flashing unavailable', false),
      ]);
    }
    final canConfigure = device.ipv4ConfigurationKnown && device.networkInterfaceToken.isNotEmpty;
    final canFactoryReset = device.discoverySources.any((source) => source.startsWith('ONVIF')) && device.deviceServiceUrl.isNotEmpty;
    return ListView(padding: const EdgeInsets.all(18), children: [
      _heading('Maintenance', 'Actions for the selected camera'),
      const SizedBox(height: 14),
      Card(child: ListTile(
        leading: const Icon(Icons.videocam, color: red),
        title: Text(device.userLabel.isEmpty ? device.ipAddress : device.userLabel),
        subtitle: Text('${device.ipAddress} · ${device.manufacturer} · ${device.model}'),
        trailing: Text(device.reachabilityStatus, style: const TextStyle(color: muted, fontSize: 11)),
      )),
      const SizedBox(height: 14),
      _heading('Device actions', 'Refresh camera information or open its web interface'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () => unawaited(_refreshDevice(device)),
          icon: const Icon(Icons.refresh), label: const Text('Refresh info'),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: () async {
            final uri = Uri(scheme: 'http', host: device.ipAddress);
            final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
            if (!launched) _msg('Could not open the camera web interface.');          },
          icon: const Icon(Icons.open_in_browser), label: const Text('Open web UI'),
        )),
      ]),
      const SizedBox(height: 20),
      _heading('Camera maintenance', 'Only verified ONVIF operations are exposed'),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: canFactoryReset ? () => unawaited(_factoryReset(device)) : null,
        icon: const Icon(Icons.restore, color: Color(0xFFC62836)),
        label: const Text('Factory reset camera'),
      ),
      const Card(child: ListTile(
        leading: Icon(Icons.info_outline, color: muted),
        title: Text('Reboot is unavailable'),
        subtitle: Text('Desktop main does not implement a verified reboot operation. Factory reset is available only through ONVIF SetSystemFactoryDefault when the camera supports and authorizes it.'),
      )),
      const SizedBox(height: 20),
      _heading('IPv4 network configuration', 'Camera-side settings reported by ONVIF'),
      const SizedBox(height: 8),
      _detail('Current IP', device.ipv4Address),
      _detail('Subnet mask', device.ipv4SubnetMask),
      _detail('Gateway', device.ipv4Gateway),
      _detail('DNS', device.ipv4DnsServer),
      _detail('DHCP', device.ipv4ConfigurationKnown ? (device.ipv4DhcpEnabled ? 'Enabled' : 'Disabled') : 'Unknown'),
      _detail('Interface token', device.networkInterfaceToken),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: OutlinedButton(
          onPressed: canConfigure ? () => unawaited(_previewStaticIpv4(device)) : null,
          child: const Text('Preview IP'),
        )),
        const SizedBox(width: 8),
        Expanded(child: FilledButton(
          onPressed: canConfigure ? () => unawaited(_staticIp(device)) : null,
          child: const Text('Apply static IPv4'),
        )),
      ]),
      const SizedBox(height: 20),
      _heading('Firmware status', 'Read-only information from the camera'),
      const SizedBox(height: 8),
      _detail('Reported firmware', device.firmwareVersion),
      OutlinedButton.icon(onPressed: () => unawaited(_validateFirmwareCandidate(device)), icon: const Icon(Icons.verified_outlined), label: const Text('Validate package candidate')),
      const Card(child: ListTile(
        leading: Icon(Icons.lock_outline, color: muted),
        title: Text('Firmware flashing unavailable'),
        subtitle: Text('The desktop main branch only validates package metadata and SHA-256 candidates. Vendor signature verification, authorized transport and recovery are not implemented.'),
      )),
      const SizedBox(height: 8),
      _cap('Factory reset', 'ONVIF Soft/Hard request · camera support and authorization required', true),
      _cap('Reboot', 'Not implemented', false),
      _cap('DHCP / DNS write configuration', 'Not implemented', false),
    ]);
  }


  Future<void> _exportDiagnostics() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review diagnostic export'),
        content: const Text(
          'The support bundle includes OS/app details, local IPv4 interface addresses, recent operation history and redacted rotating logs. '
          'It excludes the inventory database, camera credentials and ONVIF interface tokens. '
          'Local addresses, camera IPs and activity timestamps may still be sensitive. You will be able to inspect the bundle before sharing.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final history = await store.loadHistory(limit: 250);
      final count = await store.deviceCount();
      final content = await diagnostics.buildSupportBundle(history: history, deviceCount: count);
      if (!mounted) return;
      final share = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Inspect diagnostic bundle'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: SingleChildScrollView(child: SelectableText(content, style: const TextStyle(fontSize: 11))),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton.icon(onPressed: () => Navigator.pop(context, true), icon: const Icon(Icons.share), label: const Text('Share bundle')),
          ],
        ),
      );
      if (share != true || !mounted) return;
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/oxita-mobile-diagnostics.txt');
      await file.writeAsString(content, flush: true);
      await Share.shareXFiles([XFile(file.path)], text: 'Oxita Camera IP Search diagnostic bundle');
      await _record('Diagnostic export', file.uri.pathSegments.last, 'Prepared',
          'User inspected the redacted support bundle before opening the share sheet.');
    } catch (error) {
      await diagnostics.log('error', 'Diagnostic export failed: $error');
      _msg('Diagnostic export failed: $error');
    }
  }

  Widget _history() => RefreshIndicator(
    onRefresh: _refreshHistory,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _heading('Operation history', 'Local audit trail for discovery and device-management actions'),
        const SizedBox(height: 8),
        const Text(
          'The latest 1,000 events are retained on this device. Sensitive-looking values are redacted before persistence; diagnostic redaction is best-effort.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _refreshHistory, icon: const Icon(Icons.refresh), label: const Text('Refresh'))),
          const SizedBox(width: 8),
          Expanded(child: FilledButton.icon(onPressed: _exportDiagnostics, icon: const Icon(Icons.support_agent), label: const Text('Export diagnostics'))),
        ]),
        const SizedBox(height: 12),
        if (historyEntries.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('No operations recorded yet. Discovery, scans and device changes will appear here.')))
        else
          ...historyEntries.map((entry) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                entry.outcome.toLowerCase().contains('fail') ? Icons.error_outline :
                entry.outcome.toLowerCase().contains('cancel') ? Icons.cancel_outlined :
                Icons.history,
                color: entry.outcome.toLowerCase().contains('fail') ? const Color(0xFFE58B82) : red,
              ),
              title: Text(entry.operation, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${entry.outcome} · ${entry.target.isEmpty ? 'Local operation' : entry.target}'),
                  if (entry.details.isNotEmpty) Text(entry.details, style: const TextStyle(color: muted, fontSize: 11)),
                  Text(entry.occurredAt.toLocal().toString(), style: const TextStyle(color: muted, fontSize: 10)),
                ]),
              ),
              isThreeLine: true,
            ),
          )),
      ],
    ),
  );

  Future<void> _backupInventory() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/oxita-mobile-inventory-${DateTime.now().toUtc().toIso8601String().replaceAll(':','-')}.db');
      await store.exportBackup(file);
      await Share.shareXFiles([XFile(file.path)], text: 'Oxita Camera IP Search inventory backup');
      await _record('Inventory backup', file.uri.pathSegments.last, 'Prepared',
          'SQLite integrity was checkpointed before the user shared the backup.');
    } catch (error) {
      await diagnostics.log('error', 'Inventory backup failed: $error');
      _msg('Inventory backup failed: $error');
    }
  }

  Future<void> _restoreInventory() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite', 'sqlite3'],
      withData: false,
    );
    if (picked == null || picked.files.single.path == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore inventory backup?'),
        content: const Text('The current inventory will be replaced. The selected file is integrity-checked first and a recovery snapshot of the current database is retained before restore. Only an Oxita mobile inventory backup is accepted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Validate and restore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final recovery = await store.restoreBackup(File(picked.files.single.path!));
      final restored = await store.load();
      final history = await store.loadHistory();
      discovery.replaceInventory(restored);
      if (!mounted) return;
      setState(() {
        historyEntries = history;
        _lastInventorySnapshot = jsonEncode(discovery.devices.map((d) => d.toJson()).toList());
      });
      await _record('Inventory restore', picked.files.single.name, 'Completed',
          'Pre-restore recovery snapshot retained at ${recovery.path}.');
      _msg('Inventory restored. A recovery snapshot was retained on this device.');
    } catch (error) {
      await diagnostics.log('error', 'Inventory restore failed: $error');
      _msg('Inventory restore failed: $error');
    }
  }

  Widget _settings()=>FutureBuilder<String>(future:store.databasePath,builder:(context,s)=>ListView(padding:const EdgeInsets.all(18),children:[
    _heading('Application settings','Local inventory and platform information'),
    Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('LOCAL SQLITE DATABASE',style:TextStyle(color:muted,fontSize:10,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),SelectableText(s.data??'Loading database path…'),
      TextButton.icon(onPressed:s.hasData?(){unawaited(Clipboard.setData(ClipboardData(text:s.data!)));_msg('Database location copied.');}:null,icon:const Icon(Icons.copy),label:const Text('Copy location')),
    ]))),
    _detail('Platform',Platform.operatingSystem),_detail('Active interface',interfaceName??'Not selected'),
    _detail('Saved devices','${discovery.devices.length}'),_detail('SQLite integrity',databaseIntegrity),_detail('Version','0.3.0'),
    _tool(Icons.backup,'Back up local inventory','Create a consistent SQLite backup of saved devices and operation history.',()=>unawaited(_backupInventory())),
    _tool(Icons.settings_backup_restore,'Restore inventory backup','Validate a backup and retain a recovery snapshot before restoring.',()=>unawaited(_restoreInventory())),
    _tool(Icons.file_download,'Export inventory','Share the current inventory as CSV.',()=>unawaited(_export())),
    const SizedBox(height:12),const Text('iOS multicast/broadcast requires Apple multicast entitlement and physical-device validation. Android local-network permissions are handled by the native bootstrap runner.',style:TextStyle(color:muted,fontSize:12)),
  ]));

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Row(children:[
      Image.asset('assets/oxita-logo.png',width:96,height:40,fit:BoxFit.contain,
        errorBuilder:(context,error,stack)=>const Icon(Icons.camera_alt,color:red,size:28)),
      const SizedBox(width:8),
      const Expanded(child:Text('CAMERA DEVICE MANAGER',maxLines:1,overflow:TextOverflow.ellipsis,
        style:TextStyle(fontSize:9,color:muted,fontWeight:FontWeight.w800,letterSpacing:1))),
    ]),actions:[IconButton(onPressed:()=>unawaited(_help()),icon:const Icon(Icons.help_outline),tooltip:'Help'),IconButton(onPressed:()=>unawaited(_manual()),icon:const Icon(Icons.add_circle_outline),tooltip:'Add device'),IconButton(onPressed:()=>unawaited(_export()),icon:const Icon(Icons.file_download),tooltip:'Export CSV')]),
    body:SafeArea(child:IndexedStack(index:tab,children:[_overview(),_devices(),_tools(),_maintenance(),_history(),_settings()])),
    floatingActionButton:tab<2?FloatingActionButton.extended(onPressed:()=>unawaited(_discover()),backgroundColor:red,foregroundColor:Colors.white,
      icon:Icon(discovery.isScanning?Icons.stop:Icons.radar),label:Text(discovery.isScanning?'Stop discovery':'Discover devices')):null,
    bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[
      NavigationDestination(icon:Icon(Icons.grid_view),label:'Overview'),NavigationDestination(icon:Icon(Icons.videocam_outlined),label:'Devices'),
      NavigationDestination(icon:Icon(Icons.tune),label:'Tools'),NavigationDestination(icon:Icon(Icons.build_outlined),label:'Maintenance'),
      NavigationDestination(icon:Icon(Icons.history),label:'History'),
      NavigationDestination(icon:Icon(Icons.settings_outlined),label:'Settings'),
    ]),
  );
}
