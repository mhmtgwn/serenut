// core_next/client_core/lib/infrastructure/sync/sync_v4_pull_worker.dart

import 'dart:async';
import '../../domain/models/sync_dtos.dart';
import 'sync_v4_http_client.dart';
import 'sync_v4_pull_ingestion_service.dart';

/// Tek bir pull sayfası (batch) işleme sonucu
class PullBatchResult {
  final bool isSuccess;
  final int cursorBefore;
  final int cursorAfter;
  final int changesFetched;
  final int productsApplied;
  final int customersApplied;
  final int salesApplied;
  final int refundsApplied;
  final bool hasMore;
  final String? error;
  final bool isPermanentError;

  const PullBatchResult({
    required this.isSuccess,
    this.cursorBefore = 0,
    this.cursorAfter = 0,
    this.changesFetched = 0,
    this.productsApplied = 0,
    this.customersApplied = 0,
    this.salesApplied = 0,
    this.refundsApplied = 0,
    this.hasMore = false,
    this.error,
    this.isPermanentError = false,
  });

  factory PullBatchResult.success({
    required int cursorBefore,
    required int cursorAfter,
    required int changesFetched,
    required PullIngestionResult ingestionResult,
    required bool hasMore,
  }) {
    return PullBatchResult(
      isSuccess: true,
      cursorBefore: cursorBefore,
      cursorAfter: cursorAfter,
      changesFetched: changesFetched,
      productsApplied: ingestionResult.productsApplied,
      customersApplied: ingestionResult.customersApplied,
      salesApplied: ingestionResult.salesApplied,
      refundsApplied: ingestionResult.refundsApplied,
      hasMore: hasMore,
    );
  }

  factory PullBatchResult.failure({
    required int currentCursor,
    required String error,
    required bool isPermanent,
  }) {
    return PullBatchResult(
      isSuccess: false,
      cursorBefore: currentCursor,
      cursorAfter: currentCursor,
      error: error,
      isPermanentError: isPermanent,
    );
  }
}

/// Tüm pull döngüsü (sayfalı çekim) sonucu
class PullWorkerResult {
  final bool isSuccess;
  final int totalBatches;
  final int totalChanges;
  final int finalCursor;
  final bool hasMoreRemaining;
  final String? error;
  final bool isPermanentError;

  const PullWorkerResult({
    required this.isSuccess,
    this.totalBatches = 0,
    this.totalChanges = 0,
    this.finalCursor = 0,
    this.hasMoreRemaining = false,
    this.error,
    this.isPermanentError = false,
  });
}

/// Serenut OS Sync V4 Pull İşlem Yöneticisi (Worker).
/// 
/// `SyncV4HttpClient` ile `SyncV4PullIngestionService` arasındaki koordinasyonu sağlar:
/// 1. Sunucudan cursor tabanlı artımlı sayfaları çeker.
/// 2. Gelen sayfaları yerel veritabanına ACID transaction sınırında idempotent uygular.
/// 3. Cursor yalnızca sayfa başarıyla uygulandıktan sonra kalıcılaşır.
/// 4. Geçici ağ hatalarında kontrollü retry yapar; kalıcı kimlik/doğrulama hatalarında sonsuz döngüye girmez.
/// 5. Eşzamanlı iki worker çalışmasını engellemek için atomic concurrency kilidi barındırır.
class SyncV4PullWorker {
  final SyncV4HttpClient httpClient;
  final SyncV4PullIngestionService ingestionService;
  final int pageSize;
  final int maxRetries;
  final Duration retryDelay;

  bool _isRunning = false;

  /// Worker'ın şu anda aktif bir döngüde çalışıp çalışmadığı
  bool get isRunning => _isRunning;

  SyncV4PullWorker({
    required this.httpClient,
    required this.ingestionService,
    this.pageSize = 200,
    this.maxRetries = 3,
    this.retryDelay = const Duration(milliseconds: 50),
  }) {
    if (pageSize <= 0 || pageSize > 500) {
      throw ArgumentError('pageSize 1 ile 500 arasında olmalıdır (Sunucu sınırı: 500).');
    }
  }

  /// Hatanın geçici (retry edilebilir) olup olmadığını belirler
  static bool isRetryableError(Object error) {
    if (error is SyncNetworkException ||
        error is SyncTimeoutException ||
        error is SyncServerException) {
      return true;
    }
    return false;
  }

