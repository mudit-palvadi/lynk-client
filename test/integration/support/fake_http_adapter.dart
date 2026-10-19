import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One HTTP request that reached the fake backend.
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.path,
    required this.uri,
    required this.queryParameters,
    required this.headers,
    required this.body,
    required this.rawBody,
  });

  final String method;

  /// The path as it was requested, after the ApiClient interceptor ran.
  final String path;

  final Uri uri;
  final Map<String, dynamic> queryParameters;
  final Map<String, dynamic> headers;

  /// The request body decoded as JSON, or null when there was none.
  final Object? body;

  /// The raw request body as text.
  final String? rawBody;

  @override
  String toString() => '$method $path';
}

/// A Dio [HttpClientAdapter] that answers from a handler instead of the
/// network.
///
/// The real [ApiClient] still sits in front of this (with its base url and its
/// leading-slash interceptor), so a test using it exercises the client's own
/// request building rather than a hand-written request.
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  /// Produces the response for a request.
  final FutureOr<ResponseBody> Function(RecordedRequest request) handler;

  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Every request whose path contains [fragment], in order.
  Iterable<RecordedRequest> requestsTo(String fragment) =>
      requests.where((request) => request.path.contains(fragment));

  /// The paths of every request, in order. Handy for asserting call order.
  List<String> get paths =>
      requests.map((request) => '${request.method} ${request.path}').toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = await _readBody(requestStream);
    final request = RecordedRequest(
      method: options.method,
      path: options.path,
      uri: options.uri,
      queryParameters: Map<String, dynamic>.from(options.queryParameters),
      headers: Map<String, dynamic>.from(options.headers),
      body: _decode(raw) ?? options.data,
      rawBody: raw,
    );
    requests.add(request);
    return handler(request);
  }

  static Future<String?> _readBody(Stream<Uint8List>? stream) async {
    if (stream == null) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    if (builder.isEmpty) return null;
    return utf8.decode(builder.takeBytes());
  }

  static Object? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  void close({bool force = false}) {}
}

/// Builds a JSON response body the way a real server would.
ResponseBody jsonResponse(int statusCode, Object? payload) =>
    ResponseBody.fromString(
      payload == null ? '' : jsonEncode(payload),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
