import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/platform/report_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(ReportFilePicker.channel, null);
  });

  test('pickReportFile() returns a PickedReportFile when the native side succeeds', () async {
    messenger.setMockMethodCallHandler(ReportFilePicker.channel, (call) async {
      expect(call.method, 'pickReportFile');
      return <String, dynamic>{
        'path': '/data/user/0/com.example.mobile/cache/report_uploads/report_abc.pdf',
        'name': 'blood_test.pdf',
        'sizeBytes': 204800,
      };
    });

    final picked = await ReportFilePicker.pickReportFile();

    expect(picked, isNotNull);
    expect(picked!.path, '/data/user/0/com.example.mobile/cache/report_uploads/report_abc.pdf');
    expect(picked.name, 'blood_test.pdf');
    expect(picked.sizeBytes, 204800);
  });

  test('pickReportFile() returns null when the user cancels', () async {
    messenger.setMockMethodCallHandler(ReportFilePicker.channel, (call) async => null);

    final picked = await ReportFilePicker.pickReportFile();

    expect(picked, isNull);
  });

  test('pickReportFile() returns null if the native result is missing a required field', () async {
    messenger.setMockMethodCallHandler(
      ReportFilePicker.channel,
      (call) async => <String, dynamic>{'path': '/tmp/x.pdf', 'name': 'x.pdf'},
    );

    final picked = await ReportFilePicker.pickReportFile();

    expect(picked, isNull);
  });

  test('pickReportFile() propagates a PlatformException from the native side', () async {
    messenger.setMockMethodCallHandler(ReportFilePicker.channel, (call) async {
      throw PlatformException(code: 'PICK_FAILED', message: 'Could not read the selected file.');
    });

    await expectLater(
      ReportFilePicker.pickReportFile(),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'PICK_FAILED')),
    );
  });

  test('pickReportFile() throws MissingPluginException when no native handler is registered', () async {
    // No handler registered at all — the default state for any platform
    // without an implementation (e.g. iOS today), and what `flutter_test`
    // gives every channel by default.
    await expectLater(
      ReportFilePicker.pickReportFile(),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
