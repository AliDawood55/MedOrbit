import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/my_reports/data/my_reports_api.dart';
import 'package:mobile/features/my_reports/models/my_report_item.dart';
import 'package:mobile/features/my_reports/providers/my_reports_provider.dart';

MyReportItem _item({String id = 'summary-1'}) {
  return MyReportItem(
    id: id,
    type: MyReportType.reportSummary,
    createdAt: DateTime.parse('2026-08-01T09:00:00.000Z'),
    summaryAr: 'ملخص',
    summaryEn: 'Summary',
    extractedTextPreview: 'preview',
    modelUsed: 'qwen2:7b',
    sourceFileType: 'text',
  );
}

void main() {
  test('loads successfully on construction and populates the list', () async {
    final api = _FakeMyReportsApi()..results.add([_item()]);
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(myReportsControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(myReportsControllerProvider);
    expect(state.hasValue, isTrue);
    expect(state.value, hasLength(1));
    expect(state.value!.single.id, 'summary-1');
  });

  test('an empty list loads as an empty (not error, not null) value', () async {
    final api = _FakeMyReportsApi()..results.add(<MyReportItem>[]);
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(myReportsControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(myReportsControllerProvider);
    expect(state.hasValue, isTrue);
    expect(state.value, isEmpty);
  });

  test('a load failure surfaces as an error state, and load() again recovers', () async {
    final api = _FakeMyReportsApi()
      ..results.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      )
      ..results.add([_item()]);
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(myReportsControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(myReportsControllerProvider).hasError, isTrue);

    await container.read(myReportsControllerProvider.notifier).load();

    final state = container.read(myReportsControllerProvider);
    expect(state.hasValue, isTrue);
    expect(state.value, hasLength(1));
  });

  test('load() shows a loading state again while refreshing', () async {
    final api = _FakeMyReportsApi()
      ..results.add([_item()])
      ..results.add([_item(), _item(id: 'summary-2')]);
    final container = _container(api);
    addTearDown(container.dispose);
    container.read(myReportsControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final future = container.read(myReportsControllerProvider.notifier).load();
    expect(container.read(myReportsControllerProvider).isLoading, isTrue);
    await future;

    expect(container.read(myReportsControllerProvider).value, hasLength(2));
  });
}

ProviderContainer _container(MyReportsApi api) {
  final container = ProviderContainer(
    overrides: [myReportsApiProvider.overrideWithValue(api)],
  );
  // `myReportsControllerProvider` is `autoDispose` — keep it alive across
  // `await` boundaries the same way every other autoDispose provider test
  // does.
  container.listen(myReportsControllerProvider, (previous, next) {});
  return container;
}

class _FakeMyReportsApi extends MyReportsApi {
  _FakeMyReportsApi() : super(Dio());

  final results = <Object>[];

  @override
  Future<List<MyReportItem>> listReportSummaries() {
    final next = results.removeAt(0);
    if (next is Future<List<MyReportItem>>) return next;
    if (next is List<MyReportItem>) return Future.value(next);
    return Future.error(next);
  }
}
