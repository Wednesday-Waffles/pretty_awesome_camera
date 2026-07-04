import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pretty_awesome_camera_example/recording_permutation_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recording permutation harness writes ffprobe metadata', (
    WidgetTester tester,
  ) async {
    final permissions = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    expect(
      permissions.values.every((status) => status.isGranted),
      isTrue,
      reason: 'Camera and microphone permissions are required.',
    );

    final scenarios = _scenariosFromEnvironment();
    final harness = RecordingPermutationHarness();
    final results = await harness.runAll(scenarios: scenarios);
    final produced = results.where((result) => !result.isSkipped).toList();

    expect(produced, isNotEmpty);
    for (final result in produced) {
      expect(result.error, isNull, reason: result.scenario.id);
      expect(result.metadataPath, isNotEmpty, reason: result.scenario.id);
      if (result.expectsOutput) {
        expect(result.videoPath, isNotEmpty, reason: result.scenario.id);
        expect(
          await File(result.videoPath!).exists(),
          isTrue,
          reason: result.videoPath,
        );
      } else {
        expect(result.videoPath, isNull, reason: result.scenario.id);
      }
      expect(
        await File(result.metadataPath!).exists(),
        isTrue,
        reason: result.metadataPath,
      );
      expect(result.expectedDuration.inMilliseconds, greaterThan(0));
    }
  });
}

List<RecordingPermutationScenario> _scenariosFromEnvironment() {
  const raw = String.fromEnvironment(
    'CAMERA_HARNESS_SCENARIOS',
    defaultValue: 'record_stop,rapid_start_stop',
  );
  return raw
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .map(RecordingPermutationScenarioLabel.fromId)
      .nonNulls
      .toList(growable: false);
}
