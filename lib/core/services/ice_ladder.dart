/// ICE server ladder for the P2P session: Google STUN first, optional TURN
/// relay second. With TURN configured, WebRTC succeeds across cellular /
/// CG-NAT / double-NAT; without it, the existing 8s-timeout → R2 fallback
/// still guarantees transfer success.
const List<Map<String, String>> kStunServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun1.l.google.com:19302'},
  {'urls': 'stun:stun2.l.google.com:19302'},
];

/// Builds the `iceServers` config for `createPeerConnection`.
///
/// TURN is appended only when enabled **and** all credential parts are
/// present — any missing piece silently degrades to STUN-only.
List<Map<String, Object>> buildIceServers({
  required bool turnEnabled,
  List<String> urls = const [],
  String username = '',
  String credential = '',
}) {
  final servers = List<Map<String, Object>>.from(kStunServers);
  if (!turnEnabled || urls.isEmpty || username.isEmpty || credential.isEmpty) {
    return servers;
  }

  final turnUrls = <String>[
    for (final url in urls) ...[url, '$url?transport=tcp'],
  ];
  servers.add({
    'urls': turnUrls,
    'username': username,
    'credential': credential,
  });
  return servers;
}
