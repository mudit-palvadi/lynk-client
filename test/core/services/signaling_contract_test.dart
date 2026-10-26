import 'dart:convert';
import 'dart:io';

import 'package:client/core/services/webrtc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = File('test/fixtures/signaling_contract.json');
  final contract =
      jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;

  group('Dart/browser signaling contract', () {
    test(
      'fixture matches the browser copy when both repos are checked out',
      () {
        final browser = File('../web/test/fixtures/signaling_contract.json');
        if (browser.existsSync()) {
          expect(fixture.readAsBytesSync(), browser.readAsBytesSync());
        }
        expect(contract['version'], 1);
      },
    );

    for (final vector in contract['cases'] as List<dynamic>) {
      final entry = vector as Map<String, dynamic>;
      test(entry['name'] as String, () {
        final raw = entry['raw'] as String;
        final expected = entry['expected'];
        final message = SignalingMessage.fromRaw(raw);
        expect(message.toJson(), expected);
        expect(jsonEncode(message.toJson()), jsonEncode(expected));

        dynamic input;
        try {
          input = jsonDecode(raw);
        } on FormatException {
          return;
        }
        if (input is! Map<String, dynamic>) return;

        // Direct JSON callers must have the same safe behavior as raw frames.
        expect(SignalingMessage.fromJson(input).toJson(), expected);

        final type = switch (input['type']) {
          'offer' => SignalingMessageType.offer,
          'answer' => SignalingMessageType.answer,
          'candidate' => SignalingMessageType.candidate,
          _ => null,
        };
        if (type == null) return;
        final sdp = input['sdp'];
        final candidate = input['candidate'];
        if (sdp != null && sdp is! String) return;
        if (candidate != null && candidate is! Map<String, dynamic>) return;
        final encoded = SignalingMessage(
          type: type,
          sdp: sdp as String?,
          candidate: candidate as Map<String, dynamic>?,
        ).toJson();
        expect(jsonEncode(encoded), jsonEncode(expected));
      });
    }
  });
}
