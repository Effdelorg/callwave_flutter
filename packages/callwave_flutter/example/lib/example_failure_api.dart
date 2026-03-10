import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum ExampleFailureApiFlow {
  validatedAllow('validated_allow'),
  validatedReject('validated_reject'),
  declineFailed('decline_failed');

  const ExampleFailureApiFlow(this.wireValue);

  final String wireValue;
}

abstract final class ExampleFailureApiExtraKeys {
  static const String endpoint = 'exampleFailureApiEndpoint';
  static const String flow = 'exampleFailureApiFlow';
  static const String reason = 'exampleFailureApiReason';
  static const String statusCode = 'exampleFailureApiStatusCode';
  static const String error = 'exampleFailureApiError';
  static const String bodyPreview = 'exampleFailureApiBodyPreview';
}

typedef ExampleFailureApiLogSink = void Function(String message);
typedef ExampleFailureApiHttpClientFactory = HttpClient Function();

class ExampleFailureApiResult {
  const ExampleFailureApiResult({
    required this.flow,
    required this.reason,
    required this.endpoint,
    this.statusCode,
    this.error,
    this.bodyPreview,
  });

  final ExampleFailureApiFlow flow;
  final String reason;
  final Uri endpoint;
  final int? statusCode;
  final String? error;
  final String? bodyPreview;

  bool get isSuccessful {
    final code = statusCode;
    return code != null && code >= 200 && code < 300;
  }

  Map<String, dynamic> toExtra() {
    return <String, dynamic>{
      ExampleFailureApiExtraKeys.endpoint: endpoint.toString(),
      ExampleFailureApiExtraKeys.flow: flow.wireValue,
      ExampleFailureApiExtraKeys.reason: reason,
      if (statusCode != null) ExampleFailureApiExtraKeys.statusCode: statusCode,
      if (error != null) ExampleFailureApiExtraKeys.error: error,
      if (bodyPreview != null && bodyPreview!.isNotEmpty)
        ExampleFailureApiExtraKeys.bodyPreview: bodyPreview,
    };
  }
}

/// Simulates backend responses for the example app's validated/decline demos.
/// Uses DummyJSON (https://dummyjson.com/) for delayed success and HTTP 400
/// responses.
abstract final class ExampleFailureApi {
  /// DummyJSON endpoint that returns HTTP 400. See https://dummyjson.com/
  static const String failingEndpoint =
      'https://dummyjson.com/http/400/Bad_Request_Test';
  static const String delayedValidatedAllowEndpoint =
      'https://dummyjson.com/test/?delay=1000';
  static const Duration requestTimeout = Duration(seconds: 8);

  @visibleForTesting
  static Future<ExampleFailureApiResult> Function({
    required ExampleFailureApiFlow flow,
    required String callId,
    required String reason,
  })? callOverride;
  static ExampleFailureApiHttpClientFactory httpClientFactory =
      _defaultHttpClientFactory;
  static ExampleFailureApiLogSink logSink = _defaultLogSink;

  static Future<ExampleFailureApiResult> call({
    required ExampleFailureApiFlow flow,
    required String callId,
    required String reason,
  }) async {
    final override = callOverride;
    if (override != null) {
      return override(
        flow: flow,
        callId: callId,
        reason: reason,
      );
    }
    final uri = Uri.parse(_endpointForFlow(flow));
    _log(
      'request flow=${flow.wireValue} callId=$callId '
      'reason="$reason" url=$uri',
    );

    HttpClient? client;
    try {
      client = httpClientFactory();
      final request = await client.getUrl(uri).timeout(requestTimeout);
      final response = await request.close().timeout(requestTimeout);
      final body = await utf8.decoder.bind(response).join().timeout(
            requestTimeout,
          );
      final bodyPreview = _bodyPreview(body);
      _log(
        'response flow=${flow.wireValue} callId=$callId '
        'reason="$reason" status=${response.statusCode}'
        '${bodyPreview.isEmpty ? "" : ' body="$bodyPreview"'}',
      );
      return ExampleFailureApiResult(
        flow: flow,
        reason: reason,
        endpoint: uri,
        statusCode: response.statusCode,
        bodyPreview: bodyPreview.isEmpty ? null : bodyPreview,
      );
    } on TimeoutException {
      _log(
        'error flow=${flow.wireValue} callId=$callId '
        'reason="$reason" error=timeout',
      );
      return ExampleFailureApiResult(
        flow: flow,
        reason: reason,
        endpoint: uri,
        error: 'timeout',
      );
    } catch (error) {
      _log(
        'error flow=${flow.wireValue} callId=$callId '
        'reason="$reason" error=$error',
      );
      return ExampleFailureApiResult(
        flow: flow,
        reason: reason,
        endpoint: uri,
        error: error.toString(),
      );
    } finally {
      client?.close(force: true);
    }
  }

  @visibleForTesting
  static void resetForTesting() {
    callOverride = null;
    httpClientFactory = _defaultHttpClientFactory;
    logSink = _defaultLogSink;
  }

  static void _log(String message) {
    logSink('CallwaveExampleApi $message');
  }

  static String _bodyPreview(String body) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}...';
  }

  static String _endpointForFlow(ExampleFailureApiFlow flow) {
    switch (flow) {
      case ExampleFailureApiFlow.validatedAllow:
        return delayedValidatedAllowEndpoint;
      case ExampleFailureApiFlow.validatedReject:
      case ExampleFailureApiFlow.declineFailed:
        return failingEndpoint;
    }
  }
}

HttpClient _defaultHttpClientFactory() => HttpClient();

void _defaultLogSink(String message) {
  debugPrint(message);
}
