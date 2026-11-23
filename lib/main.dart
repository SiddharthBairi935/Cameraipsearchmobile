import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/camera_device.dart';
import 'services/device_discovery_service.dart';
import 'services/inventory_store.dart';

void main() => runApp(const CameraIpSearchApp());

class CameraIpSearchApp extends StatelessWidget {
  const CameraIpSearchApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Camera IP Search',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF101216),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE04452), brightness: Brightness.dark, surface: const Color(0xFF191D23)),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF101216), foregroundColor: Color(0xFFF5F6F8)),
      cardTheme: CardThemeData(color: const Color(0xFF1A1E25), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFF2B3039)))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: const Color(0xFF20252D), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
    ),
    home: const DashboardPage(),
  );
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final DeviceDiscoveryService _discovery = DeviceDiscoveryService();
  final InventoryStore _store = InventoryStore();
  final TextEditingController _search = TextEditingController();
  int _tab = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _discovery.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    final saved = await _store.load();
    if (!mounted) return;
    for (final device in saved) { _discovery.restoreDevice(device); }
    setState(() => _loading = false);
  }

  void _changed() {
    if (mounted) setState(() {});
    if (!_loading) { _store.save(_discovery.devices); }
  }

  @override
  void dispose() {
    _discovery.removeListener(_changed);
    _discovery.dispose();
    _search.dispose();
    super.dispose();
  }

  List<CameraDevice> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _discovery.devices;
    return _discovery.devices.where((d) => [d.ipAddress, d.macAddress, d.manufacturer, d.model].any((v) => v.toLowerCase().contains(q))).toList();
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addManual() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Add device manually'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Camera IPv4 address', hintText: '192.168.1.100')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add device')),
      ],
    ));
    controller.dispose();
    if (value == null || !mounted) return;
    try { await _discovery.addManualDevice(value); }
    on FormatException catch (e) { _message(e.message); }
  }

  Future<void> _scanSubnet() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Scan local subnet'),
      content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Local IPv4 / prefix', hintText: '192.168.1.20/24')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Start scan')),
      ],
    ));
    controller.dispose();
    if (value == null || !mounted) return;
    try {
      final parts = value.trim().split('/');
      final ip = InternetAddress.tryParse(parts.first);
      final prefix = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (ip == null || ip.type != InternetAddressType.IPv4 || prefix == null || prefix < 1 || prefix > 30) {
        throw const FormatException('Enter a valid IPv4 CIDR such as 192.168.1.20/24.');
      }
      final maskValue = (0xffffffff << (32 - prefix)) & 0xffffffff;
      final mask = InternetAddress.fromRawAddress([(maskValue >> 24) & 255, (maskValue >> 16) & 255, (maskValue >> 8) & 255, maskValue & 255]);
      await _discovery.scanSubnet(ip, mask);
    } on FormatException catch (e) { _message(e.message); }
  }

  Future<void> _check(CameraDevice device) async {
    _message('Checking ${device.ipAddress}…');
    final result = await _discovery.checkReachability(device);
    if (!mounted) return;
    _discovery.updateReachability(device, result);
    _message('${device.ipAddress}: $result');
  }

  @override
  Widget build(BuildContext context) {
    final devices = _filtered;
    return Scaffold(
      appBar: AppBar(title: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFE04452), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.camera_alt_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('OXITA', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          Text('CAMERA IP SEARCH', style: TextStyle(fontSize: 10, color: Color(0xFF9AA3B1), letterSpacing: 1.2)),
        ]),
      ]), actions: [IconButton(onPressed: _addManual, tooltip: 'Add device', icon: const Icon(Icons.add_circle_outline_rounded))]),
      body: SafeArea(child: IndexedStack(index: _tab, children: [_overview(devices), _deviceList(devices), _tools()])),
      floatingActionButton: _tab == 2 ? null : FloatingActionButton.extended(
        onPressed: () => _discovery.isScanning ? _discovery.cancelDiscovery() : _discovery.startDiscovery(),
        backgroundColor: const Color(0xFFE04452), foregroundColor: Colors.white,
        icon: Icon(_discovery.isScanning ? Icons.stop_rounded : Icons.radar_rounded),
        label: Text(_discovery.isScanning ? 'Stop scan' : 'Discover cameras'),
      ),
      bottomNavigationBar: NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() => _tab = v), destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Overview'),
        NavigationDestination(icon: Icon(Icons.videocam_outlined), label: 'Devices'),
        NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Tools'),
      ]),
    );
  }

  Widget _heading(String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
    const SizedBox(height: 4),
    Text(subtitle, style: const TextStyle(color: Color(0xFF929BA8), fontSize: 13)),
  ]);

  Widget _metric(String label, String value, IconData icon) => Expanded(child: Card(child: Padding(
    padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: const Color(0xFFE66B76), size: 19),
      const SizedBox(height: 12),
      Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Color(0xFF9AA3B1), letterSpacing: 0.7, fontWeight: FontWeight.w700)),
    ]),
  )));

  Widget _overview(List<CameraDevice> devices) => RefreshIndicator(
    onRefresh: _discovery.startDiscovery,
    child: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 110), children: [
      _heading('Network overview', 'Discover and manage cameras on your local network'),
      const SizedBox(height: 16),
      Row(children: [
        _metric('TOTAL', '${devices.length}', Icons.devices_rounded),
        const SizedBox(width: 8),
        _metric('VERIFIED', '${devices.where((d) => !d.isCandidate).length}', Icons.verified_user_outlined),
        const SizedBox(width: 8),
        _metric('CANDIDATES', '${devices.where((d) => d.isCandidate).length}', Icons.search_rounded),
      ]),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(15), child: Row(children: [
        const Icon(Icons.wifi_tethering_rounded, color: Color(0xFF6DD6A6), size: 26),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_discovery.isScanning ? 'Discovery in progress' : 'Network status', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(_discovery.status, style: const TextStyle(color: Color(0xFF9AA3B1), fontSize: 12)),
        ])),
        if (_discovery.isScanning) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]))),
      const SizedBox(height: 22),
      _heading('Recently discovered', 'Your saved camera inventory'),
      const SizedBox(height: 12),
      if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
      else if (devices.isEmpty) _empty()
      else ...devices.take(5).map(_deviceCard),
      if (devices.length > 5) TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('View all devices')),
    ]),
  );

  Widget _deviceList(List<CameraDevice> devices) => Column(children: [
    Padding(padding: const EdgeInsets.fromLTRB(18, 14, 18, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Device inventory', '${devices.length} device(s) saved on this phone'),
      const SizedBox(height: 14),
      TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(
        hintText: 'Search IP, MAC, model or manufacturer',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded)),
      )),
    ])),
    Expanded(child: devices.isEmpty ? _empty() : ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: devices.map(_deviceCard).toList())),
  ]);

  Widget _tools() => ListView(padding: const EdgeInsets.all(18), children: [
    _heading('Network tools', 'Utilities for installers and field technicians'),
    const SizedBox(height: 16),
    _tool(Icons.radar_rounded, 'ONVIF + project discovery', 'Probe active IPv4 interfaces using WS-Discovery and UDP 9988.', () => _discovery.startDiscovery()),
    _tool(Icons.lan_rounded, 'Bounded subnet scan', 'Scan a user-entered local CIDR range; open ports remain unverified candidates.', _scanSubnet),
    _tool(Icons.add_link_rounded, 'Add device manually', 'Add a known camera IPv4 address.', _addManual),
    _tool(Icons.info_outline_rounded, 'Protocol compatibility', 'ONVIF discovery and project Contract B discovery are implemented in this foundation. Provisioning actions remain disabled until validated.', () => showAboutDialog(context: context, applicationName: 'Camera IP Search Mobile', applicationVersion: '0.1.0')),
  ]);

  Widget _empty() => Padding(padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24), child: Column(children: [
    Icon(Icons.videocam_off_outlined, size: 42, color: Colors.blueGrey.shade300),
    const SizedBox(height: 12),
    const Text('No cameras discovered yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    const Text('Connect your phone to the same local network as the cameras, then start discovery.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF929BA8), height: 1.4)),
  ]));

  Widget _deviceCard(CameraDevice device) => Card(margin: const EdgeInsets.only(bottom: 10), child: InkWell(
    borderRadius: BorderRadius.circular(18), onTap: () => _details(device),
    child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0xFF292E38), borderRadius: BorderRadius.circular(13)),
        child: Icon(device.isCandidate ? Icons.device_unknown_rounded : Icons.videocam_rounded, color: device.isCandidate ? const Color(0xFFE7B45D) : const Color(0xFFE66B76))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(device.ipAddress, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 3),
        Text('${device.manufacturer} · ${device.model}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF9AA3B1), fontSize: 12)),
        const SizedBox(height: 5),
        Text(device.discoverySources.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF727D8B), fontSize: 10)),
      ])),
      const Icon(Icons.chevron_right_rounded, color: Color(0xFF8993A1)),
    ])),
  ));

  Widget _tool(IconData icon, String title, String subtitle, VoidCallback action) => Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
    leading: Icon(icon, color: const Color(0xFFE66B76)),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
    trailing: const Icon(Icons.chevron_right_rounded), onTap: action,
  ));

  Future<void> _details(CameraDevice d) async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF191D23), builder: (context) => SafeArea(
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
        const SizedBox(height: 18),
        Text(d.ipAddress, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        Text('${d.manufacturer} · ${d.model}', style: const TextStyle(color: Color(0xFF9AA3B1))),
        const SizedBox(height: 16),
        _detail('MAC address', d.macAddress),
        _detail('Firmware', d.firmwareVersion),
        _detail('Activation', d.activationState),
        _detail('Interface', d.interfaceName),
        _detail('Discovery source', d.discoverySources.join(', ')),
        _detail('Reachability', d.reachabilityStatus),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(onPressed: () { Navigator.pop(context); _check(d); }, icon: const Icon(Icons.network_check_rounded), label: const Text('Check connection')),
          OutlinedButton.icon(onPressed: () async {
            final uri = Uri(scheme: 'http', host: d.ipAddress);
            if (await canLaunchUrl(uri)) { await launchUrl(uri, mode: LaunchMode.externalApplication); }
          }, icon: const Icon(Icons.open_in_browser_rounded), label: const Text('Open web UI')),
        ]),
        const SizedBox(height: 10),
        const Text('Network configuration, activation and firmware operations remain unavailable until their protocol, authentication and verification workflows are ported and validated.', style: TextStyle(color: Color(0xFF929BA8), fontSize: 12, height: 1.4)),
      ])),
    ));
  }

  Widget _detail(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
    SizedBox(width: 112, child: Text(label, style: const TextStyle(color: Color(0xFF929BA8), fontSize: 12))),
    Expanded(child: Text(value.isEmpty ? 'Not available' : value, style: const TextStyle(fontSize: 13))),
  ]));
}
