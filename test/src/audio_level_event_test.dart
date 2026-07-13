import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

void main() {
  group('AudioLevelEvent', () {
    test('fromMap parses a full iOS payload', () {
      final event = AudioLevelEvent.fromMap(const {
        'amplitude': 0.42,
        'peakDbfs': -7.5,
        'averageDbfs': -21.3,
        'audioState': 'unknown',
        'timestampMs': 123456,
      });

      expect(event.amplitude, 0.42);
      expect(event.peakDbfs, -7.5);
      expect(event.averageDbfs, -21.3);
      expect(event.audioState, 'unknown');
      expect(event.timestampMs, 123456);
    });

    test('fromMap parses an Android payload without dBFS extras', () {
      final event = AudioLevelEvent.fromMap(const {
        'amplitude': 0.03,
        'audioState': 'sourceSilenced',
        'timestampMs': 987,
      });

      expect(event.amplitude, 0.03);
      expect(event.peakDbfs, isNull);
      expect(event.averageDbfs, isNull);
      expect(event.audioState, 'sourceSilenced');
      expect(event.timestampMs, 987);
    });

    test('fromMap tolerates missing keys with safe defaults', () {
      final event = AudioLevelEvent.fromMap(const {});

      expect(event.amplitude, 0.0);
      expect(event.audioState, 'unknown');
      expect(event.timestampMs, 0);
    });

    test('fromMap accepts integer amplitude values', () {
      final event = AudioLevelEvent.fromMap(const {
        'amplitude': 1,
        'timestampMs': 5,
      });

      expect(event.amplitude, 1.0);
    });

    test('equality and hashCode cover all fields', () {
      const a = AudioLevelEvent(
        amplitude: 0.5,
        peakDbfs: -6,
        averageDbfs: -18,
        audioState: 'active',
        timestampMs: 1,
      );
      const b = AudioLevelEvent(
        amplitude: 0.5,
        peakDbfs: -6,
        averageDbfs: -18,
        audioState: 'active',
        timestampMs: 1,
      );
      const c = AudioLevelEvent(
        amplitude: 0.5,
        audioState: 'active',
        timestampMs: 1,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('toMap round-trips through fromMap', () {
      const original = AudioLevelEvent(
        amplitude: 0.25,
        peakDbfs: -12,
        averageDbfs: -30,
        audioState: 'muted',
        timestampMs: 42,
      );

      expect(AudioLevelEvent.fromMap(original.toMap()), original);
    });
  });
}
