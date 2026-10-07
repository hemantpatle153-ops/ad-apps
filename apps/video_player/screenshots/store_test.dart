// Play Store screenshots. Run: flutter test screenshots/store_test.dart --update-goldens
//
// The player shot needs libmpv (apt install libmpv2) and ffmpeg on the
// machine: a real file plays so the seek bar and times are real. The test
// can't draw video textures, so a painted frame is drawn under the app and
// the player's black backgrounds are cleared to let it show through.
// Other platform plugins (photo_manager, media_kit_video's surface) are
// answered by channel mocks below.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_app/src/app.dart';
import 'package:video_player_app/src/library/video_library.dart';
import 'package:video_player_app/src/party/online.dart';
import 'package:video_player_app/src/party/party.dart';
import 'package:video_player_app/src/party/protocol.dart';
import 'package:video_player_app/src/player/play_item.dart';
import 'package:video_player_app/src/player/player_screen.dart';
import 'package:video_player_app/src/screens/folder_screen.dart';
import 'package:video_player_app/src/screens/home_screen.dart';
import 'package:video_player_app/src/library/private_vault.dart';
import 'package:video_player_app/src/settings.dart';

import '../../../tool/screenshots/shot.dart';

// ---------------------------------------------------------------- thumbnails

/// A tiny PNG encoder so thumbnails can be painted without a GPU.
Uint8List encodePng(int w, int h, Uint8List rgba) {
  final raw = BytesBuilder();
  for (var y = 0; y < h; y++) {
    raw.addByte(0);
    raw.add(Uint8List.sublistView(rgba, y * w * 4, (y + 1) * w * 4));
  }
  final out = BytesBuilder();
  out.add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final body = [...type.codeUnits, ...data];
    out.add(body);
    final crc = ByteData(4)..setUint32(0, _crc32(body));
    out.add(crc.buffer.asUint8List());
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', ZLibCodec(level: 6).encode(raw.toBytes()));
  chunk('IEND', const []);
  return out.toBytes();
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Colour schemes for the painted scenes: sky top, sky bottom, sun,
/// far hills, near hills, water.
const _palettes = [
  [0xFF1B2A6B, 0xFFFF8A50, 0xFFFFE08A, 0xFF5B3A6E, 0xFF2B1B3D, 0xFF3A4E8C], // sunset
  [0xFF3A8DDE, 0xFFBFE6FF, 0xFFFFFFF0, 0xFF6FA36B, 0xFF2F6B3A, 0xFF2E86C1], // day
  [0xFF0B1026, 0xFF2B3A78, 0xFFF4F1D0, 0xFF1B2440, 0xFF0D1225, 0xFF1E2A5A], // night
  [0xFFFF6E7F, 0xFFFFD3A5, 0xFFFFF4D6, 0xFFB06AB3, 0xFF6A3D7A, 0xFFE58F9C], // pink dusk
  [0xFF7FB2D9, 0xFFE8F1F5, 0xFFFFFFFF, 0xFF9AA9B8, 0xFF5E6F80, 0xFF8FB8D0], // snow
  [0xFF14532D, 0xFF8BC34A, 0xFFFFF59D, 0xFF2E7D32, 0xFF1B5E20, 0xFF26A69A], // forest
  [0xFFE65100, 0xFFFFCC80, 0xFFFFF3E0, 0xFFBF6A2B, 0xFF7A3E12, 0xFFD08A4C], // desert
];

int _mix(int a, int b, double t) {
  int ch(int s) =>
      (((a >> s) & 0xFF) + (((b >> s) & 0xFF) - ((a >> s) & 0xFF)) * t).round();
  return 0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
}

/// Paints a landscape: gradient sky, sun or moon, two hill ranges and
/// sometimes water. [darken] adds a vignette at the top and bottom.
Uint8List paintScene(int seed, int w, int h, {bool vignette = false}) {
  final r = Random(seed);
  final p = _palettes[seed % _palettes.length];
  final px = Uint8List(w * h * 4);
  final sunX = w * (0.2 + r.nextDouble() * 0.6), sunY = h * (0.22 + r.nextDouble() * 0.18);
  final sunR = h * (0.07 + r.nextDouble() * 0.05);
  final water = r.nextBool();
  final horizon = h * (water ? 0.68 : 1.0);
  final ph = [r.nextDouble() * 6, r.nextDouble() * 6, r.nextDouble() * 6, r.nextDouble() * 6];
  double far(double x) =>
      h * 0.45 + sin(x / w * 5 + ph[0]) * h * 0.08 + sin(x / w * 13 + ph[1]) * h * 0.03;
  double near(double x) =>
      h * 0.6 + sin(x / w * 3 + ph[2]) * h * 0.07 + sin(x / w * 9 + ph[3]) * h * 0.025;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      int c;
      final dx = x - sunX, dy = y - sunY;
      final d = sqrt(dx * dx + dy * dy);
      if (y > horizon) {
        // Water mirrors the sky with soft ripples.
        final t = (y - horizon) / (h - horizon);
        c = _mix(p[5], p[4], t * 0.8);
        if ((x - sunX).abs() < sunR * (1.4 - t) && sin(y * 1.7) > 0.1) {
          c = _mix(c, p[2], 0.55);
        }
      } else if (y > near(x.toDouble()) && y <= horizon) {
        c = _mix(p[4], 0xFF000000, ((y - near(x.toDouble())) / h).clamp(0, 0.4));
      } else if (y > far(x.toDouble())) {
        c = _mix(p[3], p[4], 0.25);
      } else if (d < sunR) {
        c = p[2];
      } else {
        c = _mix(p[0], p[1], y / horizon);
        if (d < sunR * 3) c = _mix(c, p[2], (1 - d / (sunR * 3)) * 0.45);
      }
      if (vignette) {
        final t = y / h;
        final dark = t < 0.25 ? (0.25 - t) / 0.25 * 0.6 : t > 0.7 ? (t - 0.7) / 0.3 * 0.65 : 0.0;
        if (dark > 0) c = _mix(c, 0xFF000000, dark);
      }
      final i = (y * w + x) * 4;
      px[i] = (c >> 16) & 0xFF;
      px[i + 1] = (c >> 8) & 0xFF;
      px[i + 2] = c & 0xFF;
      px[i + 3] = 0xFF;
    }
  }
  return encodePng(w, h, px);
}

