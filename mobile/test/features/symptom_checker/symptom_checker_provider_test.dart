import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/symptom_checker/data/symptom_checker_api.dart';
import 'package:mobile/features/symptom_checker/models/symptom_check_result.dart';
import 'package:mobile/features/symptom_checker/providers/symptom_checker_provider.dart';

SymptomCheckResult _result({
  TriageLevel triageLevel = TriageLevel.routine,
  String id = 'triage-1',
}) {
  return SymptomCheckResult(
    id: id,
    symptoms: const ['headache'],
    triageLevel: triageLevel,
    confidenceScore: 0.5,
    recommendations: 'See a general practitioner if symptoms persist.',
    followUpAction: 'book_appointment',
    recommendedSpecialtyNameEn: 'General Practice',
    recommendedSpecialtyNameAr: 'طب عام',
  );
}

void main() {
  test('initial state is empty with nothing submitted yet', () async {
    final container = _container(_FakeSymptomCheckerApi());
    addTearDown(container.dispose);

    final state = container.read(symptomCheckerControllerProvider);

    expect(state.symptomsInput, isEmpty);
    expect(state.isSubmitting, isFalse);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('submitting empty/whitespace input shows a validation error and never calls the API', () async {
    final api = _FakeSymptomCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('   \n  ,  \n ');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    expect(container.read(symptomCheckerControllerProvider).showValidationError, isTrue);
    expect(api.checkSymptomsCalls, isEmpty);
  });

  test('updateInput clears a previously shown validation error', () async {
    final api = _FakeSymptomCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    await notifier.submit();
    expect(container.read(symptomCheckerControllerProvider).showValidationError, isTrue);

    notifier.updateInput('headache');

    expect(container.read(symptomCheckerControllerProvider).showValidationError, isFalse);
  });

  test('a successful submit parses "one symptom per line" input and populates the result', () async {
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache\nfever, cough\n\nheadache');

    final ok = await notifier.submit();

    expect(ok, isTrue);
    expect(api.checkSymptomsCalls.single, ['headache', 'fever', 'cough'],
        reason: 'newline/comma separated, trimmed, deduped case-insensitively, empties dropped');
    final state = container.read(symptomCheckerControllerProvider);
    expect(state.result, isNotNull);
    expect(state.isSubmitting, isFalse);
    expect(state.error, isNull);
  });

  test('a second submit while one is in flight is ignored', () async {
    final completer = Completer<SymptomCheckResult>();
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache');

    final first = notifier.submit();
    final second = await notifier.submit();

    expect(second, isFalse);
    completer.complete(_result());
    await first;
    expect(api.checkSymptomsCalls, hasLength(1));
  });

  test('a submit failure sets a categorized, safe error and keeps no stale result', () async {
    final api = _FakeSymptomCheckerApi()
      ..checkSymptomsResults.add(
        const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache');

    final ok = await notifier.submit();

    expect(ok, isFalse);
    final state = container.read(symptomCheckerControllerProvider);
    expect(state.error, SymptomCheckErrorKind.serviceUnavailable);
    expect(state.result, isNull);
    expect(state.isSubmitting, isFalse);
  });

  test('a timeout failure categorizes as timeout', () async {
    final api = _FakeSymptomCheckerApi()
      ..checkSymptomsResults.add(
        const ApiException(message: 'Too slow', code: ApiException.codeReceiveTimeout),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache');

    await notifier.submit();

    expect(
      container.read(symptomCheckerControllerProvider).error,
      SymptomCheckErrorKind.timeout,
    );
  });

  test('retry resubmits the last symptom list without requiring the input again', () async {
    final api = _FakeSymptomCheckerApi()
      ..checkSymptomsResults.add(
        const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
      )
      ..checkSymptomsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache');
    await notifier.submit();
    expect(container.read(symptomCheckerControllerProvider).error, SymptomCheckErrorKind.generic);

    final ok = await notifier.retry();

    expect(ok, isTrue);
    expect(container.read(symptomCheckerControllerProvider).result, isNotNull);
    expect(container.read(symptomCheckerControllerProvider).error, isNull);
    expect(api.checkSymptomsCalls, [
      ['headache'],
      ['headache'],
    ]);
  });

  test('retry before anything has been submitted is a no-op', () async {
    final api = _FakeSymptomCheckerApi();
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);

    final ok = await notifier.retry();

    expect(ok, isFalse);
    expect(api.checkSymptomsCalls, isEmpty);
  });

  test('reset clears input, result, and error', () async {
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache');
    await notifier.submit();
    expect(container.read(symptomCheckerControllerProvider).result, isNotNull);

    notifier.reset();

    final state = container.read(symptomCheckerControllerProvider);
    expect(state.symptomsInput, isEmpty);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.showValidationError, isFalse);
  });

  test('reset() also clears whatever retry() would have resubmitted', () async {
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('headache');
    await notifier.submit();

    notifier.reset();
    final ok = await notifier.retry();

    expect(ok, isFalse, reason: 'reset must forget the last submitted symptom list too');
    expect(api.checkSymptomsCalls, hasLength(1));
  });

  test('an emergency triage_level result is surfaced through state.result as-is', () async {
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result(triageLevel: TriageLevel.emergency));
    final container = _container(api);
    addTearDown(container.dispose);
    final notifier = container.read(symptomCheckerControllerProvider.notifier);
    notifier.updateInput('severe chest pain');

    await notifier.submit();

    expect(
      container.read(symptomCheckerControllerProvider).result?.triageLevel,
      TriageLevel.emergency,
    );
  });

  test('symptom text and results are never printed', () async {
    final api = _FakeSymptomCheckerApi()..checkSymptomsResults.add(_result());
    final printed = <String>[];

    await runZoned(
      () async {
        final container = _container(api);
        addTearDown(container.dispose);
        final notifier = container.read(symptomCheckerControllerProvider.notifier);
        notifier.updateInput('a very private symptom description');
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

ProviderContainer _container(SymptomCheckerApi api) {
  final container = ProviderContainer(
    overrides: [symptomCheckerApiProvider.overrideWithValue(api)],
  );
  // `symptomCheckerControllerProvider` is `autoDispose` — keep it alive across
  // `await` boundaries the same way every other autoDispose provider test does.
  container.listen(symptomCheckerControllerProvider, (previous, next) {});
  return container;
}

class _FakeSymptomCheckerApi extends SymptomCheckerApi {
  _FakeSymptomCheckerApi() : super(Dio());

  final checkSymptomsResults = <Object>[];
  final checkSymptomsCalls = <List<String>>[];

  @override
  Future<SymptomCheckResult> checkSymptoms(List<String> symptoms) {
    checkSymptomsCalls.add(symptoms);
    final next = checkSymptomsResults.removeAt(0);
    if (next is Future<SymptomCheckResult>) return next;
    if (next is SymptomCheckResult) return Future.value(next);
    return Future.error(next);
  }
}
