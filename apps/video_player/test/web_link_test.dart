import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_app/src/party/online.dart';

void main() {
  test('no web page yet: invite has only the code', () {
    expect(partyWebLink('K7QF2M', webUrl: ''), isNull);
    expect(partyInvite('Trip', 'K7QF2M', webUrl: ''),
        'Watch "Trip" with me in Video Player: open Watch together and enter code K7QF2M');
  });

  test('with the web page: the invite links straight into the room', () {
    const url = 'https://watch.example.com/';
    expect(partyWebLink('K7QF2M', webUrl: url), 'https://watch.example.com/#K7QF2M');
    expect(partyInvite('Trip', 'K7QF2M', webUrl: url),
        endsWith('enter code K7QF2M, or join in a browser: https://watch.example.com/#K7QF2M'));
  });
}
