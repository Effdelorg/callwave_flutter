import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:callwave_flutter/callwave_flutter.dart';
import 'package:callwave_flutter_example/example_failure_api.dart';
import 'package:callwave_flutter_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() async {
    loadPersistedIncomingDemoModeOverride = null;
    ExampleFailureApi.resetForTesting();
    await clearPersistedIncomingDemoMode();
  });

  test('failure API logs request and 400 response details', () async {
    final logs = <String>[];
    ExampleFailureApi.logSink = logs.add;
    ExampleFailureApi.httpClientFactory = () => _FakeHttpClient(
          statusCode: HttpStatus.badRequest,
          body: '{"message":"Bad Request Test"}',
        );

    final result = await ExampleFailureApi.call(
      flow: ExampleFailureApiFlow.validatedReject,
      callId: 'demo-call-001',
      reason: 'simulate rejected accept via failing backend',
    );

    expect(result.statusCode, HttpStatus.badRequest);
    expect(result.isSuccessful, isFalse);
    expect(
      result.toExtra()[ExampleFailureApiExtraKeys.statusCode],
      HttpStatus.badRequest,
    );
    expect(logs, hasLength(2));
    expect(logs.first, contains('CallwaveExampleApi request'));
    expect(logs.first, contains('flow=validated_reject'));
    expect(logs.last, contains('status=400'));
    expect(logs.last, contains('Bad Request Test'));
  });

  test('failure API logs thrown client errors', () async {
    final logs = <String>[];
    ExampleFailureApi.logSink = logs.add;
    ExampleFailureApi.httpClientFactory = () => _ThrowingHttpClient();

    final result = await ExampleFailureApi.call(
      flow: ExampleFailureApiFlow.declineFailed,
      callId: 'demo-call-002',
      reason: 'simulate failed decline report via failing backend',
    );

    expect(result.statusCode, isNull);
    expect(result.error, contains('fake client failure'));
    expect(logs, hasLength(2));
    expect(logs.first, contains('flow=decline_failed'));
    expect(logs.last, contains('fake client failure'));
  });

  test('validated allow uses delayed backend approval and returns allow',
      () async {
    var callCount = 0;
    ExampleFailureApi.callOverride = ({
      required ExampleFailureApiFlow flow,
      required String callId,
      required String reason,
    }) async {
      callCount += 1;
      return ExampleFailureApiResult(
        flow: flow,
        reason: reason,
        endpoint: Uri.parse(ExampleFailureApi.delayedValidatedAllowEndpoint),
        statusCode: HttpStatus.ok,
        bodyPreview: '{"status":"ok"}',
      );
    };
    loadPersistedIncomingDemoModeOverride =
        () async => IncomingDemoMode.validatedAllow;

    final decision = await exampleBackgroundIncomingCallValidator(
      const BackgroundIncomingCallValidationRequest(
        callId: 'demo-call-allow',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.audio,
      ),
    );

    expect(decision.isAllowed, isTrue);
    expect(callCount, 1);
    expect(
      decision.extra?[ExampleFailureApiExtraKeys.endpoint],
      ExampleFailureApi.delayedValidatedAllowEndpoint,
    );
  });

  test('validated reject maps failing API result to failed reject', () async {
    ExampleFailureApi.callOverride = ({
      required ExampleFailureApiFlow flow,
      required String callId,
      required String reason,
    }) async {
      return ExampleFailureApiResult(
        flow: flow,
        reason: reason,
        endpoint: Uri.parse(ExampleFailureApi.failingEndpoint),
        statusCode: HttpStatus.badRequest,
        bodyPreview: 'Bad Request Test',
      );
    };
    loadPersistedIncomingDemoModeOverride =
        () async => IncomingDemoMode.validatedReject;

    final decision = await exampleBackgroundIncomingCallValidator(
      const BackgroundIncomingCallValidationRequest(
        callId: 'demo-call-reject',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.audio,
      ),
    );

    expect(decision.isAllowed, isFalse);
    expect(decision.reason, CallAcceptRejectReason.failed);
    expect(
      decision.extra?[ExampleFailureApiExtraKeys.statusCode],
      HttpStatus.badRequest,
    );
  });

  test('decline failed maps failing API result to failed decline decision',
      () async {
    ExampleFailureApi.callOverride = ({
      required ExampleFailureApiFlow flow,
      required String callId,
      required String reason,
    }) async {
      return ExampleFailureApiResult(
        flow: flow,
        reason: reason,
        endpoint: Uri.parse(ExampleFailureApi.failingEndpoint),
        statusCode: HttpStatus.badRequest,
        bodyPreview: 'Bad Request Test',
      );
    };
    loadPersistedIncomingDemoModeOverride =
        () async => IncomingDemoMode.declineFailed;

    final decision = await exampleBackgroundIncomingCallDeclineValidator(
      const BackgroundIncomingCallValidationRequest(
        callId: 'demo-call-decline',
        callerName: 'Ava',
        handle: '+1 555 0101',
        callType: CallType.audio,
      ),
    );

    expect(decision.isReported, isFalse);
    expect(decision.reason, CallDeclineFailureReason.failed);
    expect(
      decision.extra?[ExampleFailureApiExtraKeys.statusCode],
      HttpStatus.badRequest,
    );
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest(
      response: _FakeHttpClientResponse(
        statusCode: statusCode,
        body: body,
      ),
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    throw const HttpException('fake client failure');
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({
    required HttpClientResponse response,
  }) : _response = response;

  final HttpClientResponse _response;

  @override
  Future<HttpClientResponse> close() async => _response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({
    required this.statusCode,
    required String body,
  }) : _bytes = utf8.encode(body);

  final List<int> _bytes;

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(<List<int>>[_bytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