  /// İlk kurulum / boş veritabanı için bootstrap snapshot indirmesini yürütür.
  Future<PullBatchResult> bootstrap() async {
    if (_isRunning) {
      throw StateError('pull_worker_busy');
    }
    _isRunning = true;
    try {
      SyncBootstrapResponseDto? dto;
      int attempts = 0;

      while (attempts <= maxRetries) {
        try {
          dto = await httpClient.bootstrap();
          break;
        } catch (e) {
          if (!isRetryableError(e) || attempts >= maxRetries) {
            return PullBatchResult.failure(
              currentCursor: 0,
              error: e.toString(),
              isPermanent: !isRetryableError(e),
            );
          }
          attempts++;
          if (retryDelay > Duration.zero) {
            await Future.delayed(retryDelay);
          }
        }
      }

      if (dto == null) {
        return PullBatchResult.failure(
          currentCursor: 0,
          error: 'Bootstrap DTO alınamadı.',
          isPermanent: false,
        );
      }

      final ingestionResult = await ingestionService.ingestBootstrap(dto);
      final finalCursor = await ingestionService.getSavedCursor();

      return PullBatchResult.success(
        cursorBefore: 0,
        cursorAfter: finalCursor,
        changesFetched: dto.changes.length,
        ingestionResult: ingestionResult,
        hasMore: false,
      );
    } catch (e) {
      return PullBatchResult.failure(
        currentCursor: 0,
        error: e.toString(),
        isPermanent: true,
      );
    } finally {
      _isRunning = false;
    }
  }

  /// Tek bir artımlı pull sayfasını çeker ve uygular.
  Future<PullBatchResult> pullSingleBatch({int? cursorOverride}) async {
    final currentCursor = cursorOverride ?? await ingestionService.getSavedCursor();
    SyncPullResponseDto? dto;
    int attempts = 0;

    while (attempts <= maxRetries) {
      try {
        dto = await httpClient.pull(cursor: currentCursor, limit: pageSize);
        break;
      } catch (e) {
        if (!isRetryableError(e) || attempts >= maxRetries) {
          return PullBatchResult.failure(
            currentCursor: currentCursor,
            error: e.toString(),
            isPermanent: !isRetryableError(e),
          );
        }
        attempts++;
        if (retryDelay > Duration.zero) {
          await Future.delayed(retryDelay);
        }
      }
    }

    if (dto == null) {
      return PullBatchResult.failure(
        currentCursor: currentCursor,
        error: 'Pull yanıtı alınamadı.',
        isPermanent: false,
      );
    }

    try {
      final ingestionResult = await ingestionService.ingestPull(dto);
      final cursorAfter = await ingestionService.getSavedCursor();

      // Sunucudan tam olarak pageSize kadar kayıt geldiyse ve kayıt sayısı > 0 ise devamı olabilir
      final hasMore = dto.changes.length >= pageSize && dto.changes.isNotEmpty;

      return PullBatchResult.success(
        cursorBefore: currentCursor,
        cursorAfter: cursorAfter,
        changesFetched: dto.changes.length,
        ingestionResult: ingestionResult,
        hasMore: hasMore,
      );
    } on StateError catch (e) {
      // unidentified_local_device gibi kalıcı fail-safe hataları
      return PullBatchResult.failure(
        currentCursor: currentCursor,
        error: e.message,
        isPermanent: true,
      );
    } catch (e) {
      return PullBatchResult.failure(
        currentCursor: currentCursor,
        error: e.toString(),
        isPermanent: false,
      );
    }
  }

  /// Tüm sayfaları sırayla tüketerek güncel duruma kadar çeker (Pagination Loop).
  Future<PullWorkerResult> pullAll({int maxPages = 50}) async {
    if (_isRunning) {
      throw StateError('pull_worker_busy');
    }
    _isRunning = true;

    int totalBatches = 0;
    int totalChanges = 0;
    int lastCursor = await ingestionService.getSavedCursor();

    try {
      int pages = 0;
      bool hasMore = true;

      while (pages < maxPages && hasMore) {
        final batch = await pullSingleBatch();
        if (!batch.isSuccess) {
          return PullWorkerResult(
            isSuccess: false,
            totalBatches: totalBatches,
            totalChanges: totalChanges,
            finalCursor: lastCursor,
            hasMoreRemaining: true,
            error: batch.error,
            isPermanentError: batch.isPermanentError,
          );
        }

        totalBatches++;
        totalChanges += batch.changesFetched;
        lastCursor = batch.cursorAfter;
        hasMore = batch.hasMore;
        pages++;

        // Sayfa boşsa veya limitin altındaysa son sayfaya ulaşılmıştır
        if (!hasMore || batch.changesFetched == 0) {
          break;
        }
      }

      return PullWorkerResult(
        isSuccess: true,
        totalBatches: totalBatches,
        totalChanges: totalChanges,
        finalCursor: lastCursor,
        hasMoreRemaining: hasMore,
      );
    } finally {
      _isRunning = false;
    }
  }
}
