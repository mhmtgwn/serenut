import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum DiscoveredPrinterKind { windows, network, bluetooth, sunmi }

class DiscoveredPrinter {
  final String id;
  final String name;
  final DiscoveredPrinterKind kind;
  final String? address;
  final int? port;
  final bool isDefault;
  final bool requiresPrintTest;

  const DiscoveredPrinter({
    required this.id,
    required this.name,
    required this.kind,
    this.address,
    this.port,
    this.isDefault = false,
    this.requiresPrintTest = true,
  });
}

class DiscoveredSerialDevice {
  final String port;
  final String name;

  const DiscoveredSerialDevice({required this.port, required this.name});
}

class PrinterDiscoveryService {
  final Future<Socket> Function(String host, int port, Duration timeout)
      _connect;

  PrinterDiscoveryService({
    Future<Socket> Function(String host, int port, Duration timeout)? connect,
  }) : _connect = connect ??
            ((host, port, timeout) =>
                Socket.connect(host, port, timeout: timeout));

  /// Lists all printers registered in the Windows spooler via WMI.
  ///
  /// Uses `Get-CimInstance Win32_Printer` instead of `Get-Printer` for two
  /// reasons:
  ///  1. `Get-Printer` is part of the optional PrintManagement module which
  ///     is absent on Windows Home editions.
  ///  2. When a PowerShell script is passed as a `-Command` argument by
  ///     Dart's `Process.run`, the shell strips `$` prefixes so `$_.Name`
  ///     becomes `.Name` and the whole script fails silently.
  ///     We avoid this by encoding the script as Base64 UTF-16LE and using
  ///     `-EncodedCommand`.
  Future<List<DiscoveredPrinter>> listWindowsPrinters() async {
    if (!Platform.isWindows) return const [];

    // Script uses $_ inside ForEach-Object — must be passed via
    // -EncodedCommand to prevent Dart/shell from stripping the $ signs.
    const psScript = r'''
$defaultName = (Get-CimInstance Win32_Printer | Where-Object { $_.Default -eq $true } | Select-Object -First 1 -ExpandProperty Name)
$arr = @(Get-CimInstance Win32_Printer | ForEach-Object {
  [PSCustomObject]@{ name = $_.Name; port = $_.PortName; isDefault = ($_.Name -eq $defaultName) }
})
if ($arr.Count -eq 0) { Write-Output '[]'; exit 0 }
$arr | ConvertTo-Json -Compress
''';

    // Encode as UTF-16LE (what PowerShell -EncodedCommand expects).
    // psScript is ASCII-only so each codeUnit fits in one UTF-16LE word.
    final utf16LeBytes = <int>[];
    for (final cu in psScript.codeUnits) {
      utf16LeBytes.add(cu & 0xFF);
      utf16LeBytes.add((cu >> 8) & 0xFF);
    }
    final encoded = base64Encode(Uint8List.fromList(utf16LeBytes));

    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
      ).timeout(const Duration(seconds: 10));

      final stdout = result.stdout.toString().trim();
      final stderr = result.stderr.toString().trim();

      if (result.exitCode != 0 || stdout.isEmpty) {
        if (stderr.isNotEmpty) {
          throw Exception('PowerShell hata kodu ${result.exitCode}: $stderr');
        }
        return const [];
      }

      final decoded = jsonDecode(stdout);
      final rows = decoded is List ? decoded : [decoded];
      return rows.map((row) {
        final map = Map<String, dynamic>.from(row as Map);
        final name = map['name']?.toString() ?? 'Windows Yazıcısı';
        return DiscoveredPrinter(
          id: 'windows:$name',
          name: name,
          kind: DiscoveredPrinterKind.windows,
          address: map['port']?.toString(),
          isDefault: map['isDefault'] == true,
        );
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<DiscoveredSerialDevice>> listSerialDevices(
    List<String> availablePorts,
  ) async {
    if (availablePorts.isEmpty) return const [];
    if (!Platform.isWindows) {
      return availablePorts
          .map((port) => DiscoveredSerialDevice(port: port, name: port))
          .toList(growable: false);
    }

    const script = r'''
@(Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match '\(COM\d+\)' } | ForEach-Object {
  if ($_.Name -match '\((COM\d+)\)') {
    [PSCustomObject]@{ port = $Matches[1]; name = $_.Name }
  }
}) | ConvertTo-Json -Compress
''';
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      ).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0 || result.stdout.toString().trim().isEmpty) {
        throw const FormatException('Seri aygıt listesi boş');
      }
      final decoded = jsonDecode(result.stdout.toString());
      final rows = decoded is List ? decoded : [decoded];
      final byPort = <String, String>{
        for (final row in rows)
          if (row is Map && row['port'] != null)
            row['port'].toString().toUpperCase():
                (row['name']?.toString() ?? row['port'].toString()),
      };
      return availablePorts
          .map((port) => DiscoveredSerialDevice(
                port: port,
                name: byPort[port.toUpperCase()] ?? port,
              ))
          .toList(growable: false);
    } catch (_) {
      return availablePorts
          .map((port) => DiscoveredSerialDevice(port: port, name: port))
          .toList(growable: false);
    }
  }

  Future<List<String>> localIpv4Subnets() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final subnets = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final octets = address.address.split('.');
        if (octets.length == 4) {
          subnets.add('${octets[0]}.${octets[1]}.${octets[2]}');
        }
      }
    }
    return subnets.toList()..sort();
  }

  /// Scans a /24 subnet with bounded concurrency. An open port is only an
  /// ESC/POS candidate and still requires an explicit print test.
  Future<List<DiscoveredPrinter>> scanSubnet(
    String subnet, {
    List<int> ports = const [9100],
    Duration timeout = const Duration(milliseconds: 220),
    int concurrency = 32,
  }) async {
    if (!RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(subnet)) {
      throw ArgumentError.value(subnet, 'subnet', 'Geçersiz /24 ağ öneki');
    }
    final results = <DiscoveredPrinter>[];
    var nextHost = 1;

    Future<void> worker() async {
      while (nextHost <= 254) {
        final host = nextHost++;
        final ip = '$subnet.$host';
        for (final port in ports) {
          Socket? socket;
          try {
            socket = await _connect(ip, port, timeout);
            results.add(DiscoveredPrinter(
              id: 'network:$ip:$port',
              name: 'ESC/POS adayı $ip:$port',
              kind: DiscoveredPrinterKind.network,
              address: ip,
              port: port,
            ));
          } catch (_) {
            // Closed/unreachable hosts are expected during discovery.
          } finally {
            await socket?.close();
          }
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    results.sort((a, b) => (a.address ?? '').compareTo(b.address ?? ''));
    return results;
  }
}
