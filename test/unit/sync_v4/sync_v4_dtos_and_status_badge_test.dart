// test/unit/sync_v4/sync_v4_dtos_and_status_badge_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_dtos.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/presentation/widgets/sync_status_badge.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/auth_user.dart';

void main() {
  group('Sync V4 Typed DTOs', () {
    test('SyncPushResponseDto parses results, conflicts, and rejected entries',
        () {
      final json = {
        'results': [
          {'mutation_id': 'mut-1', 'revision': 42},
          // PostgreSQL BIGINT revisions may be encoded as JSON strings.
          {'mutation_id': 'mut-2', 'revision': '43'},
        ],
        'conflicts': [
          {
            'mutation_id': 'mut-c1',
            'entity_type': 'product',
            'entity_id': 'p-123',
            'server_revision': '55',
          }
        ],
        'rejected': [
          {'mutation_id': 'mut-r1', 'error': 'validation_failed'}
        ]
      };

      final dto = SyncPushResponseDto.fromJson(json);

      expect(dto.results.length, 2);
      expect(dto.results.first.mutationId, 'mut-1');
      expect(dto.results.first.revision, 42);

      expect(dto.conflicts.length, 1);
      final conflict = dto.conflicts.first;
      expect(conflict.mutationId, 'mut-c1');
      expect(conflict.entityType, 'product');
      expect(conflict.serverRevision, 55);

      final row = conflict.toDbRow();
      expect(row['mutation_id'], 'mut-c1');
      expect(row['server_revision'], 55);
      expect(row['detected_at'], isNotEmpty);

      expect(dto.rejected.length, 1);
      expect(dto.rejected.first.mutationId, 'mut-r1');
      expect(dto.rejected.first.error, 'validation_failed');
    });

    test('SyncPullResponseDto parses string payload and nested objects safely',
        () {
      final json = {
        'changes': [
          {
            'revision': '100',
            'mutation_id': 'pull-1',
            'device_id': 'dev-1',
            'entity_type': 'customer',
            'entity_id': 'cust-1',
            'operation': 'UPSERT',
            'payload': '{"name":"Ahmet Yılmaz","balance":150.0}',
            'created_at': '2026-10-08T18:00:00Z',
          }
        ],
        'next_cursor': 100,
      };

      final dto = SyncPullResponseDto.fromJson(json, 0);

      expect(dto.changes.length, 1);
      expect(dto.nextCursor, 100);
      final change = dto.changes.first;
      expect(change.entityType, 'customer');
      expect(change.payload['name'], 'Ahmet Yılmaz');
      expect(change.payload['balance'], 150.0);
    });
  });

  group('SyncState & Cashier UX Visibility', () {
    test(
        'SyncState pendingOutboxCount and userFriendlyError fields work correctly',
        () {
      const state = SyncState(
        status: SyncStatus.idle,
        pendingOutboxCount: 5,
        userFriendlyError: 'Sunucuya bağlanılamadı.',
      );

      expect(state.pendingOutboxCount, 5);
      expect(state.userFriendlyError, 'Sunucuya bağlanılamadı.');

      final updated = state.copyWith(
        status: SyncStatus.success,
        pendingOutboxCount: 0,
        clearError: true,
      );

      expect(updated.status, SyncStatus.success);
      expect(updated.pendingOutboxCount, 0);
      expect(updated.userFriendlyError, isNull);
    });

    testWidgets('SyncStatusBadge renders pending count and status chip',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncProvider.overrideWith((ref) => _FakeSyncNotifier(
                  const SyncState(
                    status: SyncStatus.idle,
                    pendingOutboxCount: 3,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SyncStatusBadge(compact: false),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('3 bekliyor'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_queue_rounded), findsOneWidget);
    });

    testWidgets('SyncStatusBadge in compact mode renders compact counter',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncProvider.overrideWith((ref) => _FakeSyncNotifier(
                  const SyncState(
                    status: SyncStatus.idle,
                    pendingOutboxCount: 7,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SyncStatusBadge(compact: true),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
    });
  });

  group('Product Repository Typed IDs', () {
    test('InMemoryProductRepository findProductById and empty input validation',
        () async {
      final repo = InMemoryProductRepository();
      final product = ProductEntity(
        id: '869000000001',
        name: 'Deneme Ürün',
        description: 'Açıklama',
        price: 25.50,
        quantity: 10,
        category: 'Gıda',
      );

      await repo.create(product);

      final found = await repo.findProductById('869000000001');
      expect(found, isNotNull);
      expect(found?.name, 'Deneme Ürün');

      final emptyResult = await repo.findProductById('   ');
      expect(emptyResult, isNull);
    });
  });
}

class _FakeSyncNotifier extends StateNotifier<SyncState>
    implements SyncNotifier {
  _FakeSyncNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
