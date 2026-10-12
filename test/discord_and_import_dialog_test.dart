import 'dart:convert';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/services/discord_activity.dart';
import 'package:symphony/features/audio_player/presentation/widgets/import_playlist_dialog.dart';

void main() {
  group('Discord listening status', () {
    final now = DateTime.utc(2026, 10, 12, 12);
    final song = MediaItem(
      id: 'yt_abc',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      album: 'After Hours',
      duration: const Duration(minutes: 3, seconds: 20),
      artUri: Uri.parse('https://i.ytimg.com/vi/abc/hq.jpg'),
    );

    test('shows the song, artist, art and a progress bar', () {
      final a = buildListeningActivity(item: song, playing: true, position: const Duration(seconds: 20), now: now)!;
      expect(a['type'], 2);
      expect(a['details'], 'Blinding Lights');
      expect(a['state'], 'by The Weeknd');
      final t = a['timestamps'] as Map;
      expect(t['start'], now.subtract(const Duration(seconds: 20)).millisecondsSinceEpoch);
      expect(t['end'], now.add(const Duration(minutes: 3)).millisecondsSinceEpoch);
      final assets = a['assets'] as Map;
      expect(assets['large_image'], 'https://i.ytimg.com/vi/abc/hq.jpg');
      expect(assets['large_text'], 'After Hours');
    });

    test('clears when paused or nothing is loaded', () {
      expect(buildListeningActivity(item: song, playing: false, position: Duration.zero, now: now), isNull);
      expect(buildListeningActivity(item: null, playing: true, position: Duration.zero, now: now), isNull);
    });

    test('local artwork falls back to the app icon; text fits Discord limits', () {
      final local = song.copyWith(title: 'X' * 200, artUri: Uri.file(r'C:\music\cover.jpg'), album: '');
      final a = buildListeningActivity(item: local, playing: true, position: Duration.zero, now: now)!;
      expect((a['assets'] as Map)['large_image'], startsWith('https://raw.githubusercontent.com/'));
      expect((a['details'] as String).length, 128);
      expect(buildListeningActivity(item: song.copyWith(title: 'X'), playing: true, position: Duration.zero, now: now)!['details'],
          hasLength(2));
    });

    test('frames are opcode, length, then JSON', () {
      final frame = encodeDiscordFrame(DiscordOp.handshake, {'v': 1, 'client_id': '42'});
      final head = ByteData.sublistView(frame, 0, 8);
      expect(head.getInt32(0, Endian.little), 0);
      expect(head.getInt32(4, Endian.little), frame.length - 8);
      expect(jsonDecode(utf8.decode(frame.sublist(8))), {'v': 1, 'client_id': '42'});
    });
  });

  group('Import dialog on a phone', () {
    Future<void> openDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: ImportPlaylistDialog())),
      ));
    }

    testWidgets('every source tab fits without cutting off', (tester) async {
      await openDialog(tester);
      expect(tester.takeException(), isNull);
      for (final name in ['Spotify', 'YouTube', 'Apple Music']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
        expect(paragraph.didExceedMaxLines, isFalse, reason: name);
        // Drawn whole inside its tab.
        final tab = find.ancestor(of: find.text(name), matching: find.byType(InkWell));
        final shown = tester.getRect(find.text(name));
        expect(tester.getRect(tab).contains(shown.topLeft) && tester.getRect(tab).contains(shown.bottomRight - const Offset(0.01, 0.01)),
            isTrue,
            reason: name);
      }
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('pasting a link switches tabs; presets fill the field', (tester) async {
      await openDialog(tester);
      expect(find.text('Spotify playlist link'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'https://music.apple.com/us/playlist/x/pl.1');
      await tester.pump();
      expect(find.text('Apple Music playlist link'), findsOneWidget);

      await tester.tap(find.text('YouTube'));
      await tester.pump();
      await tester.tap(find.text("Pop's Biggest Hits"));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, contains('list=RDCLAK'));
    });
  });
}
