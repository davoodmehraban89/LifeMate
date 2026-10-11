import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifemate/aparat_player.dart';

class _PlayerPort implements AparatPlayerPort {
  final List<Uri> frames = [];
  ValueChanged<String>? fail;

  @override
  bool get isSupported => true;

  @override
  Widget buildFrame(BuildContext context,
      {required Uri uri,
      required String title,
      required VoidCallback onFrameReady,
      required ValueChanged<String> onError}) {
    frames.add(uri);
    fail = onError;
    return const ColoredBox(
        key: ValueKey('fixture-frame'), color: Colors.black);
  }
}

Widget _app(_PlayerPort port, {String hash = 'rod03i6'}) => MaterialApp(
    home: Scaffold(
        body: AparatPlayerPortScope(
            port: port,
            child: AparatPlayer(videoHash: hash, title: 'درس نمونه'))));

void main() {
  test('hash policy rejects URLs, escaped paths and unbounded identifiers', () {
    for (final hash in [
      '',
      'abcd',
      'a' * 65,
      'rod03i6?autoplay=true',
      'rod03i6/other',
      '%72od03i6',
      'رود۳',
      'https://www.aparat.com/v/rod03i6',
      ' rod03i6',
      'rod03i6\n'
    ]) {
      expect(aparatEmbedUri(hash), isNull, reason: hash);
    }
    expect(aparatEmbedUri('rOd03i6').toString(),
        'https://www.aparat.com/video/video/embed/videohash/rOd03i6/vt/frame');
  });

  test('native navigation allows only the selected canonical HTTPS frame', () {
    final canonical = aparatEmbedUri('rod03i6')!;
    expect(isAllowedAparatNavigation(canonical.toString(), 'rod03i6'), isTrue);
    expect(
        isAllowedAparatNavigation(
            canonical.replace(host: 'aparat.com').toString(), 'rod03i6'),
        isTrue);
    for (final url in [
      'http://www.aparat.com${canonical.path}',
      'https://www.aparat.com.evil.test${canonical.path}',
      'https://evil.test${canonical.path}',
      'https://user@www.aparat.com${canonical.path}',
      'https://www.aparat.com:444${canonical.path}',
      'https://www.aparat.com/video/video/embed/videohash/%72od03i6/vt/frame',
      '${canonical.toString()}?autoplay=true',
      '${canonical.toString()}#other',
      'https://www.aparat.com/v/rod03i6',
      'https://www.aparat.com/video/video/embed/videohash/other01/vt/frame',
      'javascript:alert(1)',
      'intent://www.aparat.com',
      'about:blank'
    ]) {
      expect(isAllowedAparatNavigation(url, 'rod03i6'), isFalse, reason: url);
    }
  });

  testWidgets('no provider frame exists until the explicit load click',
      (tester) async {
    final port = _PlayerPort();
    await tester.pumpWidget(_app(port));
    expect(port.frames, isEmpty);
    expect(find.textContaining('حریم خصوصی'), findsOneWidget);
    await tester.tap(find.text('بارگذاری ویدئو از آپارات'));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-frame')), findsOneWidget);
    expect(port.frames.single.toString(),
        'https://www.aparat.com/video/video/embed/videohash/rod03i6/vt/frame');
    expect(port.frames.single.hasQuery, isFalse);
    expect(port.frames.single.hasFragment, isFalse);
    expect(find.textContaining('اثبات مطالعه'), findsOneWidget);
  });

  testWidgets('invalid identifier cannot load a remote player', (tester) async {
    final port = _PlayerPort();
    await tester.pumpWidget(_app(port, hash: 'rod03i6?autoplay=true'));
    expect(find.textContaining('شناسهٔ ویدئو معتبر نیست'), findsOneWidget);
    expect(find.text('بارگذاری ویدئو از آپارات'), findsNothing);
    expect(port.frames, isEmpty);
  });

  testWidgets('load failure removes the frame and offers an explicit retry',
      (tester) async {
    final port = _PlayerPort();
    await tester.pumpWidget(_app(port));
    await tester.tap(find.text('بارگذاری ویدئو از آپارات'));
    await tester.pump();
    port.fail!('network');
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-frame')), findsNothing);
    expect(find.textContaining('بارگذاری آپارات انجام نشد'), findsOneWidget);
    await tester.tap(find.text('تلاش دوباره'));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-frame')), findsOneWidget);
    expect(port.frames, hasLength(2));
  });

  testWidgets(
      'new selection requires consent again and stale errors are ignored',
      (tester) async {
    final port = _PlayerPort();
    await tester.pumpWidget(_app(port));
    await tester.tap(find.text('بارگذاری ویدئو از آپارات'));
    await tester.pump();
    final oldFailure = port.fail!;
    await tester.pumpWidget(_app(port, hash: 'new0123'));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-frame')), findsNothing);
    oldFailure('late failure');
    await tester.pump();
    expect(find.textContaining('بارگذاری آپارات انجام نشد'), findsNothing);
    expect(find.text('بارگذاری ویدئو از آپارات'), findsOneWidget);
    expect(port.frames, hasLength(1));
  });

  testWidgets('closing the player removes remote content', (tester) async {
    final port = _PlayerPort();
    await tester.pumpWidget(_app(port));
    await tester.tap(find.text('بارگذاری ویدئو از آپارات'));
    await tester.pump();
    await tester.tap(find.text('بستن پخش‌کننده'));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-frame')), findsNothing);
    expect(find.text('بارگذاری ویدئو از آپارات'), findsOneWidget);
  });

  testWidgets('backgrounding removes provider content and requires a new click',
      (tester) async {
    final port = _PlayerPort();
    await tester.pumpWidget(_app(port));
    await tester.tap(find.text('بارگذاری ویدئو از آپارات'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-frame')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('بارگذاری ویدئو از آپارات'), findsOneWidget);
    expect(port.frames, hasLength(1));
  });

  testWidgets('unsupported desktop explains the in-page limitation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: AparatPlayer(videoHash: 'rod03i6', title: 'درس نمونه'))));
    await tester.tap(find.text('بارگذاری ویدئو از آپارات'));
    await tester.pump();
    expect(find.textContaining('پخش در این نسخه پشتیبانی نمی‌شود'),
        findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('fullscreen Back returns the native view once', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Text('underlying app')));
    final presenter =
        AparatFullscreenPresenter(navigator: navigator.currentState!);
    var returned = 0;
    presenter.show(const Text('native fullscreen'), () {
      returned++;
      presenter
          .hide(); // Native custom-view hide can follow the close callback.
    });
    await tester.pumpAndSettle();
    expect(find.text('native fullscreen'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(returned, 1);
    presenter.hide();
    await tester.pumpAndSettle();
    expect(find.text('underlying app'), findsOneWidget);
    expect(returned, 1);
    presenter.dispose();
  });

  testWidgets('native fullscreen hide removes its route without popping others',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Text('underlying app')));
    final presenter =
        AparatFullscreenPresenter(navigator: navigator.currentState!);
    var returned = 0;
    presenter.show(const Text('native fullscreen'), () => returned++);
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('another app route'))));
    await tester.pumpAndSettle();
    presenter.hide();
    presenter.hide();
    await tester.pumpAndSettle();
    expect(find.text('another app route'), findsOneWidget);
    expect(returned, 0);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('underlying app'), findsOneWidget);
    presenter.dispose();
  });

  testWidgets('fullscreen close and disposal notify native only once',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Text('underlying app')));
    final presenter =
        AparatFullscreenPresenter(navigator: navigator.currentState!);
    var returned = 0;
    presenter.show(const Text('native fullscreen'), () => returned++);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('خروج از تمام‌صفحه'));
    await tester.pumpAndSettle();
    expect(returned, 1);
    presenter.show(const Text('native fullscreen again'), () => returned++);
    await tester.pumpAndSettle();
    presenter.dispose();
    presenter.hide();
    await tester.pumpAndSettle();
    expect(returned, 2);
    expect(find.text('underlying app'), findsOneWidget);
  });
}
