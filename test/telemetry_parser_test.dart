import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:opview/services/telemetry_parser.dart';

void main() {
  late TelemetryParser parser;

  setUp(() {
    parser = TelemetryParser();
  });

  group('single message', () {
    test('complete JSON produces one message', () {
      final json = jsonEncode({'type': 'carState', 'data': {'vEgo': 10.0}});
      final msgs = parser.parse(json);
      expect(msgs.length, 1);
      expect(msgs[0].type, 'carState');
      expect((msgs[0].data as Map)['vEgo'], 10.0);
    });

    test('empty string produces no messages', () {
      expect(parser.parse(''), isEmpty);
    });
  });

  group('}{ splitting', () {
    test('two concatenated JSON objects produce two messages', () {
      final a = jsonEncode({'type': 'carState', 'data': {}});
      final b = jsonEncode({'type': 'modelV2', 'data': {}});
      final msgs = parser.parse('$a$b');
      expect(msgs.length, 2);
      expect(msgs[0].type, 'carState');
      expect(msgs[1].type, 'modelV2');
    });

    test('three concatenated objects produce three messages', () {
      final a = jsonEncode({'type': 'a', 'data': {}});
      final b = jsonEncode({'type': 'b', 'data': {}});
      final c = jsonEncode({'type': 'c', 'data': {}});
      final msgs = parser.parse('$a$b$c');
      expect(msgs.length, 3);
      expect(msgs[0].type, 'a');
      expect(msgs[1].type, 'b');
      expect(msgs[2].type, 'c');
    });
  });

  group('NaN sanitization', () {
    test('NaN in value is replaced with null', () {
      final raw = '{"type":"carState","data":{"vEgo":NaN}}';
      final msgs = parser.parse(raw);
      expect(msgs.length, 1);
      expect((msgs[0].data as Map)['vEgo'], isNull);
    });

    test('multiple NaN values are all replaced', () {
      final raw = '{"type":"t","data":{"a":NaN,"b":NaN,"c":1.5}}';
      final msgs = parser.parse(raw);
      expect(msgs.length, 1);
      final data = msgs[0].data as Map;
      expect(data['a'], isNull);
      expect(data['b'], isNull);
      expect(data['c'], 1.5);
    });

    test('NaN as substring is not replaced (word boundary)', () {
      final raw = '{"type":"t","data":{"name":"NaNothing"}}';
      final msgs = parser.parse(raw);
      expect(msgs.length, 1);
      expect((msgs[0].data as Map)['name'], 'NaNothing');
    });

    test('NaN in array is replaced', () {
      final raw = '{"type":"t","data":{"arr":[1.0,NaN,3.0]}}';
      final msgs = parser.parse(raw);
      expect(msgs.length, 1);
      final arr = (msgs[0].data as Map)['arr'] as List;
      expect(arr[0], 1.0);
      expect(arr[1], isNull);
      expect(arr[2], 3.0);
    });
  });

  group('buffering', () {
    test('partial message buffered until complete', () {
      final full = jsonEncode({'type': 'carState', 'data': {}});
      final half1 = full.substring(0, full.length ~/ 2);
      final half2 = full.substring(full.length ~/ 2);

      expect(parser.parse(half1), isEmpty);
      final msgs = parser.parse(half2);
      expect(msgs.length, 1);
      expect(msgs[0].type, 'carState');
    });

    test('partial first + complete second splits correctly', () {
      final a = jsonEncode({'type': 'first', 'data': {}});
      final b = jsonEncode({'type': 'second', 'data': {}});

      // send first part of a
      final halfA = a.substring(0, a.length ~/ 2);
      expect(parser.parse(halfA), isEmpty);

      // send rest of a + all of b
      final rest = a.substring(a.length ~/ 2) + b;
      final msgs = parser.parse(rest);
      expect(msgs.length, 2);
      expect(msgs[0].type, 'first');
      expect(msgs[1].type, 'second');
    });
  });

  group('error handling', () {
    test('malformed JSON is silently ignored', () {
      final msgs = parser.parse('{bad json}');
      expect(msgs, isEmpty);
    });

    test('valid message after malformed one is still parsed', () {
      final good = jsonEncode({'type': 'ok', 'data': {}});
      // send bad JSON followed by good
      final msgs = parser.parse('{bad}$good');
      // the bad part gets consumed by }{ split, the good part gets parsed
      expect(msgs.where((m) => m.type == 'ok').length, 1);
    });
  });

  group('reset', () {
    test('reset clears buffer', () {
      final full = jsonEncode({'type': 'test', 'data': {}});
      final half = full.substring(0, full.length ~/ 2);

      parser.parse(half);
      parser.reset();

      // remaining half should not produce a message
      final rest = full.substring(full.length ~/ 2);
      final msgs = parser.parse(rest);
      expect(msgs, isEmpty);
    });
  });

  group('CerealMessage defaults', () {
    test('missing type defaults to empty string', () {
      final raw = '{"data":{"x":1}}';
      final msgs = parser.parse(raw);
      expect(msgs.length, 1);
      expect(msgs[0].type, '');
    });
  });
}
