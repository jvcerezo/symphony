import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/features/audio_player/domain/entities/track.dart';
import 'package:symphony/features/for_you/data/listening_history.dart';
import 'package:symphony/features/for_you/domain/play_event.dart';
import 'package:symphony/features/for_you/presentation/for_you_providers.dart';
import 'package:symphony/features/for_you/presentation/recap_screen.dart';

class _MemoryStore implements ListeningLogStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String? value) async => value == null ? values.remove(key) : values[key] = value;
}

void main() {
  testWidgets('a year recap on a phone: every slide, no overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final history = ListeningHistory(store: _MemoryStore());
    await tester.runAsync(() => history.loaded);
    for (var d = 1; d <= 5; d++) {
      history.record(PlayEvent.of(
        Track(id: 's$d', title: 'A song with a rather long title number $d', artist: 'Artist ${d % 2}'),
        listened: const Duration(minutes: 3),
        length: const Duration(minutes: 3),
        at: DateTime(2026, 10, d, 23),
      ));
    }

    await tester.pumpWidget(ProviderScope(
      overrides: [listeningHistoryProvider.overrideWith((ref) => history)],
      child: const MaterialApp(home: RecapScreen(initialYear: 2026)),
    ));
    await tester.pump();

    expect(find.text('15'), findsOneWidget, reason: '5 plays of 3 minutes');
    expect(find.text('minutes of listening'), findsOneWidget);

    final seen = <String>[];
    for (final title in ['Your top artist', 'Your top songs', 'Your top artists', 'How you listen', '2026, wrapped up']) {
      await tester.tapAt(const Offset(300, 400));
      await tester.pumpAndSettle();
      if (find.text(title).evaluate().isNotEmpty) seen.add(title);
    }
    expect(seen, ['Your top artist', 'Your top songs', 'Your top artists', 'How you listen', '2026, wrapped up']);
    expect(find.text('You\'re a night owl'), findsNothing, reason: 'that was the slide before');
    expect(find.text('Play your top songs'), findsOneWidget);
  });

  testWidgets('switching to one month', (tester) async {
    final history = ListeningHistory(store: _MemoryStore());
    await tester.runAsync(() => history.loaded);
    history.record(PlayEvent.of(const Track(id: 'x', title: 'X', artist: 'A'),
        listened: const Duration(minutes: 3), length: const Duration(minutes: 3), at: DateTime(2026, 9, 3)));

    await tester.pumpWidget(ProviderScope(
      overrides: [listeningHistoryProvider.overrideWith((ref) => history)],
      child: const MaterialApp(home: RecapScreen(initialYear: 2026)),
    ));
    await tester.pump();
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('September 2026'));
    await tester.pumpAndSettle();

    expect(find.text('Your September 2026 in music'), findsOneWidget);
  });
}
