import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';
import 'package:symphony/features/audio_player/presentation/desktop/desktop_shell.dart';
import 'package:symphony/features/audio_player/presentation/mobile/mobile_shell.dart';
import 'package:symphony/features/audio_player/presentation/widgets/sidebar_nav.dart';
import 'package:symphony/features/playlist_import/domain/entities/spotify_playlist.dart';
import 'package:symphony/main.dart';

void main() {
  final samplePlaylist = SpotifyPlaylist(
    id: 'routing-playlist',
    title: 'Routing Mix',
    ownerName: 'Symphony',
    tracks: [
      Track(
        id: 'r-1',
        title: 'First Song',
        artist: 'Artist A',
        album: 'Album A',
        expectedDuration: const Duration(minutes: 3),
      ),
    ],
  );

  Future<void> pumpAt(
      WidgetTester tester, Size size, SymphonyAudioHandler handler) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(handler),
          activePlaylistProvider.overrideWith((ref) => samplePlaylist),
        ],
        child: const SymphonyApp(),
      ),
    );
  }

  testWidgets('wide window routes to DesktopShell with sidebar',
      (tester) async {
    final handler = SymphonyAudioHandler();
    addTearDown(() {
      handler.release();
    });
    await pumpAt(tester, const Size(1280, 800), handler);

    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(MobileShell), findsNothing);
    expect(find.byType(SidebarNav), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('Routing Mix'), findsWidgets);
  });

  testWidgets('narrow window routes to MobileShell with bottom navigation',
      (tester) async {
    final handler = SymphonyAudioHandler();
    addTearDown(() {
      handler.release();
    });
    await pumpAt(tester, const Size(420, 900), handler);

    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
    expect(find.byType(SidebarNav), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('PLAYLIST'), findsOneWidget);
    expect(find.text('Routing Mix'), findsWidgets);
  });
}