final _thumbs = <String, Uint8List>{};
Uint8List thumbFor(String id) =>
    _thumbs.putIfAbsent(id, () => paintScene(id.codeUnits.fold(7, (a, b) => (a * 31 + b) % 9973), 160, 90));

// ------------------------------------------------------------------ library

final _now = DateTime.now();

VideoEntry video(String id, String title, String folder, Duration length,
    {int mb = 0, int daysAgo = 10, int w = 1920, int h = 1080}) {
  final t = _now.subtract(Duration(days: daysAgo)).millisecondsSinceEpoch ~/ 1000;
  final v = VideoEntry(
    AssetEntity(
      id: id,
      typeInt: AssetType.video.index,
      width: w,
      height: h,
      duration: length.inSeconds,
      title: title,
      createDateSecond: t,
      modifiedDateSecond: t,
      relativePath: 'DCIM/$folder/',
    ),
    folder,
  );
  v.size = mb * 1024 * 1024;
  return v;
}

Duration d(int m, [int s = 0]) => Duration(minutes: m, seconds: s);

List<VideoFolder> sampleFolders() {
  var n = 0;
  List<VideoEntry> many(String folder, int count, Duration Function(int) len) => [
        for (var i = 0; i < count; i++)
          video('${folder.hashCode}_${n++}', 'VID_2026${(i % 9) + 1}1${i % 10}_1${i % 6}4${i % 10}22.mp4',
              folder, len(i),
              mb: 40 + i * 13 % 300, daysAgo: 20 + i * 3),
      ];
  final trips = [
    video('trip1', 'Goa Trip - Baga Beach Sunset.mp4', 'Trips', d(24, 18), mb: 812, daysAgo: 1),
    video('trip2', 'Manali Snow Day with Friends.mp4', 'Trips', d(12, 4), mb: 455, daysAgo: 2),
    video('trip3', 'Kerala Backwaters Houseboat.mp4', 'Trips', d(31, 47), mb: 1230, daysAgo: 6),
    video('trip4', 'Ladakh Bike Ride - Khardung La.mp4', 'Trips', d(18, 9), mb: 690, daysAgo: 9),
    video('trip5', 'Rishikesh River Rafting.mp4', 'Trips', d(7, 33), mb: 260, daysAgo: 14),
    video('trip6', 'Jaipur Night Market Walk.mp4', 'Trips', d(15, 2), mb: 540, daysAgo: 21,
        w: 3840, h: 2160),
    video('trip7', 'Udaipur Lake Palace Timelapse.mp4', 'Trips', d(2, 41), mb: 118, daysAgo: 30),
    video('trip8', 'Munnar Tea Gardens Drone.mp4', 'Trips', d(5, 12), mb: 205, daysAgo: 44),
    video('trip9', 'Andaman Scuba Diving.mp4', 'Trips', d(9, 58), mb: 377, daysAgo: 60),
  ];
  return [
    VideoFolder('cam', 'Camera', many('Camera', 42, (i) => d(i % 7, (i * 17) % 60))),
    VideoFolder('dl', 'Download', many('Download', 16, (i) => d(20 + i * 3, i * 7 % 60))),
    VideoFolder('fam', 'Family Functions', [
      video('fam1', 'Diwali 2026 at Dadi\'s House.mp4', 'Family Functions', d(18, 40), mb: 640),
      video('fam2', 'Riya\'s Wedding Sangeet.mp4', 'Family Functions', d(46, 12), mb: 1720),
      ...many('Family Functions', 9, (i) => d(3 + i, 20)),
    ]),
    VideoFolder('mov', 'Movies', many('Movies', 8, (i) => d(118 + i * 7, 15))),
    VideoFolder('rec', 'Screen Recordings', many('Screen Recordings', 6, (i) => d(1 + i, 5))),
    VideoFolder('tg', 'Telegram Video', many('Telegram Video', 23, (i) => d(4 + i % 30, 12))),
    VideoFolder('trips', 'Trips', trips),
    VideoFolder('wa', 'WhatsApp Video', many('WhatsApp Video', 87, (i) => d(i % 3, (i * 11) % 60))),
  ];
}

