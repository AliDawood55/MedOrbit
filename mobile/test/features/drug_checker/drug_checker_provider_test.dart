import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/drug_checker/data/drug_checker_api.dart';
import 'package:mobile/features/drug_checker/models/drug_check_result.dart';
import 'package:mobile/features/drug_checker/providers/drug_checker_provider.dart';

DrugCheckResult _result({
  bool hasInteractions = true,
  DrugSeverity severity = DrugSeverity.moderate,
}) {
  return DrugCheckResult(
    hasInteractions: hasInteractions,
    interactionCount: hasInteractions ? 1 : 0,
    interactions: hasInteractions
        ? [
            DrugInteraction(
              drug1NameEn: 'Aspirin',
              drug1NameAr: 'أسبرين',
              drug2NameEn: 'Warfarin',
              drug2NameAr: 'وارفارين',
              severity: severity,
              description: 'Increases bleeding risk.',
            ),
          ]
        : const [],
    severitySummary: hasInteractions ? {severity.name: 1} : const {},
  );
}

void main() {
  test('initial state is empty with nothing submitted yet', () async {
    final container = _container(_FakeDrugCheckerApi());
    addTearDown(container.dispose);

    final state = container.read(drugCheckerControllerProvider);

    expect(state.medicationsInput, isEmpty);
    expect(state.isSubmitting, isFalse);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('submitting with fewer than 2 medications shows a validation error and never calls the API', () async {
    final api = _FakeDrugCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(container.read(drugCheckerControllerProvider).showValidationError, isTrue);
    expect(api.checkInteractionsCalls, isEmpty);
  });

  test('an empty input also fails the minimum-2 validation', () async {
    final api = _FakeDrugCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(container.read(drugCheckerControllerProvider).showValidationError, isTrue);
    expect(api.checkInteractionsCalls, isEmpty);
  });

  test('updateInput clears a previously shown validation error', () async {
    final api = _FakeDrugCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    await notifier.submit();
    expect(container.read(drugCheckerControllerProvider).showValidationError, isTrue);

    notifier.updateInput('Aspirin\nWarfarin');

    expect(container.read(drugCheckerControllerProvider).showValidationError, isFalse);
  });

  test('a successful submit parses "one medication per line" input and populates the result', () async {
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin, Aspirin');

    final ok = await notifier.submit();

    expect(ok, isTrue);
    expect(api.checkInteractionsCalls.single, ['Aspirin', 'Warfarin'],
        reason: 'newline/comma separated, trimmed, deduped case-insensitively, empties dropped');
    final state = container.read(drugCheckerControllerProvider);
    expect(state.result, isNotNull);
    expect(state.isSubmitting, isFalse);
    expect(state.error, isNull);
  });

  test('a second submit while one is in flight is ignored', () async {
    final completer = Completer<DrugCheckResult>();
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');

    final first = notifier.submit();
    final second = await notifier.submit();

    expect(second, isFalse);
    completer.complete(_result());
    await first;
    expect(api.checkInteractionsCalls, hasLength(1));
  });

  test('a submit failure sets a categorized, safe error and keeps no stale result', () async {
    final api = _FakeDrugCheckerApi()
      ..checkInteractionsResults.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    final state = container.read(drugCheckerControllerProvider);
    expect(state.error, DrugCheckErrorKind.serviceUnavailable);
    expect(state.result, isNull);
    expect(state.isSubmitting, isFalse);
  });

  test('a timeout failure categorizes as timeout', () async {
    final api = _FakeDrugCheckerApi()
      ..checkInteractionsResults.add(
        const ApiException(message: 'Too slow', code: ApiException.codeReceiveTimeout),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');

    await notifier.submit();

    expect(
      container.read(drugCheckerControllerProvider).error,
      DrugCheckErrorKind.timeout,
    );
  });

  test('retry resubmits the last medication list without requiring the input again', () async {
    final api = _FakeDrugCheckerApi()
      ..checkInteractionsResults.add(
        const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
      )
      ..checkInteractionsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');
    await notifier.submit();
    expect(container.read(drugCheckerControllerProvider).error, DrugCheckErrorKind.generic);

    final ok = await notifier.retry();

    expect(ok, isTrue);
    expect(container.read(drugCheckerControllerProvider).result, isNotNull);
    expect(container.read(drugCheckerControllerProvider).error, isNull);
    expect(api.checkInteractionsCalls, [
      ['Aspirin', 'Warfarin'],
      ['Aspirin', 'Warfarin'],
    ]);
  });

  test('retry before anything has been submitted is a no-op', () async {
    final api = _FakeDrugCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);

    final ok = await notifier.retry();

    expect(ok, isFalse);
    expect(api.checkInteractionsCalls, isEmpty);
  });

  test('reset clears input, result, and error', () async {
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');
    await notifier.submit();
    expect(container.read(drugCheckerControllerProvider).result, isNotNull);

    notifier.reset();

    final state = container.read(drugCheckerControllerProvider);
    expect(state.medicationsInput, isEmpty);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('reset() also clears whatever retry() would have resubmitted', () async {
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');
    await notifier.submit();

    notifier.reset();
    final ok = await notifier.retry();

    expect(ok, isFalse, reason: 'reset must forget the last submitted medication list too');
    expect(api.checkInteractionsCalls, hasLength(1));
  });

  test('a severe-interaction result is surfaced through state.result as-is', () async {
    final api = _FakeDrugCheckerApi()
      ..checkInteractionsResults.add(_result(severity: DrugSeverity.severe));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Aspirin\nWarfarin');

    await notifier.submit();

    expect(
      container.read(drugCheckerControllerProvider).result?.interactions.single.severity,
      DrugSeverity.severe,
    );
  });

  test('a no-interactions result is surfaced through state.result as-is', () async {
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result(hasInteractions: false));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(drugCheckerControllerProvider.notifier);
    notifier.updateInput('Paracetamol\nIbuprofen');

    await notifier.submit();

    expect(container.read(drugCheckerControllerProvider).result?.hasInteractions, isFalse);
  });

  test('medication names and results are never printed', () async {
    final api = _FakeDrugCheckerApi()..checkInteractionsResults.add(_result());
    final printed = <String>[];

    await runZoned(
      () async {
        final container = _container(api);
        addTearDown(container.dispose);
        final notifier = container.read(drugCheckerControllerProvider.notifier);
        notifier.updateInput('A very private medication\nAnother private one');
        await notifier.submit();
        notifier.reset();
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

ProviderContainer _container(DrugCheckerApi api) {
  final container = ProviderContainer(
    overrides: [drugCheckerApiProvider.overrideWithValue(api)],
  );
  // `drugCheckerControllerProvider` is `autoDispose` — keep it alive across
  // `await` boundaries the same way every other autoDispose provider test does.
  container.listen(drugCheckerControllerProvider, (previous, next) {});
  return container;
}

class _FakeDrugCheckerApi extends DrugCheckerApi {
  _FakeDrugCheckerApi() : super(Dio());

  final checkInteractionsResults = <Object>[];
  final checkInteractionsCalls = <List<String>>[];

  @override
  Future<DrugCheckResult> checkInteractions(List<String> medicationNames) {
    checkInteractionsCalls.add(medicationNames);
    final next = checkInteractionsResults.removeAt(0);
    if (next is Future<DrugCheckResult>) return next;
    if (next is DrugCheckResult) return Future.value(next);
    return Future.error(next);
  }
}
