import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/config/links.dart';
import 'package:symphony/core/utils/widget_image.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/for_you/data/listening_history.dart';
import 'package:symphony/features/for_you/domain/listening_log.dart';
import 'package:symphony/features/for_you/domain/play_event.dart';
import 'package:symphony/features/for_you/domain/recap.dart';
import 'package:symphony/features/for_you/presentation/for_you_providers.dart';
import 'package:symphony/features/for_you/presentation/recap_screen.dart';
import 'package:symphony/features/for_you/presentation/recap_share_card.dart';

class _MemoryStore implements ListeningLogStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

ListeningLog _log() {
  final log = ListeningLog();
  final songs = [
    ('drivers license', 'Olivia Rodrigo', 7),
    ('Espresso', 'Sabrina Carpenter', 5),
    ('Yellow', 'Coldplay', 4),
    ('Ivy', 'Frank Ocean', 3),
    ('A Very Long Song Title That Has To Be Cut Short Somewhere', 'An Artist With A Long Name', 2),
  ];
  for (final (title, artist, plays) in songs) {
    for (var i = 0; i < plays; i++) {
      log.add(PlayEvent.of(Track(id: '$title$i', title: title, artist: artist),
          listened: const Duration(minutes: 3), length: const Duration(minutes: 3), at: DateTime(2026, 10, 1 + i, 23)));
    }
  }
  return log;
}

/// PNG width and height, from its header.
(int, int) _pngSize(Uint8List png) {
  final b = ByteData.sublistView(png);
  return (b.getUint32(16), b.getUint32(20));
}

void main() {
  // Real text in the saved previews when this machine has the app's font.
  setUpAll(() async {
    final font = File(r'C:\Windows\Fonts\segoeui.ttf');
    final bold = File(r'C:\Windows\Fonts\segoeuib.ttf');
    if (!font.existsSync()) return;
    final loader = FontLoader('Segoe UI')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
    if (bold.existsSync()) loader.addFont(Future.value(ByteData.sublistView(bold.readAsBytesSync())));
    await loader.load();
  });

  testWidgets('every card renders as a 1080×1920 picture', (tester) async {
    final recap = Recap.year(_log(), 2026);
    final out = Platform.environment['SYMPHONY_CARD_PREVIEW_DIR'];
    for (final kind in RecapCardKind.values) {
      final png = await tester.runAsync(() => renderWidgetToPng(
            RecapShareCard(recap: recap, kind: kind),
            size: RecapShareCard.size,
            view: tester.view,
          ));
      expect(_pngSize(png!), (1080, 1920), reason: kind.name);
      if (out != null) File('$out/${kind.name}.png').writeAsBytesSync(png);
    }
  });

  testWidgets('sharing from the recap sends the card and a link to Symphony', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final history = ListeningHistory(store: _MemoryStore());
    await tester.runAsync(() => history.loaded);
    for (final e in _log().recent) {
      history.record(e);
    }
    final shared = <(String, String, (int, int))>[];

    await tester.pumpWidget(ProviderScope(
      overrides: [listeningHistoryProvider.overrideWith((ref) => history)],
      child: MaterialApp(
        home: RecapScreen(
          initialYear: 2026,
          share: (png, {required fileName, required text}) async => shared.add((fileName, text, _pngSize(png))),
        ),
      ),
    ));
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Share'));
      // Rendering happens off the fake clock.
      for (var i = 0; i < 50 && shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();

    expect(shared, hasLength(1));
    final (fileName, text, size) = shared.single;
    expect(fileName, 'symphony-2026-minutes.png');
    expect(text, contains(SymphonyLinks.site));
    expect(size, (1080, 1920));
  });

  test('cards ask only for the artwork they show', () {
    final recap = Recap.year(_log(), 2026);
    expect(RecapShareCard.artworkFor(recap, RecapCardKind.minutes), isEmpty);
    expect(RecapShareCard.artworkFor(recap, RecapCardKind.topSongs).length, lessThanOrEqualTo(5));
  });
}
