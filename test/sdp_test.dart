import 'package:flutter_test/flutter_test.dart';
import 'package:opview/system/webrtc/webrtc_client.dart';

void main() {
  group('preferH264', () {
    test('reorders H264 before VP8 in m=video line', () {
      final sdp = [
        'v=0',
        'o=- 0 0 IN IP4 0.0.0.0',
        's=-',
        't=0 0',
        'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 H264/90000',
        'a=fmtp:97 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f',
        'a=rtpmap:98 rtx/90000',
        'a=fmtp:98 apt=97',
        '',
      ].join('\r\n');

      final result = preferH264(sdp);
      final mLine = result.split('\r\n').firstWhere((l) => l.startsWith('m=video'));
      final payloads = mLine.split(' ').sublist(3);

      // H264 (97) and its RTX (98) should come before VP8 (96)
      expect(payloads.indexOf('97'), lessThan(payloads.indexOf('96')));
      expect(payloads.indexOf('98'), lessThan(payloads.indexOf('96')));
    });

    test('no change when no m=video line', () {
      const sdp = 'v=0\r\no=- 0 0 IN IP4 0.0.0.0\r\ns=-\r\n';
      expect(preferH264(sdp), sdp);
    });

    test('no change when no H264 codec', () {
      final sdp = [
        'v=0',
        'm=video 9 UDP/TLS/RTP/SAVPF 96',
        'a=rtpmap:96 VP8/90000',
        '',
      ].join('\r\n');
      expect(preferH264(sdp), sdp);
    });

    test('handles multiple H264 profiles', () {
      final sdp = [
        'v=0',
        'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 H264/90000',
        'a=fmtp:97 profile-level-id=42e01f',
        'a=rtpmap:98 H264/90000',
        'a=fmtp:98 profile-level-id=640032',
        'a=rtpmap:99 VP9/90000',
        '',
      ].join('\r\n');

      final result = preferH264(sdp);
      final mLine = result.split('\r\n').firstWhere((l) => l.startsWith('m=video'));
      final payloads = mLine.split(' ').sublist(3);

      // both H264 payloads before VP8 and VP9
      expect(payloads.indexOf('97'), lessThan(payloads.indexOf('96')));
      expect(payloads.indexOf('98'), lessThan(payloads.indexOf('96')));
      expect(payloads.indexOf('97'), lessThan(payloads.indexOf('99')));
    });

    test('preserves all payload types', () {
      final sdp = [
        'v=0',
        'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 H264/90000',
        'a=rtpmap:98 VP9/90000',
        '',
      ].join('\r\n');

      final result = preferH264(sdp);
      final mLine = result.split('\r\n').firstWhere((l) => l.startsWith('m=video'));
      final payloads = mLine.split(' ').sublist(3).toSet();

      expect(payloads, containsAll(['96', '97', '98']));
    });

    test('H264 already first remains unchanged', () {
      final sdp = [
        'v=0',
        'm=video 9 UDP/TLS/RTP/SAVPF 97 96',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 H264/90000',
        '',
      ].join('\r\n');

      final result = preferH264(sdp);
      final mLine = result.split('\r\n').firstWhere((l) => l.startsWith('m=video'));
      final payloads = mLine.split(' ').sublist(3);

      expect(payloads[0], '97'); // H264 stays first
    });

    test('RTX payload for non-H264 not moved', () {
      final sdp = [
        'v=0',
        'm=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99',
        'a=rtpmap:96 VP8/90000',
        'a=rtpmap:97 rtx/90000',
        'a=fmtp:97 apt=96',
        'a=rtpmap:98 H264/90000',
        'a=rtpmap:99 rtx/90000',
        'a=fmtp:99 apt=98',
        '',
      ].join('\r\n');

      final result = preferH264(sdp);
      final mLine = result.split('\r\n').firstWhere((l) => l.startsWith('m=video'));
      final payloads = mLine.split(' ').sublist(3);

      // H264 (98) and its RTX (99) come first
      expect(payloads.indexOf('98'), lessThan(payloads.indexOf('96')));
      expect(payloads.indexOf('99'), lessThan(payloads.indexOf('96')));
      // VP8's RTX (97) stays with VP8
      expect(payloads.indexOf('97'), greaterThan(payloads.indexOf('99')));
    });
  });
}
