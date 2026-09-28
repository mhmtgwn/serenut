// lib/presentation/controllers/end_of_day_controller.dart
// Kasa Sayımı & Gün Sonu — Riverpod Controller
// Created: 28 Sep 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/infrastructure/repositories/end_of_day_repository.dart';
import 'package:serenutos/providers/database_provider.dart';

// ── Repository Provider ──────────────────────────────────────
final endOfDayRepositoryProvider = Provider<EndOfDayRepository>((ref) {
  return EndOfDayRepository(ref.watch(dbGatewayProvider));
});

// ── Report Provider (tarih bazlı) ────────────────────────────
final endOfDayReportProvider =
    FutureProvider.family<EndOfDayReport, DateTime>((ref, date) async {
  final repo = ref.watch(endOfDayRepositoryProvider);
  return repo.getReport(date);
});

// ── Actions Provider ─────────────────────────────────────────
class EndOfDayActions {
  final Ref _ref;
  EndOfDayActions(this._ref);

  EndOfDayRepository get _repo => _ref.read(endOfDayRepositoryProvider);

  Future<void> addExpense({
    required DateTime date,
    required double amount,
    required String category,
    required String description,
  }) async {
    await _repo.addCashExpense(
      amount: amount,
      category: category,
      description: description,
      date: date,
    );
    _ref.invalidate(endOfDayReportProvider(date));
  }

  Future<void> deleteExpense({
    required DateTime date,
    required String expenseId,
  }) async {
    await _repo.deleteCashExpense(expenseId);
    _ref.invalidate(endOfDayReportProvider(date));
  }

  Future<void> saveCount({
    required DateTime date,
    required double openingBalance,
    required double countedCash,
    required double expectedCash,
    String? notes,
  }) async {
    final dayStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await _repo.saveCashCount(
      date: dayStr,
      openingBalance: openingBalance,
      countedCash: countedCash,
      expectedCash: expectedCash,
      notes: notes,
    );
    _ref.invalidate(endOfDayReportProvider(date));
  }
}

final endOfDayActionsProvider = Provider<EndOfDayActions>((ref) {
  return EndOfDayActions(ref);
});
