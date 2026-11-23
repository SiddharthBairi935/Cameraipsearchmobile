import 'dart:async';
import 'dart:convert';
import 'dart:io';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/camera_device.dart';
import 'models/operation_history_entry.dart';
import 'services/device_discovery_service.dart';
import 'services/inventory_store.dart';
import 'services/diagnostics_service.dart';
import 'services/onvif_device_service.dart';
import 'services/network_config_validator.dart';

const red = Color(0xFFD43B49), canvas = Color(0xFF101216), surface = Color(0xFF191D23), muted = Color(0xFF9AA3B1);

class CameraIpSearchApp extends StatelessWidget {
  const CameraIpSearchApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Oxita Camera Device Manager', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: red, brightness: Brightness.dark, surface: surface),
      cardTheme: CardThemeData(color: surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF2B3039)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF20252D), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
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
  List<OperationHistoryEntry> historyEntries = [];
  final search = TextEditingController();
  final selected = <String>{};
  List<NetworkInterface> interfaces = [];
  Map<String, dynamic>? nativeInterfaceDetails;
  int tab = 0;
  bool loading = true, checking = false;
  String? interfaceName, focusedDeviceKey;
  String manufacturerFilter = 'All manufacturers', statusFilter = 'All statuses';
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
      setState(() { interfaces = found; interfaceName = found.isEmpty ? null : found.first.name; historyEntries = history; loading = false; });
      await _loadNativeInterfaceDetails(interfaceName);
    } catch (e) { if (mounted) setState(() => loading = false); _msg('Inventory load failed: $e'); }
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
      if (mounted) setState(() => nativeInterfaceDetails = {
        'available': false,
        'error': error.toString(),
      });
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
      await discovery.refreshDeviceInfo(device);
      await _record('Device information refresh', device.ipAddress, 'Completed',
          'ONVIF identity, capabilities and available network details refreshed.');
    } catch (error) {
      await _record('Device information refresh', device.ipAddress, 'Failed', error.toString());
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
    final status = switch (statusFilter) {
      'Online' => d.reachabilityStatus == 'Reachable',
      'Activated' => d.activationState == 'Activated',
      'Not activated' => d.activationState == 'Not activated',
      'Unverified candidates' => d.isCandidate,
      _ => true,
    };
    return match && vendor && status;
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
    final rows = <List<String>>[
      ['IP ADDRESS','DESCRIPTION','MANUFACTURER','MODEL','MAC','FIRMWARE','STATUS','SOURCE','SERIAL','HARDWARE ID','REACHABILITY','INTERFACES','CAPABILITIES','OPEN PORTS','CAMERA IPV4','MASK','GATEWAY','DNS','DHCP','ONVIF ENDPOINT','SERVICE URL'],
      ...visible.map((d)=>[d.ipAddress,d.userLabel,d.manufacturer,d.model,d.macAddress,d.firmwareVersion,d.activationState,d.discoverySources.join('; '),d.serialNumber,d.hardwareId,d.reachabilityStatus,d.networkSummary,d.capabilities.join('; '),d.openPorts.join('; '),d.ipv4Address,d.ipv4SubnetMask,d.ipv4Gateway,d.ipv4DnsServer,d.ipv4DhcpEnabled.toString(),d.onvifEndpoint,d.deviceServiceUrl])
    ];
    String field(String v)=>'"${v.replaceAll('"','""')}"';
    final dir=await getTemporaryDirectory(), file=File('${dir.path}/oxita-camera-inventory.csv');
    await file.writeAsString('\uFEFF${rows.map((r)=>r.map(field).join(',')).join('\r\n')}\r\n',flush:true);
    await Share.shareXFiles([XFile(file.path)],text:'Oxita camera inventory');
    await _record('Inventory export', 'oxita-camera-inventory.csv', 'Prepared', '${visible.length} filtered device row(s) exported.');
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
    if (!mounted) return;
    await _record('Static IPv4 preview', d.ipAddress, 'Validated', 'Local validation passed for proposed address ${values[0]}; no camera request was sent.');
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
        Text('Feature availability', style: TextStyle(fontWeight: FontWeight.w800)),
        Text('Bulk image settings, camera activation, firmware update, reboot and NVR channels are not implemented in the desktop release candidate and remain unavailable here.'),
      ])),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
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

  Future<void> _details(CameraDevice d) async {
    focusedDeviceKey = _key(d);
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,backgroundColor:surface,builder:(context)=>DraggableScrollableSheet(
      expand:false,initialChildSize:.88,maxChildSize:.96,builder:(context,scroll)=>ListView(controller:scroll,padding:const EdgeInsets.all(20),children:[
        Center(child:Container(width:38,height:4,decoration:BoxDecoration(color:Colors.white24,borderRadius:BorderRadius.circular(4)))),
        const SizedBox(height:18),Text(d.userLabel.isEmpty?d.ipAddress:d.userLabel,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
        Text('${d.ipAddress} · ${d.manufacturer} · ${d.model}',style:const TextStyle(color:muted)),
        const SizedBox(height:12),
        ...[
          ['MAC',d.macAddress],['Serial number',d.serialNumber],['Hardware ID',d.hardwareId],['Firmware',d.firmwareVersion],['Activation',d.activationState],
          ['Interface',d.interfaceName],['Sources',d.discoverySources.join(', ')],['Last seen',d.lastSeen?.toLocal().toString() ?? ''],['Reachability',d.reachabilityStatus],['Checked at',d.reachabilityCheckedAt],
          ['ONVIF endpoint',d.onvifEndpoint],['Service URL',d.deviceServiceUrl],['Interface token',d.networkInterfaceToken],['Capabilities',d.capabilities.join(', ')],['Network interfaces',d.networkSummary],
          ['Camera IPv4',d.ipv4Address],['Subnet mask',d.ipv4SubnetMask],['Gateway',d.ipv4Gateway],['DNS',d.ipv4DnsServer],
          ['DHCP',d.ipv4ConfigurationKnown?(d.ipv4DhcpEnabled?'Enabled':'Disabled'):'Unknown'],['Open TCP ports',d.openPorts.join(', ')],
        ].map((e)=>_detail(e[0],e[1])),
        const SizedBox(height:14),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton.icon(onPressed:(){Navigator.pop(context);unawaited(_refreshDevice(d));},icon:const Icon(Icons.refresh),label:const Text('Refresh info')),
          OutlinedButton.icon(onPressed:(){Navigator.pop(context);unawaited(_rename(d));},icon:const Icon(Icons.edit),label:const Text('Rename')),
          OutlinedButton.icon(onPressed:d.ipv4ConfigurationKnown && d.networkInterfaceToken.isNotEmpty?(){Navigator.pop(context);unawaited(_previewStaticIpv4(d));}:null,icon:const Icon(Icons.preview_outlined),label:const Text('Preview IP')),
          OutlinedButton.icon(onPressed:d.ipv4ConfigurationKnown && d.networkInterfaceToken.isNotEmpty?(){Navigator.pop(context);unawaited(_staticIp(d));}:null,icon:const Icon(Icons.settings_ethernet),label:const Text('Apply static IPv4')),
          OutlinedButton.icon(onPressed:()async{final u=Uri(scheme:'http',host:d.ipAddress);if(await canLaunchUrl(u))await launchUrl(u,mode:LaunchMode.externalApplication);},icon:const Icon(Icons.open_in_browser),label:const Text('Open web UI')),
        ]),
        const SizedBox(height:12),const Text('Bulk configuration, activation, firmware upgrade, reboot and NVR channels are not implemented in desktop PR #4 and remain unavailable.',style:TextStyle(color:muted,fontSize:12)),
      ])));
  }

  Widget _detail(String label,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
    SizedBox(width:120,child:Text(label,style:const TextStyle(color:muted,fontSize:12))),
    Expanded(child:SelectableText(value.isEmpty?'Not available':value,style:const TextStyle(fontSize:13))),
  ]));

  Widget _metric(String label,String value,IconData icon)=>Expanded(child:Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Icon(icon,color:red),const SizedBox(height:10),Text(value,style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
    Text(label,style:const TextStyle(color:muted,fontSize:9,fontWeight:FontWeight.w700)),
  ]))));

  Widget _deviceCard(CameraDevice d){
    final checked=selected.contains(_key(d));
    return Card(margin:const EdgeInsets.only(bottom:8),child:InkWell(borderRadius:BorderRadius.circular(18),onTap:()=>_details(d),
      child:Padding(padding:const EdgeInsets.symmetric(horizontal:8,vertical:10),child:Row(children:[
        Checkbox(value:checked,onChanged:(v)=>setState(()=>v==true?selected.add(_key(d)):selected.remove(_key(d)))),
        Icon(d.isCandidate?Icons.device_unknown:Icons.videocam,color:d.isCandidate?const Color(0xFFE6B45D):red),
        const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(d.userLabel.isEmpty?d.ipAddress:d.userLabel,style:const TextStyle(fontWeight:FontWeight.w800)),
          Text('${d.ipAddress} · ${d.manufacturer} · ${d.model}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:muted,fontSize:11)),
          Text('${d.isCandidate?'Unverified candidate':d.reachabilityStatus} · ${d.discoverySources.join(', ')}',maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:muted,fontSize:10)),
        ])),
        IconButton(onPressed:()=>unawaited(_rename(d)),icon:const Icon(Icons.edit_outlined,size:18)),const Icon(Icons.chevron_right,color:muted),
      ]))));
  }

  Widget _heading(String title,String subtitle)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const SizedBox(height:4),Text(subtitle,style:const TextStyle(color:muted,fontSize:13)),
  ]);

  Widget _overview()=>ListView(padding:const EdgeInsets.all(18),children:[
    _heading('Device manager','Discover, verify and configure compatible cameras'),
    const SizedBox(height:14),
    DropdownButtonFormField<String>(key:ValueKey(interfaceName),initialValue:interfaceName,isExpanded:true,decoration:const InputDecoration(labelText:'Active network interface',prefixIcon:Icon(Icons.lan_outlined)),
      items:interfaces.map((n)=>DropdownMenuItem(value:n.name,child:Text(n.name))).toList(),onChanged:(v){setState(()=>interfaceName=v);unawaited(_loadNativeInterfaceDetails(v));}),
    const SizedBox(height:8),
    Card(child: ListTile(
      dense: true,
      leading: const Icon(Icons.router_outlined, color: red),
      title: Text(activeInterface?.name ?? 'No active interface selected'),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_interfaceAddressSummary(activeInterface)),
        const SizedBox(height: 4),
        Text(
          nativeInterfaceDetails == null
              ? 'Native link diagnostics loading…'
              : nativeInterfaceDetails!['available'] == true
                  ? "Link: ${nativeInterfaceDetails!['isUp'] == true ? 'Up' : 'Down'} · MTU: ${nativeInterfaceDetails!['mtu'] ?? 'Not exposed by this OS'}"
                  : 'Native link details unavailable on this platform build',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
      ]),
      trailing: activeInterface == null ? null : Text('IF ${activeInterface!.index}', style: const TextStyle(color: muted, fontSize: 11)),
    )),
    const SizedBox(height:14),Row(children:[
      _metric('DISCOVERED','${discovery.devices.length}',Icons.devices),
      _metric('REACHABLE','${discovery.devices.where((d)=>d.reachabilityStatus=='Reachable').length}',Icons.wifi),
      _metric('NEEDS REVIEW','${discovery.devices.where((d)=>d.isCandidate).length}',Icons.search),
    ]),
    const SizedBox(height:8),Row(children:[
      _metric('ONVIF VERIFIED','${discovery.devices.where((d)=>d.discoverySources.contains('ONVIF GetDeviceInformation')).length}',Icons.verified_user_outlined),
      _metric('OXITA DEVICES','${discovery.devices.where((d)=>d.manufacturer.toLowerCase()=='oxita').length}',Icons.camera_alt_outlined),
    ]),
    const SizedBox(height:14),Card(child:ListTile(leading:Icon(discovery.isScanning?Icons.radar:Icons.wifi_tethering,color:const Color(0xFF74C69D)),
      title:Text(discovery.isScanning?'Discovery in progress':'Network status'),subtitle:Text(discovery.status))),
    if(reachabilityProgress.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(reachabilityProgress,style:const TextStyle(color:muted))),
    if(subnetProgress.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(subnetProgress,style:const TextStyle(color:muted))),
    const SizedBox(height:16),_heading('Recently discovered','Saved local inventory'),
    if(loading)const Center(child:CircularProgressIndicator()) else if(discovery.devices.isEmpty)const Padding(padding:EdgeInsets.all(30),child:Text('No cameras discovered yet. Connect to the camera network and start discovery.',textAlign:TextAlign.center))
    else ...discovery.devices.take(6).map(_deviceCard),
    if(discovery.devices.length>6)TextButton(onPressed:()=>setState(()=>tab=1),child:const Text('View all devices')),
  ]);

  Widget _devices()=>Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(16,14,16,8),child:Column(children:[
      _heading('Device inventory','${visible.length} matching device(s)'),
      const SizedBox(height:10),TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search IP, MAC, model, serial or label')),
      const SizedBox(height:8),Row(children:[
        Expanded(child:DropdownButtonFormField<String>(key:ValueKey(manufacturerFilter),initialValue:manufacturerFilter,isExpanded:true,decoration:const InputDecoration(labelText:'Manufacturer'),
          items:const ['All manufacturers','ONVIF devices','Oxita devices','Other / unknown'].map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>manufacturerFilter=v??'All manufacturers'))),
        const SizedBox(width:8),Expanded(child:DropdownButtonFormField<String>(key:ValueKey(statusFilter),initialValue:statusFilter,isExpanded:true,decoration:const InputDecoration(labelText:'Status'),
          items:const ['All statuses','Online','Activated','Not activated','Unverified candidates'].map((v)=>DropdownMenuItem(value:v,child:Text(v,overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>statusFilter=v??'All statuses'))),
      ]),
      Row(children:[TextButton(onPressed:()=>setState(()=>selected.addAll(visible.map(_key))),child:const Text('Select all')),
        TextButton(onPressed:()=>setState(selected.clear),child:const Text('Clear')),const Spacer(),Text('${selected.length} selected',style:const TextStyle(color:muted,fontSize:12))]),
    ])),
    Expanded(child:visible.isEmpty?const Center(child:Text('No matching devices')):ListView(padding:const EdgeInsets.symmetric(horizontal:16),children:visible.map(_deviceCard).toList())),
  ]);

  Widget _tools()=>ListView(padding:const EdgeInsets.all(18),children:[
    _heading('Network tools','Installer and field-technician workflows'),
    _tool(Icons.radar,'ONVIF + Oxita discovery','Discover devices on selected IPv4 interface.',()=>unawaited(_discover())),
    _tool(Icons.lan,discovery.isSubnetScanning?'Cancel subnet scan':'Bounded subnet scan','Probe up to 256 IPv4 hosts; TCP responders remain unverified candidates. $subnetProgress',()=>unawaited(_subnet())),
    _tool(Icons.network_check,checking?'Cancel reachability checks':'Check reachability','Checks selected devices or all visible devices when none selected.',()=>unawaited(_reachability())),
    _tool(Icons.add_link,'Add device manually','Add a known camera IPv4 address.',()=>unawaited(_manual())),
    _tool(Icons.file_download,'Export inventory CSV','Share filtered inventory with device, network and capability fields.',()=>unawaited(_export())),
    const SizedBox(height:14),_heading('Feature availability','Unimplemented desktop features stay unavailable'),
    _cap('ONVIF discovery and enrichment','Available when supported',true),
    _cap('TCP reachability and bounded scan','Available',true),
    _cap('Static IPv4 over ONVIF','Conditional · verified interface required',true),
    _cap('Bulk image settings','Not implemented',false),
    _cap('Activation / reboot / firmware','Not implemented',false),
    _cap('NVR channels','Not implemented',false),
    _cap('CP Plus / Hikvision / Prama adapters','No verified vendor adapters',false),
  ]);

  Widget _tool(IconData icon,String title,String subtitle,VoidCallback action)=>Card(child:ListTile(leading:Icon(icon,color:red),title:Text(title),subtitle:Text(subtitle),trailing:const Icon(Icons.chevron_right),onTap:action));
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
        _cap('Firmware update / reboot', 'Not implemented in desktop PR #4', false),
      ]);
    }
    final canConfigure = device.ipv4ConfigurationKnown && device.networkInterfaceToken.isNotEmpty;
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
            if (!launched) _msg('Could not open the camera web interface.');
          },
          icon: const Icon(Icons.open_in_browser), label: const Text('Open web UI'),
        )),
      ]),
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
      const Card(child: ListTile(
        leading: Icon(Icons.lock_outline, color: muted),
        title: Text('Firmware update unavailable'),
        subtitle: Text('No verified firmware upload, signature validation or recovery workflow is implemented in desktop PR #4.'),
      )),
      const SizedBox(height: 8),
      _cap('Reboot / factory reset', 'Not implemented', false),
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

  Widget _settings()=>FutureBuilder<String>(future:store.databasePath,builder:(context,s)=>ListView(padding:const EdgeInsets.all(18),children:[
    _heading('Application settings','Local inventory and platform information'),
    Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('LOCAL SQLITE DATABASE',style:TextStyle(color:muted,fontSize:10,fontWeight:FontWeight.w800)),
      const SizedBox(height:8),SelectableText(s.data??'Loading database path…'),
      TextButton.icon(onPressed:s.hasData?(){unawaited(Clipboard.setData(ClipboardData(text:s.data!)));_msg('Database location copied.');}:null,icon:const Icon(Icons.copy),label:const Text('Copy location')),
    ]))),
    _detail('Platform',Platform.operatingSystem),_detail('Active interface',interfaceName??'Not selected'),
    _detail('Saved devices','${discovery.devices.length}'),_detail('Version','0.3.0'),
    _tool(Icons.file_download,'Export inventory','Share the current inventory as CSV.',()=>unawaited(_export())),
    const SizedBox(height:12),const Text('iOS multicast/broadcast requires Apple multicast entitlement and physical-device validation. Android local-network permissions are handled by the native bootstrap runner.',style:TextStyle(color:muted,fontSize:12)),
  ]));

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Row(children:[
      CircleAvatar(backgroundColor:red,child:Icon(Icons.camera_alt,color:Colors.white)),
      SizedBox(width:10),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('OXITA',style:TextStyle(fontSize:16,fontWeight:FontWeight.w900,letterSpacing:1.2)),
        Text('CAMERA DEVICE MANAGER',style:TextStyle(fontSize:9,color:muted,letterSpacing:1)),
      ]),
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

