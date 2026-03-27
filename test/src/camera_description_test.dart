import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/pretty_awesome_camera.dart';

void main() {
  group('CameraDescription', () {
    test('creates description with all properties', () {
      const description = CameraDescription(
        name: 'Back Camera',
        lensDirection: LensDirection.back,
        sensorOrientation: 90,
      );

      expect(description.name, 'Back Camera');
      expect(description.lensDirection, LensDirection.back);
      expect(description.sensorOrientation, 90);
    });

    test('is const constructible', () {
      const description = CameraDescription(
        name: 'Test Camera',
        lensDirection: LensDirection.front,
        sensorOrientation: 0,
      );

      expect(identical(description, description), true);
    });

    test('toString returns formatted string', () {
      const description = CameraDescription(
        name: 'Back Camera',
        lensDirection: LensDirection.back,
        sensorOrientation: 90,
      );

      expect(
        description.toString(),
        'CameraDescription(name: Back Camera, lensDirection: LensDirection.back, sensorOrientation: 90)',
      );
    });

    group('serialization - toJson', () {
      test('converts to JSON map', () {
        const description = CameraDescription(
          name: 'Back Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        final json = description.toJson();

        expect(json['name'], 'Back Camera');
        expect(json['lensDirection'], 'back');
        expect(json['sensorOrientation'], 90);
      });

      test('serializes front camera', () {
        const description = CameraDescription(
          name: 'Front Camera',
          lensDirection: LensDirection.front,
          sensorOrientation: 270,
        );

        final json = description.toJson();

        expect(json['lensDirection'], 'front');
        expect(json['sensorOrientation'], 270);
      });

      test('serializes external camera', () {
        const description = CameraDescription(
          name: 'USB Camera',
          lensDirection: LensDirection.external,
          sensorOrientation: 0,
        );

        final json = description.toJson();

        expect(json['lensDirection'], 'external');
      });
    });

    group('deserialization - fromJson', () {
      test('creates from JSON map', () {
        final json = {
          'name': 'Back Camera',
          'lensDirection': 'back',
          'sensorOrientation': 90,
        };

        final description = CameraDescription.fromJson(json);

        expect(description.name, 'Back Camera');
        expect(description.lensDirection, LensDirection.back);
        expect(description.sensorOrientation, 90);
      });

      test('deserializes front camera', () {
        final json = {
          'name': 'Front Camera',
          'lensDirection': 'front',
          'sensorOrientation': 270,
        };

        final description = CameraDescription.fromJson(json);

        expect(description.lensDirection, LensDirection.front);
      });

      test('deserializes external camera', () {
        final json = {
          'name': 'USB Camera',
          'lensDirection': 'external',
          'sensorOrientation': 0,
        };

        final description = CameraDescription.fromJson(json);

        expect(description.lensDirection, LensDirection.external);
      });
    });

    group('round-trip serialization', () {
      test('toJson/fromJson round-trip preserves data', () {
        const original = CameraDescription(
          name: 'Back Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        final json = original.toJson();
        final restored = CameraDescription.fromJson(json);

        expect(restored, original);
      });

      test('multiple cameras round-trip correctly', () {
        const cameras = [
          CameraDescription(
            name: 'Back Camera',
            lensDirection: LensDirection.back,
            sensorOrientation: 90,
          ),
          CameraDescription(
            name: 'Front Camera',
            lensDirection: LensDirection.front,
            sensorOrientation: 270,
          ),
        ];

        final jsonList = cameras.map((c) => c.toJson()).toList();
        final restored = jsonList
            .map((j) => CameraDescription.fromJson(j))
            .toList();

        expect(restored, cameras);
      });
    });

    group('equality', () {
      test('two descriptions with same properties are equal', () {
        const description1 = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );
        const description2 = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        expect(description1, description2);
      });

      test('two descriptions with different name are not equal', () {
        const description1 = CameraDescription(
          name: 'Camera 1',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );
        const description2 = CameraDescription(
          name: 'Camera 2',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        expect(description1, isNot(description2));
      });

      test('two descriptions with different lensDirection are not equal', () {
        const description1 = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );
        const description2 = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.front,
          sensorOrientation: 90,
        );

        expect(description1, isNot(description2));
      });

      test(
        'two descriptions with different sensorOrientation are not equal',
        () {
          const description1 = CameraDescription(
            name: 'Camera',
            lensDirection: LensDirection.back,
            sensorOrientation: 90,
          );
          const description2 = CameraDescription(
            name: 'Camera',
            lensDirection: LensDirection.back,
            sensorOrientation: 180,
          );

          expect(description1, isNot(description2));
        },
      );

      test('description equals itself', () {
        const description = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        expect(description, description);
      });
    });

    group('hashCode', () {
      test('equal descriptions have same hashCode', () {
        const description1 = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );
        const description2 = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        expect(description1.hashCode, description2.hashCode);
      });

      test('different descriptions likely have different hashCode', () {
        const description1 = CameraDescription(
          name: 'Camera 1',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );
        const description2 = CameraDescription(
          name: 'Camera 2',
          lensDirection: LensDirection.front,
          sensorOrientation: 180,
        );

        expect(description1.hashCode, isNot(description2.hashCode));
      });

      test('description hashCode consistent across calls', () {
        const description = CameraDescription(
          name: 'Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        expect(description.hashCode, description.hashCode);
      });

      test('can use descriptions in sets with hashCode', () {
        const description1 = CameraDescription(
          name: 'Back Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );
        const description2 = CameraDescription(
          name: 'Front Camera',
          lensDirection: LensDirection.front,
          sensorOrientation: 270,
        );
        const description3 = CameraDescription(
          name: 'Back Camera',
          lensDirection: LensDirection.back,
          sensorOrientation: 90,
        );

        final set = {description1, description2, description3};
        expect(set.length, 2);
        expect(set.contains(description1), true);
        expect(set.contains(description3), true);
      });
    });

    group('LensDirection enum', () {
      test('has front value', () {
        expect(LensDirection.front, isNotNull);
      });

      test('has back value', () {
        expect(LensDirection.back, isNotNull);
      });

      test('has external value', () {
        expect(LensDirection.external, isNotNull);
      });

      test('enum values are distinct', () {
        expect(LensDirection.front == LensDirection.back, false);
        expect(LensDirection.back == LensDirection.external, false);
        expect(LensDirection.front == LensDirection.external, false);
      });
    });
  });
}
