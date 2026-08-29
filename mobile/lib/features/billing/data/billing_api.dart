import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/billing_models.dart';

class BillingApi {
  BillingApi(this._dio);

  final Dio _dio;

  Future<BillingEntitlements> getEntitlements() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/billing/entitlements',
    );
    return _parse(response.data, BillingEntitlements.fromJson);
  }

  Future<List<BillingPlan>> getPlans() async {
    final response = await _dio.get<Map<String, dynamic>>('/billing/plans');
    final data = _data(response.data);
    final rawPlans = data['plans'];
    if (rawPlans is! List) throw _invalidResponse();
    try {
      return rawPlans
          .map((value) {
            if (value is! Map) throw const BillingModelException('plans');
            return BillingPlan.fromJson(Map<String, dynamic>.from(value));
          })
          .toList(growable: false);
    } on BillingModelException {
      throw _invalidResponse();
    }
  }

  Future<BillingConfig> getConfig() async {
    final response = await _dio.get<Map<String, dynamic>>('/billing/config');
    return _parse(response.data, BillingConfig.fromJson);
  }

  Future<Uri> createCheckout(String planCode) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/checkout',
      data: {'plan_code': planCode},
    );
    final data = _data(response.data);
    final rawUrl = data['checkout_url'];
    final uri = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    final isHosted =
        uri != null && uri.isAbsolute && {'http', 'https'}.contains(uri.scheme);
    final isBackendSandboxPath =
        uri != null &&
        !uri.isAbsolute &&
        uri.path == '/billing-sandbox.html' &&
        uri.queryParameters['session']?.isNotEmpty == true;
    if (!isHosted && !isBackendSandboxPath) {
      throw _invalidResponse();
    }
    return uri;
  }

  Future<SubscriptionDetail> getSubscription() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/billing/subscription',
    );
    return _parse(response.data, SubscriptionDetail.fromJson);
  }

  Future<SubscriptionDetail> cancelSubscription() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/subscription/cancel',
    );
    return _parse(response.data, SubscriptionDetail.fromJson);
  }

  Future<SubscriptionDetail> resumeSubscription() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/subscription/resume',
    );
    return _parse(response.data, SubscriptionDetail.fromJson);
  }

  Future<SubscriptionDetail> changePlan(String planCode) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/subscription/plan',
      data: {'plan_code': planCode},
    );
    return _parse(response.data, SubscriptionDetail.fromJson);
  }

  Future<List<BillingHistoryEvent>> getHistory({int limit = 50}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/billing/history',
      queryParameters: {'limit': limit},
    );
    final data = _data(response.data);
    final rawEvents = data['events'];
    if (rawEvents is! List) throw _invalidResponse();
    try {
      return rawEvents
          .map((value) {
            if (value is! Map) throw const BillingModelException('events');
            return BillingHistoryEvent.fromJson(
              Map<String, dynamic>.from(value),
            );
          })
          .toList(growable: false);
    } on BillingModelException {
      throw _invalidResponse();
    }
  }

  Future<SandboxCheckout> getSandboxCheckout(String token) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/billing/sandbox/checkout/${Uri.encodeComponent(token)}',
    );
    return _parse(response.data, SandboxCheckout.fromJson);
  }

  Future<SandboxCheckoutResult> completeSandboxCheckout(
    String token,
    String outcome,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/sandbox/checkout/${Uri.encodeComponent(token)}/complete',
      data: {'outcome': outcome},
    );
    return _parse(response.data, SandboxCheckoutResult.fromJson);
  }

  Future<SubscriptionDetail> simulateSandboxLifecycle(String kind) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/billing/sandbox/simulate',
      data: {'kind': kind},
    );
    return _parse(response.data, SubscriptionDetail.fromJson);
  }

  T _parse<T>(
    Map<String, dynamic>? envelope,
    T Function(Map<String, dynamic>) parser,
  ) {
    try {
      return parser(_data(envelope));
    } on BillingModelException {
      throw _invalidResponse();
    } on TypeError {
      throw _invalidResponse();
    }
  }

  Map<String, dynamic> _data(Map<String, dynamic>? envelope) {
    if (envelope == null) throw _invalidResponse();
    if (envelope['success'] == false) {
      final rawError = envelope['error'];
      if (rawError is Map) {
        final error = Map<String, dynamic>.from(rawError);
        throw ApiException(
          message: error['message'] is String
              ? error['message'] as String
              : 'Request failed.',
          code: error['code'] is String
              ? error['code'] as String
              : ApiException.codeUnknown,
          details: error['details'],
        );
      }
      throw _invalidResponse();
    }
    if (envelope['success'] != true) throw _invalidResponse();
    final data = envelope['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw _invalidResponse();
  }

  ApiException _invalidResponse() => const ApiException(
    message: 'Unexpected response from server.',
    code: 'INVALID_RESPONSE',
  );
}
