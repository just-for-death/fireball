import 'dart:convert';

import 'remote_server.dart' show RemoteServer;

/// LAN endpoint for remote control (HTTP to [host]:[port]).
class RemoteEndpoint {
  const RemoteEndpoint({required this.host, required this.port});

  final String host;
  final int port;

  String get httpBase => 'http://$host:$port';

  @override
  String toString() => '$host:$port';
}

/// Encodes IPv4 + port into an 8-character URL-safe code (no server required).
String encodeRemotePairing(String ipv4, [int port = RemoteServer.port]) {
  final parts = ipv4.split('.');
  if (parts.length != 4) {
    throw ArgumentError.value(ipv4, 'ipv4', 'Expected IPv4');
  }
  final bytes = <int>[];
  for (final p in parts) {
    final o = int.tryParse(p);
    if (o == null || o < 0 || o > 255) {
      throw ArgumentError.value(ipv4, 'ipv4', 'Invalid octet');
    }
    bytes.add(o);
  }
  if (port < 0 || port > 65535) {
    throw ArgumentError.value(port, 'port');
  }
  bytes.add((port >> 8) & 0xff);
  bytes.add(port & 0xff);
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Formats [encodeRemotePairing] output as `XXXX-XXXX` for readability.
String formatPairingCodeDisplay(String code) {
  final c = code.replaceAll(RegExp(r'[\s\-]'), '');
  if (c.length <= 4) return c;
  return '${c.substring(0, 4)}-${c.substring(4)}';
}

/// Decodes [encodeRemotePairing] output (case-insensitive, ignores spaces and hyphens).
RemoteEndpoint decodeRemotePairing(String input) {
  var s = input.trim().replaceAll(RegExp(r'[\s\-]'), '');
  if (s.isEmpty) {
    throw FormatException('Empty pairing code');
  }
  // Restore base64 padding
  while (s.length % 4 != 0) {
    s += '=';
  }
  List<int> bytes;
  try {
    bytes = base64Url.decode(s);
  } catch (_) {
    throw FormatException('Invalid pairing code');
  }
  if (bytes.length != 6) {
    throw FormatException('Invalid pairing code');
  }
  final port = (bytes[4] << 8) | bytes[5];
  final ip = '${bytes[0]}.${bytes[1]}.${bytes[2]}.${bytes[3]}';
  return RemoteEndpoint(host: ip, port: port);
}

/// Parses HTTP(S) URLs, `host:port`, IPv4, or a pairing code from QR/manual entry.
RemoteEndpoint? parseRemoteConnectionString(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;

  if (s.startsWith('http://') || s.startsWith('https://')) {
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return null;
    final int port;
    if (uri.hasPort) {
      port = uri.port;
    } else if (uri.scheme == 'https') {
      port = 443;
    } else {
      // Plain http://host without port — use Fireball remote port, not 80.
      port = RemoteServer.port;
    }
    return RemoteEndpoint(host: uri.host, port: port);
  }

  // Custom schemes: fbremote://pair?c=CODE or fireball://remote?c=CODE
  final asUri = Uri.tryParse(s);
  if (asUri != null &&
      asUri.scheme.isNotEmpty &&
      asUri.scheme != 'http' &&
      asUri.scheme != 'https') {
    final c = asUri.queryParameters['c'] ??
        asUri.queryParameters['code'] ??
        _lastNonEmptySegment(asUri.path);
    if (c != null && c.isNotEmpty) {
      try {
        return decodeRemotePairing(c);
      } catch (_) {}
    }
  }

  // host:port (IPv4 or simple hostname, e.g. music.local:7771)
  final colonIdx = s.lastIndexOf(':');
  if (colonIdx > 0 && !s.contains('//')) {
    final hostPart = s.substring(0, colonIdx);
    final portPart = s.substring(colonIdx + 1);
    if (RegExp(r'^\d+$').hasMatch(portPart)) {
      final p = int.tryParse(portPart);
      if (p != null && p >= 0 && p <= 65535) {
        if (_isIpv4(hostPart)) {
          return RemoteEndpoint(host: hostPart, port: p);
        }
        if (_isSimpleHostname(hostPart)) {
          return RemoteEndpoint(host: hostPart, port: p);
        }
      }
    }
  }

  if (_isIpv4(s)) {
    return RemoteEndpoint(host: s, port: RemoteServer.port);
  }

  // Pairing code (8+ chars base64url)
  if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s.replaceAll(RegExp(r'[\s\-]'), '')) &&
      s.replaceAll(RegExp(r'[\s\-]'), '').length >= 6) {
    try {
      return decodeRemotePairing(s);
    } catch (_) {}
  }

  return null;
}

String? _lastNonEmptySegment(String path) {
  final parts = path.split('/').where((e) => e.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  return parts.last;
}

bool _isIpv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

/// mDNS / LAN names like `music.local` (not IPv6 — those need a full URL).
bool _isSimpleHostname(String s) {
  if (s.isEmpty || s.length > 253) return false;
  return RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$')
      .hasMatch(s);
}
