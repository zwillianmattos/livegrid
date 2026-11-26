import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livegrid/app/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('livegrid/control');
  final calls = <MethodCall>[];
  late NativeBridge bridge;

  setUp(() {
    calls.clear();
    bridge = NativeBridge(control: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('shareFile sends path', () async {
    await bridge.shareFile('/tmp/livegrid_h.mp4');
    expect(calls, hasLength(1));
    expect(calls.single.method, 'shareFile');
    expect(calls.single.arguments, {'path': '/tmp/livegrid_h.mp4'});
  });

  test('openGallery sends no args', () async {
    await bridge.openGallery();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'openGallery');
    expect(calls.single.arguments, isNull);
  });

  test('shareFile propagates PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'file_not_found');
        });
    expect(
      () => bridge.shareFile('/missing.mp4'),
      throwsA(isA<PlatformException>()),
    );
  });
}