// -------------------------------------------------------------------- party

/// A watch party with friends already in it, for the party sheet.
class ShotParty extends WatchParty implements OnlineParty {
  ShotParty() : super('Rahul') {
    members = ['Rahul', 'Priya', 'Aman', 'Sneha'];
    for (final (from, text) in const [
      ('Priya', 'This sunset is unreal 😍'),
      ('Aman', 'Wait, pause at 12:30, that was us on the boat!'),
      ('Sneha', 'Take me with you next time 😂'),
      ('Priya', 'Same time tomorrow for part 2?'),
    ]) {
      messages.add(PartyMessage(from: from, text: text));
    }
  }

  @override
  final String code = 'K7QF2M';
  @override
  final OnlineVideo video =
      const OnlineVideo(title: 'Goa Trip - Baga Beach Sunset.mp4');
  @override
  bool get isHost => false;
  @override
  bool get owner => true;
  @override
  bool get canReport => true;
  @override
  String get inviteText => 'Join me';
  @override
  Future<void> requestPlay() async => player?.play();
  @override
  Future<void> requestPause() async => player?.pause();
  @override
  Future<void> requestSeek(Duration to) async => player?.seek(to);
  @override
  Future<void> requestRate(double rate) async => player?.setRate(rate);
  @override
  void sendChat(String text) {}
  @override
  void sendReaction(String emoji) {}
  @override
  Future<void> close() async {}
  /// A chat line or reaction arriving from a friend.
  void say(String from, String text, {bool emoji = false}) =>
      received(PartyMessage(from: from, text: text, emoji: emoji));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// -------------------------------------------------------------------- setup

const _photo = MethodChannel('com.fluttercandies/photo_manager');
const _videoOut = MethodChannel('com.alexmercerind/media_kit_video');

void mockPlugins() {
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // Video output: answer with a texture id the way the native side does,
  // so the player stops waiting for its video surface.
  m.setMockMethodCallHandler(_videoOut, (call) async {
    if (call.method == 'VideoOutputManager.Create') {
      final handle = int.parse((call.arguments as Map)['handle'] as String);
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        m.handlePlatformMessage(
          _videoOut.name,
          _videoOut.codec.encodeMethodCall(MethodCall('VideoOutput.Resize', {
            'handle': handle,
            'id': 1,
            'rect': {'left': 0, 'top': 0, 'width': 1280, 'height': 720},
          })),
          (_) {},
        );
      });
    }
    return null;
  });
  m.setMockMethodCallHandler(_photo, (call) async {
    switch (call.method) {
      case 'requestPermissionExtend':
      case 'getPermissionState':
        return PermissionState.denied.index; // the test fills the library itself
      case 'getThumb':
        return thumbFor((call.arguments as Map)['id'] as String);
    }
    return null;
  });
  for (final c in [
    'in.onlysoftware.video_player/system',
    'com.fluttercandies/photo_manager/notify',
  ]) {
    m.setMockMethodCallHandler(MethodChannel(c), (_) async => null);
  }
}

