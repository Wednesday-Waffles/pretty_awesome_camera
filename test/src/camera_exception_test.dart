import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_awesome_camera/src/camera_exception.dart';

void main() {
  group('CameraException', () {
    test('creates exception with code and message', () {
      const exception = CameraException(
        code: 'test_error',
        message: 'Test error message',
      );

      expect(exception.code, 'test_error');
      expect(exception.message, 'Test error message');
    });

    test('toString returns formatted string', () {
      const exception = CameraException(
        code: 'test_error',
        message: 'Test error message',
      );

      expect(
        exception.toString(),
        'CameraException(code: test_error, message: Test error message)',
      );
    });

    group('equality', () {
      test('two exceptions with same code and message are equal', () {
        const exception1 = CameraException(code: 'error', message: 'message');
        const exception2 = CameraException(code: 'error', message: 'message');

        expect(exception1, exception2);
      });

      test('two exceptions with different code are not equal', () {
        const exception1 = CameraException(code: 'error1', message: 'message');
        const exception2 = CameraException(code: 'error2', message: 'message');

        expect(exception1, isNot(exception2));
      });

      test('two exceptions with different message are not equal', () {
        const exception1 = CameraException(code: 'error', message: 'message1');
        const exception2 = CameraException(code: 'error', message: 'message2');

        expect(exception1, isNot(exception2));
      });

      test('exception equals itself', () {
        const exception = CameraException(code: 'error', message: 'message');

        expect(exception, exception);
      });
    });

    group('hashCode', () {
      test('equal exceptions have same hashCode', () {
        const exception1 = CameraException(code: 'error', message: 'message');
        const exception2 = CameraException(code: 'error', message: 'message');

        expect(exception1.hashCode, exception2.hashCode);
      });

      test('different exceptions likely have different hashCode', () {
        const exception1 = CameraException(code: 'error1', message: 'message1');
        const exception2 = CameraException(code: 'error2', message: 'message2');

        expect(exception1.hashCode, isNot(exception2.hashCode));
      });

      test('exception hashCode consistent across calls', () {
        const exception = CameraException(code: 'error', message: 'message');

        expect(exception.hashCode, exception.hashCode);
      });
    });

    test('implements Exception interface', () {
      const exception = CameraException(code: 'test', message: 'Test message');

      expect(exception, isA<Exception>());
    });
  });
}
