// telemetry parser — NaN sanitize + }{ split + JSON dispatch
// ported from dashy web/src/js/core/webrtc.js data channel handling
//
// webrtcd sends concatenated JSON objects on the data channel.
// they arrive as: {"type":"carState",...}{"type":"modelV2",...}
// also: capnp floats can be NaN, which isn't valid JSON.

import 'dart:convert';
import 'package:scope/data/models.dart';

// pre-compiled regex for NaN replacement (webrtc.js:22)
final _nanRegex = RegExp(r'\bNaN\b');

class TelemetryParser {
  String _buffer = '';

  /// feed raw data channel text, returns parsed messages
  List<CerealMessage> parse(String chunk) {
    _buffer += chunk;
    final messages = <CerealMessage>[];

    // split on }{ boundaries (webrtc.js:242-253)
    int boundary;
    while ((boundary = _buffer.indexOf('}{')) != -1) {
      final jsonString = _buffer.substring(0, boundary + 1);
      _tryParse(jsonString, messages);
      _buffer = _buffer.substring(boundary + 1);
    }

    // try remaining buffer if it looks complete
    if (_buffer.isNotEmpty && _buffer.trimRight().endsWith('}')) {
      _tryParse(_buffer, messages);
      _buffer = '';
    }

    return messages;
  }

  /// sanitize NaN, parse JSON, build CerealMessage
  void _tryParse(String raw, List<CerealMessage> out) {
    try {
      final sanitized = raw.contains('NaN') ? raw.replaceAll(_nanRegex, 'null') : raw;
      final json = jsonDecode(sanitized) as Map<String, dynamic>;
      out.add(CerealMessage.fromJson(json));
    } catch (_) {
      // ignore parse errors — partial messages, malformed JSON
    }
  }

  void reset() {
    _buffer = '';
  }
}
