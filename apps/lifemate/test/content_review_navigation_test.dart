import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// Explicit HTTP fixtures exercise navigation; they do not certify server grants.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({});
    String? token;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('lifeguide/local_write_guard'), (call) async {
      if (call.method == 'getBlocked') return token != null;
      if (call.method == 'beginWrite') return token = 'navigation-fixture';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });
  http.Response json(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status,
          headers: {'content-type': 'application/json; charset=utf-8'});

  HttpIdentityApi client(Future<http.Response> Function() permissions) =>
      HttpIdentityApi(
          baseUrl: 'https://navigation.example.test/api',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/content-capabilities')) {
              return permissions();
            }
            if (request.url.path.endsWith('/profile')) {
              return json({
                'user_id': 'synthetic-parent',
                'display_name': 'والد آزمایشی',
                'profile_category': 'adult',
                'theme_preference': 'adult_blue',
              });
            }
            return json({'items': [], 'families': []});
          }))
        ..accessToken = 'synthetic-token'
        ..currentUserId = 'synthetic-parent';

  Future<void> openDrawer(WidgetTester tester) async {
    tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('parent category grants no content operations menu',
      (tester) async {
    final api = client(() async => json({'permissions': []}));
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: api)));
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(find.text('بررسی محتوای آموزشی'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('explicit read capability is shown and failed refresh removes it',
      (tester) async {
    var failed = false;
    final api = client(() async => failed
        ? json({'error': 'synthetic_failure'}, 503)
        : json({
            'permissions': ['feedback.read']
          }));
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: api)));
    await tester.pumpAndSettle();
    await openDrawer(tester);
    await tester.scrollUntilVisible(find.text('بررسی محتوای آموزشی'), 100,
        scrollable: find
            .descendant(
                of: find.byType(Drawer), matching: find.byType(Scrollable))
            .first);
    expect(find.text('بررسی محتوای آموزشی'), findsOneWidget);
    failed = true;
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('بررسی محتوای آموزشی'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('late grant response from a previous account is discarded',
      (tester) async {
    final delayed = Completer<http.Response>();
    final api = client(() => delayed.future);
    await tester.pumpWidget(MaterialApp(home: HomeShell(api: api)));
    await tester.pump();
    api.currentUserId = 'another-synthetic-account';
    delayed.complete(json({
      'permissions': ['feedback.read']
    }));
    await tester.pumpAndSettle();
    await openDrawer(tester);
    expect(find.text('بررسی محتوای آموزشی'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
