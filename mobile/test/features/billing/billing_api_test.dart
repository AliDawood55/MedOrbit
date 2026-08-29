import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/billing/data/billing_api.dart';

import 'billing_test_fixtures.dart';

void main() {
  group('BillingApi reads authoritative snapshots', () {
    test(
      'entitlements parses server plan, quota, cooldown, and server time',
      () async {
        final harness = _DioHarness([_ok(entitlementJson())]);

        final value = await BillingApi(harness.dio).getEntitlements();

        expect(harness.requests.single.path, '/billing/entitlements');
        expect(value.plan, 'free');
        expect(value.chatbot.remaining, 5);
        expect(
          value.voiceDoctor.nextFreeAt,
          DateTime.parse('2026-08-30T10:00:00Z'),
        );
        expect(value.serverTime, serverNow);
      },
    );

    test('plans preserve localized names and server price fields', () async {
      final harness = _DioHarness([
        _ok({
          'plans': [planJson()],
        }),
      ]);

      final plans = await BillingApi(harness.dio).getPlans();

      expect(harness.requests.single.path, '/billing/plans');
      expect(plans.single.nameAr, 'أوربت برو الشهري');
      expect(plans.single.priceCents, 2345);
      expect(plans.single.currency, 'USD');
    });

    test('config is fail-closed and only accepts explicit booleans', () async {
      final harness = _DioHarness([
        _ok({'checkout_available': true, 'sandbox': false}),
        _ok({'checkout_available': 'yes', 'sandbox': false}),
      ]);
      final api = BillingApi(harness.dio);

      final config = await api.getConfig();
      expect(config.checkoutAvailable, isTrue);
      expect(config.sandbox, isFalse);
      await expectLater(
        api.getConfig(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });
  });

  group('BillingApi request contracts', () {
    test(
      'checkout sends only plan_code and accepts an absolute hosted URL',
      () async {
        final harness = _DioHarness([
          _ok({'checkout_url': 'https://payments.example.test/session/abc'}),
        ]);

        final url = await BillingApi(harness.dio).createCheckout('pro_monthly');

        expect(url.host, 'payments.example.test');
        expect(harness.requests.single.method, 'POST');
        expect(harness.requests.single.path, '/billing/checkout');
        expect(harness.requests.single.data, {'plan_code': 'pro_monthly'});
        expect(
          (harness.requests.single.data as Map).keys,
          isNot(contains('price_cents')),
        );
        expect(
          (harness.requests.single.data as Map).keys,
          isNot(contains('currency')),
        );
        expect(
          (harness.requests.single.data as Map).keys,
          isNot(contains('is_pro')),
        );
      },
    );

    test(
      'checkout rejects relative, custom-scheme, and malformed URLs',
      () async {
        final harness = _DioHarness([
          _ok({'checkout_url': '/billing/fake'}),
          _ok({'checkout_url': 'medorbit://paid'}),
          _ok({'checkout_url': 42}),
        ]);
        final api = BillingApi(harness.dio);

        for (var i = 0; i < 3; i++) {
          await expectLater(
            api.createCheckout('pro_monthly'),
            throwsA(
              isA<ApiException>().having(
                (e) => e.code,
                'code',
                'INVALID_RESPONSE',
              ),
            ),
          );
        }
      },
    );

    test(
      'checkout accepts only the backend exact relative sandbox page shape',
      () async {
        final harness = _DioHarness([
          _ok({'checkout_url': '/billing-sandbox.html?session=cs_mock_abc'}),
          _ok({'checkout_url': '/billing-sandbox.html'}),
        ]);
        final api = BillingApi(harness.dio);

        final uri = await api.createCheckout('pro_monthly');
        expect(uri.path, '/billing-sandbox.html');
        expect(uri.queryParameters['session'], 'cs_mock_abc');
        await expectLater(api.createCheckout('pro_monthly'), _invalidResponse);
      },
    );

    test(
      'subscription read and lifecycle methods use exact authenticated paths',
      () async {
        final live = subscriptionJson(
          planCode: 'pro_monthly',
          status: 'active',
        );
        final harness = _DioHarness([_ok(live), _ok(live), _ok(live)]);
        final api = BillingApi(harness.dio);

        await api.getSubscription();
        await api.cancelSubscription();
        await api.resumeSubscription();

        expect(harness.requests.map((r) => '${r.method} ${r.path}'), [
          'GET /billing/subscription',
          'POST /billing/subscription/cancel',
          'POST /billing/subscription/resume',
        ]);
        expect(harness.requests[1].data, isNull);
        expect(harness.requests[2].data, isNull);
      },
    );

    test('plan change sends only the server plan code', () async {
      final harness = _DioHarness([
        _ok(subscriptionJson(planCode: 'pro_annual', status: 'active')),
      ]);

      await BillingApi(harness.dio).changePlan('pro_annual');

      expect(harness.requests.single.path, '/billing/subscription/plan');
      expect(harness.requests.single.data, {'plan_code': 'pro_annual'});
      expect((harness.requests.single.data as Map).length, 1);
    });

    test('history sends the bounded display limit and parses events', () async {
      final harness = _DioHarness([
        _ok({
          'events': [
            {
              'event_type': 'subscription_started',
              'occurred_at': '2026-08-29T10:00:00Z',
            },
          ],
        }),
      ]);

      final history = await BillingApi(harness.dio).getHistory(limit: 25);

      expect(harness.requests.single.path, '/billing/history');
      expect(harness.requests.single.query, {'limit': 25});
      expect(history.single.eventType, 'subscription_started');
    });
  });

  group('BillingApi sandbox fencing', () {
    test(
      'sandbox checkout and every supported outcome use token-scoped endpoints',
      () async {
        final checkout = {
          ...planJson(),
          'status': 'open',
          'is_open': true,
          'expires_at': '2026-08-29T11:00:00Z',
          'return_path': '/billing',
          'server_time': serverNow.toIso8601String(),
          'sandbox': true,
        };
        final harness = _DioHarness([
          _ok(checkout),
          for (final outcome in ['success', 'failure', 'canceled'])
            _ok({
              'outcome': outcome,
              'return_path': '/billing',
              'entitlements': entitlementJson(pro: outcome == 'success'),
            }),
        ]);
        final api = BillingApi(harness.dio);

        final loaded = await api.getSandboxCheckout('a token');
        final completed = <String>[];
        for (final outcome in ['success', 'failure', 'canceled']) {
          completed.add(
            (await api.completeSandboxCheckout('a token', outcome)).outcome,
          );
        }

        expect(loaded.sandbox, isTrue);
        expect(completed, ['success', 'failure', 'canceled']);
        expect(harness.requests[0].path, '/billing/sandbox/checkout/a%20token');
        for (var index = 0; index < completed.length; index++) {
          expect(
            harness.requests[index + 1].path,
            '/billing/sandbox/checkout/a%20token/complete',
          );
          expect(harness.requests[index + 1].data, {
            'outcome': completed[index],
          });
        }
      },
    );

    test('sandbox lifecycle sends only the supported lifecycle kind', () async {
      final harness = _DioHarness([
        _ok(subscriptionJson(planCode: 'pro_monthly', status: 'past_due')),
      ]);

      await BillingApi(harness.dio).simulateSandboxLifecycle('renewal_failure');

      expect(harness.requests.single.path, '/billing/sandbox/simulate');
      expect(harness.requests.single.data, {'kind': 'renewal_failure'});
    });
  });

  test(
    'structured backend error preserves code/details without trusting the message',
    () async {
      final harness = _DioHarness([
        {
          'success': false,
          'error': {
            'code': 'CHECKOUT_NOT_OPEN',
            'message': 'provider prose',
            'details': {'status': 'expired'},
          },
        },
      ]);

      await expectLater(
        BillingApi(harness.dio).createCheckout('pro_monthly'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'CHECKOUT_NOT_OPEN')
              .having((e) => e.details, 'details', {'status': 'expired'}),
        ),
      );
    },
  );

  test(
    'malformed envelopes and list elements become INVALID_RESPONSE',
    () async {
      final harness = _DioHarness([
        {'data': entitlementJson()},
        _ok({
          'plans': ['not-a-map'],
        }),
        _ok({'events': 'not-a-list'}),
      ]);
      final api = BillingApi(harness.dio);

      await expectLater(api.getEntitlements(), _invalidResponse);
      await expectLater(api.getPlans(), _invalidResponse);
      await expectLater(api.getHistory(), _invalidResponse);
    },
  );
}

final _invalidResponse = throwsA(
  isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
);

Map<String, dynamic> _ok(Map<String, dynamic> data) => {
  'success': true,
  'data': data,
};

class _DioHarness {
  _DioHarness(List<Map<String, dynamic>> responses)
    : dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(
            _Request(
              method: options.method,
              path: options.path,
              data: options.data,
              query: Map<String, dynamic>.from(options.queryParameters),
            ),
          );
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: responses.removeAt(0),
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_Request>[];
}

class _Request {
  const _Request({
    required this.method,
    required this.path,
    required this.data,
    required this.query,
  });

  final String method;
  final String path;
  final Object? data;
  final Map<String, dynamic> query;
}
