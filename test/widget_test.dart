import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:symphony/main.dart';
import 'package:symphony/features/audio_player/data/services/symphony_audio_handler.dart';
import 'package:symphony/features/audio_player/presentation/controllers/audio_player_providers.dart';

void main() {
  testWidgets('SymphonyApp renders main search inputs and controls', (WidgetTester tester) async {
    final fakeHandler = SymphonyAudioHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWithValue(fakeHandler),
        ],
        child: const SymphonyApp(),
      ),
    );

    expect(find.text('Symphony Audio Player'), findsOneWidget);
    expect(find.text('Direct Stream Resolution'), findsOneWidget);
    expect(find.text('Track Title'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
    expect(find.text('Play Stream'), findsOneWidget);
  });
}
