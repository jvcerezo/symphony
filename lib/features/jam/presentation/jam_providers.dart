import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio_player/data/services/symphony_audio_handler.dart';
import '../../audio_player/presentation/controllers/audio_player_providers.dart';
import '../../settings/presentation/controllers/personalization_provider.dart';
import '../data/handler_jam_players.dart';
import '../data/jam_guest_service.dart';
import '../data/jam_host_service.dart';
import '../data/jam_transport.dart';
import '../domain/jam_state.dart';

/// This device's part in a Jam.
sealed class JamSession {
  const JamSession();
}

/// Not in a Jam. [endReason] says why the last one ended (null when none
/// did or the user left), [error] why starting or joining failed.
class JamIdle extends JamSession {
  const JamIdle({this.endReason, this.error});
  final String? endReason;
  final String? error;
}

/// Starting to host, or connecting to a host.
class JamConnecting extends JamSession {
  const JamConnecting({required this.hosting});
  final bool hosting;
}

class JamHosting extends JamSession {
  const JamHosting({required this.code, required this.port, required this.addresses, required this.members});
  final String code;
  final int port;

  /// This device's local network addresses, most likely first.
  final List<String> addresses;
  final List<JamMember> members;

  JamHosting withMembers(List<JamMember> members) =>
      JamHosting(code: code, port: port, addresses: addresses, members: members);
}

class JamJoined extends JamSession {
  const JamJoined({required this.hostName, required this.members, required this.permissions});
  final String hostName;
  final List<JamMember> members;
  final JamPermissions permissions;

  JamJoined withMembers(List<JamMember> members) =>
      JamJoined(hostName: hostName, members: members, permissions: permissions);
}

/// Splits "192.168.1.5:41234" into host and port; null if it isn't one.
({String host, int port})? parseJamAddress(String input) {
  final text = input.trim();
  final colon = text.lastIndexOf(':');
  if (colon <= 0 || colon == text.length - 1) return null;
  final host = text.substring(0, colon).trim();
  final port = int.tryParse(text.substring(colon + 1).trim());
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return (host: host, port: port);
}

/// Starts, joins and leaves Jams on the local network.
class JamController extends StateNotifier<JamSession> {
  JamController({
    required SymphonyAudioHandler handler,
    required String Function() displayName,
    Future<JamServer> Function()? bind,
    Future<JamConnection> Function(String host, int port)? connect,
    Future<List<String>> Function()? addresses,
  })  : _handler = handler,
        _displayName = displayName,
        _bind = bind ?? bindLanJamServer,
        _connect = connect ?? connectLanJam,
        _addresses = addresses ?? localNetworkAddresses,
        super(const JamIdle());

  final SymphonyAudioHandler _handler;
  final String Function() _displayName;
  final Future<JamServer> Function() _bind;
  final Future<JamConnection> Function(String host, int port) _connect;
  final Future<List<String>> Function() _addresses;

  JamHostService? _host;
  JamGuestService? _guest;
  final _subs = <StreamSubscription<Object?>>[];

  bool get isSupported => lanJamSupported;

  Future<void> host() async {
    if (state is! JamIdle) return;
    state = const JamConnecting(hosting: true);
    try {
      final server = await _bind();
      final host = JamHostService(
        player: HandlerJamHostPlayer(_handler),
        server: server,
        hostName: _displayName(),
      );
      _host = host;
      host.start();
      _subs.add(host.membersStream.listen((members) {
        final s = state;
        if (s is JamHosting) state = s.withMembers(members);
      }));
      state = JamHosting(code: host.code, port: host.port, addresses: await _addresses(), members: host.members);
    } catch (e) {
      developer.log('Could not start a Jam: $e', name: 'Jam');
      await _reset();
      state = const JamIdle(error: 'Could not start a Jam on this network');
    }
  }

  Future<void> join({required String host, required int port, required String code}) async {
    if (state is! JamIdle) return;
    state = const JamConnecting(hosting: false);
    final guest = JamGuestService(player: HandlerJamGuestPlayer(_handler), name: _displayName(), code: code.trim());
    _guest = guest;
    try {
      final connection = await _connect(host, port);
      _subs.add(guest.membersStream.listen((members) {
        final s = state;
        if (s is JamJoined) state = s.withMembers(members);
      }));
      _subs.add(guest.statusStream.listen((status) {
        if (status == JamGuestStatus.ended && identical(_guest, guest)) unawaited(_ended(guest.endReason));
      }));
      await guest.join(connection);
      if (guest.status != JamGuestStatus.joined) return;
      state = JamJoined(hostName: guest.hostName, members: guest.members, permissions: guest.permissions);
    } on JamJoinException catch (e) {
      await _reset();
      state = JamIdle(error: e.message);
    } catch (e) {
      developer.log('Could not join the Jam: $e', name: 'Jam');
      await _reset();
      state = const JamIdle(error: 'Could not reach that Jam. Check the address and that you are on the same Wi-Fi.');
    }
  }

  /// Ends the Jam when hosting, leaves it when a guest.
  Future<void> leave() async {
    final guest = _guest;
    _guest = null;
    await guest?.leave();
    await _reset();
    state = const JamIdle();
  }

  Future<void> _ended(String? reason) async {
    _guest = null;
    await _reset();
    state = JamIdle(endReason: reason == 'left' ? null : reason);
  }

  Future<void> _reset() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final host = _host;
    _host = null;
    await host?.stop();
    final guest = _guest;
    _guest = null;
    if (guest != null && guest.status != JamGuestStatus.ended) await guest.leave();
  }

  @override
  void dispose() {
    unawaited(_reset());
    super.dispose();
  }
}

final jamProvider = StateNotifierProvider<JamController, JamSession>((ref) {
  return JamController(
    handler: ref.watch(audioHandlerProvider),
    displayName: () => ref.read(personalizationProvider).displayName,
  );
});
