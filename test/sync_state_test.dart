import 'package:depot_telur_36/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncState', () {
    test('defaults and copyWith clearError behavior', () {
      const initial = SyncState();
      expect(initial.isOnline, isFalse);
      expect(initial.isSyncing, isFalse);
      expect(initial.pendingCount, 0);
      expect(initial.lastSyncedAt, isNull);
      expect(initial.lastError, isNull);

      final now = DateTime(2026, 2, 16, 10, 30);
      final withError = initial.copyWith(
        isOnline: true,
        isSyncing: true,
        pendingCount: 3,
        lastSyncedAt: now,
        lastError: 'Koneksi terputus',
      );
      expect(withError.isOnline, isTrue);
      expect(withError.isSyncing, isTrue);
      expect(withError.pendingCount, 3);
      expect(withError.lastSyncedAt, now);
      expect(withError.lastError, 'Koneksi terputus');

      final cleared = withError.copyWith(
        isSyncing: false,
        pendingCount: 0,
        clearError: true,
      );
      expect(cleared.isOnline, isTrue);
      expect(cleared.isSyncing, isFalse);
      expect(cleared.pendingCount, 0);
      expect(cleared.lastError, isNull);
    });
  });
}
