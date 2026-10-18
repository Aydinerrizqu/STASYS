import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssa_app/widgets/shot_replay_controls.dart';

void main() {
  testWidgets('controls render play button, slider, and reset', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShotReplayControls(
            progress: 1.0,
            hasTrace: true,
            isPlaying: false,
            onPlay: () {},
            onPause: () {},
            onSeek: (_) {},
            onReset: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('play icon swaps to pause while playing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShotReplayControls(
            progress: 0.4,
            hasTrace: true,
            isPlaying: true,
            onPlay: () {},
            onPause: () {},
            onSeek: (_) {},
            onReset: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('play button disabled when shot has no trace', (tester) async {
    var playCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShotReplayControls(
            progress: 1.0,
            hasTrace: false,
            isPlaying: false,
            onPlay: () => playCalled = true,
            onPause: () {},
            onSeek: (_) {},
            onReset: () {},
          ),
        ),
      ),
    );

    final playButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.play_arrow),
        matching: find.byType(IconButton),
      ),
    );
    expect(playButton.onPressed, isNull);

    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(playCalled, isFalse);
  });
}