Future<Settings> openSettings() async {
  SharedPreferences.setMockInitialValues({});
  final s = await Settings.open();
  // Continue watching and a few progress bars in the list.
  s.addRecent(RecentItem(
      key: 'trip5', title: 'Rishikesh River Rafting.mp4', uri: 'x', assetId: 'trip5'));
  s.savePosition('trip5', d(7, 33), d(7, 33));
  s.addRecent(RecentItem(
      key: 'trip4',
      title: 'Ladakh Bike Ride - Khardung La.mp4',
      uri: 'x',
      assetId: 'trip4',
      position: d(16, 30),
      duration: d(18, 9)));
  s.savePosition('trip4', d(16, 30), d(18, 9));
  s.addRecent(RecentItem(
      key: 'trip3',
      title: 'Kerala Backwaters Houseboat.mp4',
      uri: 'content://media/external/video/media/trip3',
      assetId: 'trip3',
      position: d(19, 2),
      duration: d(31, 47)));
  s.savePosition('trip3', d(19, 2), d(31, 47));
  return s;
}

Future<void> fillLibrary(WidgetTester tester) async {
  await settleReal(tester, rounds: 4);
  final lib = VideoLibrary.instance;
  lib.folders = sampleFolders();
  lib.state = LibraryState.ready;
  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  lib.notifyListeners();
  await settleReal(tester, rounds: 10);
}

/// Makes a real video file so mpv reports a real length and position.
Future<String?> makeClip() async {
  final out = '${Directory.systemTemp.path}/vp_store_clip.mp4';
  if (File(out).existsSync()) return out;
  try {
    final r = await Process.run('ffmpeg', [
      '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'color=c=0x223344:s=160x90:r=1:d=1907',
      '-f', 'lavfi', '-i', 'anullsrc=r=8000:cl=mono',
      '-t', '1907', '-c:v', 'libx264', '-preset', 'ultrafast',
      '-c:a', 'aac', '-shortest', out,
    ]);
    return r.exitCode == 0 ? out : null;
  } catch (_) {
    return null;
  }
}

/// Paints [frame] under the app, where the decoded video would be. Test
/// video textures don't paint, so [seeThrough] then clears the player's
/// black backgrounds and the picture shows through, under the real controls.
TransitionBuilder frameUnder(ui.Image frame, Rect Function(Size) area) =>
    (context, child) => Stack(children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned.fill(child: CustomPaint(painter: _FramePainter(frame, area))),
          child!,
        ]);

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame, this.area);
  final ui.Image frame;
  final Rect Function(Size) area;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      frame,
      Rect.fromLTWH(0, 0, frame.width.toDouble(), frame.height.toDouble()),
      area(size),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => false;
}

