import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifemate/api.dart';
import 'package:lifemate/family_management_ui.dart';
import 'package:lifemate/offline_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const familyId = 'a1111111-1111-4111-8111-111111111111';
const actorId = 'b1111111-1111-4111-8111-111111111111';
const targetId = 'c1111111-1111-4111-8111-111111111111';
const mutationId = 'd1111111-1111-4111-8111-111111111111';
const at = '2026-10-11T12:00:00Z';
http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> family(
        {bool admin = true, String name = 'خانواده آزمایشی'}) =>
    {'id': familyId, 'name': name, 'role': 'adult_member', 'is_admin': admin};
Map<String, dynamic> member(String id, String name,
        {bool admin = false, int version = 1, String role = 'adult_member'}) =>
    {
      'user_id': id,
      'display_name': name,
      'role': role,
      'is_admin': admin,
      'theme_preference': 'adult_blue',
      'version': version,
      'updated_at': at
    };
HttpIdentityApi fixture(Future<http.Response> Function(http.Request) handler) =>
    HttpIdentityApi(
        baseUrl: 'https://family.example.test/api', client: MockClient(handler))
      ..accessToken = 'synthetic-token'
      ..currentUserId = actorId;

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
      if (call.method == 'beginWrite') return token = 'family-write';
      if (call.method == 'completeWrite' && call.arguments == token) {
        token = null;
        return true;
      }
      throw PlatformException(code: 'local_storage_restart_required');
    });
  });

  test('role receipt lost after commit retries identical metadata after reopen',
      () async {
    var lost = true;
    final sent = <String>[];
    final api = fixture((request) async {
      if (request.method == 'GET') return response(family());
      sent.add(request.body);
      if (lost) throw http.ClientException('lost receipt');
      return response({
        'members': [
          {
            'userId': targetId,
            'role': 'parent_guardian',
            'isAdmin': false,
            'version': 2,
            'updatedAt': at,
            'endedAt': null
          }
        ],
        'acknowledgement': {
          'mutationId': mutationId,
          'familyId': familyId,
          'targetId': targetId,
          'operation': 'role',
          'status': 'already_applied'
        }
      });
    });
    final body = {
      'mutationId': mutationId,
      'expectedVersion': 1,
      'role': 'parent_guardian'
    };
    await expectLater(
        FamilyOperationSync(api, familyId).submit('role', targetId, body),
        throwsA(predicate(isOfflineFailure)));
    final pending = (await FamilyOperationSync(api, familyId).pending()).single;
    expect(pending['payload'], body);
    expect(jsonEncode(pending), isNot(contains('display_name')));
    expect(await OfflineStore.forApi(api).readList('family'), isEmpty);
    lost = false;
    await FamilyOperationSync(api, familyId).retry(pending);
    expect(sent.length, 2);
    expect(sent.first, sent.last);
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    api.close();
  });

  test(
      'former administrator may replay only journalled transfer and new changes require actual admin',
      () async {
    var admin = true, lost = true;
    final api = fixture((request) async {
      if (request.method == 'GET') return response(family(admin: admin));
      if (lost) {
        admin = false;
        throw http.ClientException('lost receipt');
      }
      return response({
        'members': [
          {
            'userId': actorId,
            'role': 'adult_member',
            'isAdmin': false,
            'version': 2,
            'updatedAt': at,
            'endedAt': null
          },
          {
            'userId': targetId,
            'role': 'adult_member',
            'isAdmin': true,
            'version': 2,
            'updatedAt': at,
            'endedAt': null
          }
        ],
        'acknowledgement': {
          'mutationId': mutationId,
          'familyId': familyId,
          'targetId': targetId,
          'operation': 'admin_transfer',
          'status': 'already_applied'
        }
      });
    });
    final sync = FamilyOperationSync(api, familyId);
    await expectLater(
        sync.submit('admin_transfer', targetId, {
          'mutationId': mutationId,
          'targetUserId': targetId,
          'expectedVersion': 1,
          'expectedActorVersion': 1
        }),
        throwsA(predicate(isOfflineFailure)));
    final pending = (await sync.pending()).single;
    lost = false;
    await FamilyOperationSync(api, familyId).retry(pending);
    await expectLater(
        sync.submit('role', targetId, {
          'mutationId': mutationId,
          'expectedVersion': 2,
          'role': 'parent_guardian'
        }),
        throwsA(isA<ApiException>()));
    expect(await sync.pending(), isEmpty);
    api.close();
  });

  test(
      'wrong transfer receipt never removes durable metadata, and scope change blocks retries',
      () async {
    final api = fixture((request) async => request.method == 'GET'
        ? response(family())
        : response({
            'members': [
              {
                'userId': targetId,
                'role': 'adult_member',
                'isAdmin': true,
                'version': 2,
                'updatedAt': at,
                'endedAt': null
              }
            ],
            'acknowledgement': {
              'mutationId': mutationId,
              'familyId': familyId,
              'targetId': targetId,
              'operation': 'admin_transfer',
              'status': 'accepted'
            }
          }));
    final sync = FamilyOperationSync(api, familyId);
    await expectLater(
        sync.submit('admin_transfer', targetId, {
          'mutationId': mutationId,
          'targetUserId': targetId,
          'expectedVersion': 1,
          'expectedActorVersion': 1
        }),
        throwsA(isA<ApiException>()));
    final saved = (await sync.pending()).single;
    api.currentUserId = targetId;
    await expectLater(sync.retry(saved), throwsA(isA<ApiException>()));
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    api.close();
  });

  testWidgets(
      'adult role does not grant management and network failure clears the member list',
      (tester) async {
    var offline = false;
    final api = fixture((request) async {
      if (offline) throw http.ClientException('offline');
      if (request.url.path.endsWith('/members')) {
        return response({
          'members': [member(actorId, 'والد آزمایشی')]
        });
      }
      return response(family(admin: false));
    });
    await tester.pumpWidget(
        MaterialApp(home: FamilyManagementPage(api: api, familyId: familyId)));
    await tester.pumpAndSettle();
    expect(find.text('والد آزمایشی'), findsOneWidget);
    expect(find.text('بایگانی خانواده'), findsNothing);
    expect(find.text('دعوت عضو'), findsNothing);
    offline = true;
    await tester.tap(find.byKey(const Key('family-management-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('والد آزمایشی'), findsNothing);
    expect(find.textContaining('اتصال'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'late family read cannot restore members after newer access denial',
      (tester) async {
    final delayed = Completer<http.Response>();
    var reads = 0;
    final api = fixture((request) async {
      if (request.url.path.endsWith('/members')) {
        return response({
          'members': [member(actorId, 'والد آزمایشی')]
        });
      }
      return ++reads == 1
          ? delayed.future
          : response({'error': 'forbidden'}, 403);
    });
    await tester.pumpWidget(
        MaterialApp(home: FamilyManagementPage(api: api, familyId: familyId)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('family-management-refresh')));
    await tester.pumpAndSettle();
    delayed.complete(response(family(admin: false)));
    await tester.pumpAndSettle();
    expect(find.text('والد آزمایشی'), findsNothing);
    expect(find.textContaining('دسترسی'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
  test(
      'a role mutation cannot trust missing or contradictory server administrator flags',
      () async {
    for (final raw in [
      {'id': familyId, 'role': 'adult_member'},
      {'id': familyId, 'role': 'teen_minor', 'is_admin': true},
    ]) {
      var writes = 0;
      final api = fixture((request) async {
        if (request.method == 'GET') return response(raw);
        writes++;
        return response({});
      });
      final sync = FamilyOperationSync(api, familyId);
      await expectLater(
          sync.submit('role', targetId, {
            'mutationId': mutationId,
            'expectedVersion': 1,
            'role': 'parent_guardian'
          }),
          throwsA(isA<ApiException>()));
      expect(writes, 0);
      expect(await sync.pending(), isEmpty);
      api.close();
    }
  });

  testWidgets(
      'role change needs confirmation and refreshes canonical role without dropdown crash',
      (tester) async {
    var role = 'adult_member', version = 1;
    final writes = <Map<String, dynamic>>[];
    final api = fixture((request) async {
      if (request.url.path.endsWith('/members')) {
        return response({
          'members': [
            member(actorId, 'مدیر آزمایشی', admin: true),
            member(targetId, 'عضو آزمایشی', version: version, role: role),
          ]
        });
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/invitations')) {
        return response({'invitations': [], 'nextCursor': null, 'total': 0});
      }
      if (request.method == 'GET') return response(family());
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      writes.add(body);
      role = body['role'] as String;
      version++;
      return response({
        'members': [
          {
            'userId': targetId,
            'role': role,
            'isAdmin': false,
            'version': version,
            'updatedAt': at,
            'endedAt': null,
          }
        ],
        'acknowledgement': {
          'mutationId': body['mutationId'],
          'familyId': familyId,
          'targetId': targetId,
          'operation': 'role',
          'status': 'accepted',
        }
      });
    });
    await tester.pumpWidget(
        MaterialApp(home: FamilyManagementPage(api: api, familyId: familyId)));
    await tester.pumpAndSettle();
    final dropdown = find.byKey(const Key('family-member-role-$targetId'));
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('سرپرست').last);
    await tester.pumpAndSettle();
    expect(find.text('تغییر نقش عضو'), findsOneWidget);
    await tester.tap(find.text('انصراف'));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('سرپرست').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تأیید تغییر'));
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    expect(writes.single['expectedVersion'], 1);
    expect(writes.single['mutationId'], isA<String>());
    expect(role, 'parent_guardian');
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'revoked access clears members, invitation hints and any contact draft',
      (tester) async {
    var denied = false;
    final api = fixture((request) async {
      if (denied) return response({'error': 'forbidden'}, 403);
      if (request.url.path.endsWith('/members')) {
        return response({
          'members': [
            member(actorId, 'مدیر آزمایشی', admin: true),
            member(targetId, 'عضو آزمایشی'),
          ]
        });
      }
      if (request.url.path.endsWith('/invitations')) {
        return response({
          'invitations': [
            {
              'id': mutationId,
              'intendedRole': 'adult_member',
              'status': 'pending',
              'version': 1,
              'createdAt': at,
              'expiresAt': '2026-10-12T12:00:00Z',
              'recipientHint': '***@example.test',
            }
          ],
          'nextCursor': null,
          'total': 1
        });
      }
      return response(family());
    });
    await tester.pumpWidget(
        MaterialApp(home: FamilyManagementPage(api: api, familyId: familyId)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('***@example.test'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('***@example.test'), findsOneWidget);
    final draft =
        tester.widget<TextField>(find.byType(TextField).last).controller!;
    draft.text = 'synthetic-private-recipient@example.test';
    denied = true;
    await tester.tap(find.byKey(const Key('family-management-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('***@example.test'), findsNothing);
    expect(find.text('عضو آزمایشی'), findsNothing);
    expect(find.text('دعوت عضو'), findsNothing);
    expect(draft.text, isEmpty);
    expect(find.textContaining('دسترسی'), findsWidgets);
    expect(await OfflineStore.forApi(api).readList('family'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets(
      'unknown result of legacy family rename only refreshes and never retries the write automatically',
      (tester) async {
    var renamed = false, patches = 0;
    final api = fixture((request) async {
      if (request.method == 'PATCH') {
        patches++;
        renamed = true;
        throw http.ClientException('synthetic receipt lost');
      }
      if (request.url.path.endsWith('/members')) {
        return response({
          'members': [
            member(actorId, 'مدیر آزمایشی', admin: true),
          ]
        });
      }
      if (request.url.path.endsWith('/invitations')) {
        return response({'invitations': [], 'nextCursor': null, 'total': 0});
      }
      return response(
          family(name: renamed ? 'نام تازه سرور' : 'خانواده آزمایشی'));
    });
    await tester.pumpWidget(
        MaterialApp(home: FamilyManagementPage(api: api, familyId: familyId)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'نام تازه سرور');
    await tester.tap(find.text('ذخیره نام خانواده'));
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.text('نام تازه سرور'), findsWidgets);
    expect(find.textContaining('نتیجه عملیات ممکن است نامشخص باشد'),
        findsOneWidget);
    expect(await OfflineStore.forApi(api).readQueue(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