/// Makes the player's solid black fills (scaffold, video fill) transparent.
void seeThrough(WidgetTester tester) {
  void visit(RenderObject o) {
    try {
      final c = (o as dynamic).color;
      if (c is Color && c.toARGB32() == 0xFF000000) {
        (o as dynamic).color = const Color(0x00000000);
      }
    } catch (_) {}
    o.visitChildren(visit);
  }

  visit(tester.renderObject(find.byType(PlayerScreen)));
}

/// Colour emoji for chat and reactions, from the Flutter engine's test fonts.
Future<void> loadEmojiFont() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final f = File('$root/engine/src/flutter/txt/third_party/fonts/NotoColorEmoji.ttf');
  if (!f.existsSync()) return;
  // 'Ubuntu' is a fallback family in the Linux text theme (see the party
  // sheet below).
  for (final family in ['NotoColorEmoji', 'Ubuntu']) {
    final l = FontLoader(family)
      ..addFont(Future.value(ByteData.view(Uint8List.fromList(f.readAsBytesSync()).buffer)));
    await l.load();
  }
}

/// The app's own theme and home screen, with Roboto named on the app bar
/// title: its style has no font family, which a phone fills with Roboto
/// but the test fills with box glyphs.
Future<void> pumpApp(WidgetTester tester, Settings s,
    {Widget? home, TransitionBuilder? builder}) async {
  // Read the theme with the home screen at phone size (in landscape its
  // permission prompt would not fit, and it is not what the shot shows).
  final size = tester.view.physicalSize;
  tester.view.physicalSize = phoneSize;
  await tester.pumpWidget(VideoPlayerApp(settings: s));
  final ctx = tester.element(find.byType(HomeScreen));
  final theme = Theme.of(ctx);
  tester.view.physicalSize = size;
  final bar = theme.appBarTheme;
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamilyFallback: const ['NotoColorEmoji']),
        appBarTheme: bar.copyWith(
            titleTextStyle: bar.titleTextStyle?.copyWith(fontFamily: 'Roboto'))),
    builder: builder,
    home: home ?? HomeScreen(settings: s, vault: PrivateVault(s)),
  ));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockPlugins();
    MediaKit.ensureInitialized();
    await loadRealFonts();
    await loadEmojiFont();
  });

  // One test: thumbnails are cached across screens, and a cached load
  // from an earlier test never finishes in the next one.
  testWidgets('library folders and videos', (tester) async {
    usePhone(tester);
    final s = await openSettings();
    await pumpApp(tester, s);
    await fillLibrary(tester);
    await shot(tester, '01_folders');
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(
        builder: (_) => FolderScreen(folderId: 'trips', settings: s, vault: PrivateVault(s))));
    await settleReal(tester, rounds: 20);
    await shot(tester, '02_videos');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('player', (tester) async {
    final clip = await tester.runAsync(makeClip);
    if (clip == null) {
      markTestSkipped('ffmpeg is needed for the player shot');
      return;
    }
    tester.view.physicalSize = const Size(2160, 1080);
    tester.view.devicePixelRatio = phoneRatio;
    addTearDown(tester.view.reset);
    final s = await openSettings();
    s.savePosition('goa', d(9, 42), d(31, 47));
    final frame = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(paintScene(0, 1280, 720));
      return (await codec.getNextFrame()).image;
    }))!;
    await pumpApp(tester, s,
        builder: frameUnder(frame, (size) {
          final h = size.height, w = h * 16 / 9;
          return Rect.fromLTWH((size.width - w) / 2, 0, w, h);
        }),
        home: PlayerScreen(settings: s, queue: [
          PlayItem(uri: clip, title: 'Goa Trip - Baga Beach Sunset.mp4', key: 'goa'),
          PlayItem(uri: clip, title: 'Manali Snow Day with Friends.mp4', key: 'manali'),
        ]));
    for (var i = 0; i < 20 && find.text('31:47').evaluate().isEmpty; i++) {
      await settleReal(tester, rounds: 2);
    }
    if (find.byIcon(Icons.pause_rounded).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await settleReal(tester, rounds: 10);
    }
    seeThrough(tester);
    await shot(tester, '03_player');
    await tester.pumpWidget(const SizedBox());
    await settleReal(tester, rounds: 10);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('watch party', (tester) async {
    final clip = await tester.runAsync(makeClip);
    if (clip == null) {
      markTestSkipped('ffmpeg is needed for the party shot');
      return;
    }
    usePhone(tester);
    final s = await openSettings();
    final frame = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(paintScene(0, 1280, 720));
      return (await codec.getNextFrame()).image;
    }))!;
    final party = ShotParty();
    await pumpApp(tester, s,
        builder: frameUnder(frame, (size) {
          final w = size.width, h = w * 9 / 16;
          return Rect.fromLTWH(0, (size.height - h) / 2, w, h);
        }),
        home: PlayerScreen(
            settings: s,
            party: party,
            queue: [PlayItem(uri: clip, title: 'Goa Trip - Baga Beach Sunset.mp4', key: 'party')]));
    for (var i = 0; i < 40 && find.text('31:47').evaluate().isEmpty; i++) {
      await settleReal(tester, rounds: 2);
    }
    // The party sheet makes its own theme, whose text has no emoji
    // fallback on Android; the Linux one falls back to 'Ubuntu', which
    // setUpAll mapped to the emoji font.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.tap(find.byIcon(Icons.groups_rounded));
    await settleReal(tester, rounds: 20);
    seeThrough(tester);
    await shot(tester, '04_watch_party');
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
    await settleReal(tester, rounds: 10);
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('watch party on the video', (tester) async {
    final clip = await tester.runAsync(makeClip);
    if (clip == null) {
      markTestSkipped('ffmpeg is needed for the party shot');
      return;
    }
    tester.view.physicalSize = const Size(2160, 1080);
    tester.view.devicePixelRatio = phoneRatio;
    addTearDown(tester.view.reset);
    final s = await openSettings();
    s.savePosition('party2', d(17, 5), d(31, 47));
    final frame = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(paintScene(3, 1280, 720));
      return (await codec.getNextFrame()).image;
    }))!;
    final party = ShotParty();
    await pumpApp(tester, s,
        builder: frameUnder(frame, (size) {
          final h = size.height, w = h * 16 / 9;
          return Rect.fromLTWH((size.width - w) / 2, 0, w, h);
        }),
        home: PlayerScreen(
            settings: s,
            party: party,
            queue: [PlayItem(uri: clip, title: 'Udaipur Lake Palace Timelapse.mp4', key: 'party2')]));
    for (var i = 0; i < 40 && find.text('31:47').evaluate().isEmpty; i++) {
      await settleReal(tester, rounds: 2);
    }
    // Wait for the resume note to go, bring the controls back, then
    // friends react.
    await tester.pump(const Duration(seconds: 6));
    await tester.tapAt(tester.getCenter(find.byType(PlayerScreen)) + const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 400));
    party.say('Priya', 'Look at those colours!');
    party.say('Aman', 'Best trip ever');
    party.say('Sneha', 'Next time I am coming too');
    for (final (e, ms) in const [('😍', 300), ('🔥', 500), ('❤️', 250), ('👏', 400), ('😍', 350)]) {
      party.say('Priya', e, emoji: true);
      await tester.pump(Duration(milliseconds: ms));
    }
    await tester.pump(const Duration(milliseconds: 200));
    seeThrough(tester);
    await shot(tester, '05_watch_party_chat');
    await tester.pumpWidget(const SizedBox());
    await settleReal(tester, rounds: 10);
    await tester.pump(const Duration(seconds: 30));
  });
}
