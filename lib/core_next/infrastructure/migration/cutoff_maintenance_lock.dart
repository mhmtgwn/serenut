// core_next/client_core/lib/infrastructure/migration/cutoff_maintenance_lock.dart
// SERENUT OS — STAGE 10.12.58
// CENTRAL CUTOFF LOCK, IN-FLIGHT TRANSACTION DRAINER & CHECKPOINT ARCHITECTURE

import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Faz durumu: Kesim kilidi ve bakım yaşam döngüsü
enum CutoffMaintenancePhase {
  idle,
  lockingRequested,
  draining,
  locked,
  releasing,
  error,
}

/// Kesim kilidi aktifken veya boşaltma sürerken yazma denendiğinde fırlatılan özel istisna
class CutoffMaintenanceActiveException implements Exception {
  final String message;
  final CutoffMaintenancePhase phase;
  final String? operation;
  final DateTime timestamp;

  CutoffMaintenanceActiveException(
    this.message, {
    required this.phase,
    this.operation,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'CutoffMaintenanceActiveException: [$phase] $message (operation: $operation, time: $timestamp)';
}

/// Kesim kilidi durum modeli
class CutoffMaintenanceState {
  final CutoffMaintenancePhase phase;
  final int activeWriteCount;
  final String? tenantId;
  final String? reason;
  final DateTime? lockAcquiredAt;
  final String? errorMessage;

  const CutoffMaintenanceState({
    this.phase = CutoffMaintenancePhase.idle,
    this.activeWriteCount = 0,
    this.tenantId,
    this.reason,
    this.lockAcquiredAt,
    this.errorMessage,
  });

  bool get isWritePermitted => phase == CutoffMaintenancePhase.idle;

  bool get isLockActive =>
      phase == CutoffMaintenancePhase.locked ||
      phase == CutoffMaintenancePhase.draining ||
      phase == CutoffMaintenancePhase.lockingRequested;

  String? get userFacingBanner {
    if (phase == CutoffMaintenancePhase.idle) return null;
    if (phase == CutoffMaintenancePhase.error) {
      return 'Sistem bakım kilidi hatası: $errorMessage. Lütfen destek ile iletişime geçiniz.';
    }
    return 'Sistem bakım ve veri güvenliği geçişi modunda. Yeni işlemler geçici olarak bekletilmektedir.';
  }

  CutoffMaintenanceState copyWith({
    CutoffMaintenancePhase? phase,
    int? activeWriteCount,
    String? tenantId,
    String? reason,
    DateTime? lockAcquiredAt,
    String? errorMessage,
  }) {
    return CutoffMaintenanceState(
      phase: phase ?? this.phase,
      activeWriteCount: activeWriteCount ?? this.activeWriteCount,
      tenantId: tenantId ?? this.tenantId,
      reason: reason ?? this.reason,
      lockAcquiredAt: lockAcquiredAt ?? this.lockAcquiredAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'activeWriteCount': activeWriteCount,
        'tenantId': tenantId,
        'reason': reason,
        'lockAcquiredAt': lockAcquiredAt?.toIso8601String(),
        'errorMessage': errorMessage,
      };

  factory CutoffMaintenanceState.fromJson(Map<String, dynamic> map) {
    return CutoffMaintenanceState(
      phase: CutoffMaintenancePhase.values.firstWhere(
        (e) => e.name == map['phase'],
        orElse: () => CutoffMaintenancePhase.idle,
      ),
      activeWriteCount: (map['activeWriteCount'] as num?)?.toInt() ?? 0,
      tenantId: map['tenantId'] as String?,
      reason: map['reason'] as String?,
      lockAcquiredAt: map['lockAcquiredAt'] != null
          ? DateTime.tryParse(map['lockAcquiredAt'].toString())
          : null,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

/// Kalıcılık arayüzü (Restart sonrasında durumun hatırlanması için)
abstract class IMaintenancePersistenceStorage {
  Future<void> saveState(CutoffMaintenanceState state);
  Future<CutoffMaintenanceState?> loadState();
  Future<void> clear();
}

/// SharedPreferences tabanlı kalıcı bakım durumu adaptörü (Fail-closed)
class SharedPreferencesMaintenanceStorage
    implements IMaintenancePersistenceStorage {
  static const String storageKey = 'serenut_cutoff_maintenance_state_v1';
  final Future<SharedPreferences> Function()? _prefsProvider;

  SharedPreferencesMaintenanceStorage([this._prefsProvider]);

  SharedPreferencesMaintenanceStorage.withInstance(SharedPreferences prefs)
      : _prefsProvider = (() async => prefs);

  Future<SharedPreferences> get _prefs async =>
      _prefsProvider != null ? await _prefsProvider!() : await SharedPreferences.getInstance();

  @override
  Future<void> saveState(CutoffMaintenanceState state) async {
    final prefs = await _prefs;
    final jsonStr = jsonEncode(state.toJson());
    await prefs.setString(storageKey, jsonStr);
  }

  @override
  Future<CutoffMaintenanceState?> loadState() async {
    try {
      final prefs = await _prefs;
      final jsonStr = prefs.getString(storageKey);
      if (jsonStr == null || jsonStr.trim().isEmpty) return null;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CutoffMaintenanceState.fromJson(map);
    } catch (e) {
      // Bozuk veya okunamayan veri durumunda fail-closed: Kilitli döndür
      return const CutoffMaintenanceState(
        phase: CutoffMaintenancePhase.locked,
        errorMessage: 'Kalıcı bakım durumu bozuk veya okunamadı. Güvenlik nedeniyle kilitli modda açıldı.',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      final prefs = await _prefs;
      await prefs.remove(storageKey);
    } catch (_) {
      // Retain or log
    }
  }
}

/// Bellek içi / mock kalıcılık depolama
class InMemoryMaintenancePersistenceStorage
    implements IMaintenancePersistenceStorage {
  CutoffMaintenanceState? _persisted;

  @override
  Future<void> saveState(CutoffMaintenanceState state) async {
    _persisted = state;
  }

  @override
  Future<CutoffMaintenanceState?> loadState() async {
    return _persisted;
  }

  @override
  Future<void> clear() async {
    _persisted = null;
  }
}

/// İşlem Tamamlama ve Boşaltıcı (In-Flight Transaction Drainer)
class InFlightTransactionDrainer {
  int _activeWrites = 0;
  Completer<void>? _drainCompleter;
  final Duration defaultTimeout;

  InFlightTransactionDrainer({
    this.defaultTimeout = const Duration(seconds: 15),
  });

  int get inFlightCount => _activeWrites;

  /// Aktif bir yazma işlemini kayıt altına alarak yürütür.
  Future<T> runTrackedWrite<T>({
    required String operationType,
    required String caller,
    required Future<T> Function() action,
    required bool Function() isWritePermitted,
    required CutoffMaintenancePhase Function() currentPhase,
  }) async {
    if (!isWritePermitted()) {
      throw CutoffMaintenanceActiveException(
        'Yazma işlemi reddedildi. Sistem bakım/geçiş modunda.',
        phase: currentPhase(),
        operation: '$caller:$operationType',
      );
    }

    _activeWrites++;
    try {
      final result = await action();
      return result;
    } finally {
      _activeWrites--;
      if (_activeWrites <= 0) {
        _activeWrites = 0;
        if (_drainCompleter != null && !_drainCompleter!.isCompleted) {
          _drainCompleter!.complete();
        }
      }
    }
  }

  /// Mevcut yazma işlemlerinin tamamlanmasını bekler.
  /// Zaman aşımına uğrarsa `false` döner.
  Future<bool> drain({Duration? timeout}) async {
    if (_activeWrites == 0) {
      return true;
    }

    _drainCompleter = Completer<void>();
    final waitDuration = timeout ?? defaultTimeout;

    try {
      await _drainCompleter!.future.timeout(waitDuration);
      return _activeWrites == 0;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  void reset() {
    _activeWrites = 0;
    _drainCompleter = null;
  }
}

/// Merkezi Kesim Kilidi (Cutoff Maintenance Lock)
class CutoffMaintenanceLock {
  final InFlightTransactionDrainer drainer;
  final IMaintenancePersistenceStorage storage;
  CutoffMaintenanceState _state = const CutoffMaintenanceState();

  final _stateStreamController =
      StreamController<CutoffMaintenanceState>.broadcast();

  CutoffMaintenanceLock({
    InFlightTransactionDrainer? drainer,
    IMaintenancePersistenceStorage? storage,
  })  : drainer = drainer ?? InFlightTransactionDrainer(),
        storage = storage ?? InMemoryMaintenancePersistenceStorage();

  CutoffMaintenanceState get state => _state.copyWith(
        activeWriteCount: drainer.inFlightCount,
      );

  Stream<CutoffMaintenanceState> get stateStream async* {
    yield state;
    yield* _stateStreamController.stream;
  }

  bool get isSafeForSnapshot =>
      _state.phase == CutoffMaintenancePhase.locked &&
      drainer.inFlightCount == 0;

  /// Başlangıçta kalıcı durumu denetler. Eğer kilitli kaldıysa (crash/reboot),
  /// güvenli fail-closed modda kilitli olarak başlatır.
  Future<void> initializeFromStorage() async {
    try {
      final persisted = await storage.loadState();
      if (persisted != null &&
          (persisted.phase == CutoffMaintenancePhase.locked ||
              persisted.phase == CutoffMaintenancePhase.draining ||
              persisted.phase == CutoffMaintenancePhase.lockingRequested ||
              persisted.phase == CutoffMaintenancePhase.error)) {
        _state = persisted.copyWith(
          phase: CutoffMaintenancePhase.locked,
          errorMessage: persisted.errorMessage ??
              'Önceki oturum kesim/bakım modundayken beklenmedik şekilde kapandı. Kilit aktif tutuldu.',
        );
        _notify();
      }
    } catch (e) {
      _state = CutoffMaintenanceState(
        phase: CutoffMaintenancePhase.locked,
        errorMessage: 'Kalıcı durum yüklenirken hata oluştu ($e). Güvenlik için kilitli başlatıldı.',
      );
      _notify();
    }
  }

  /// Yazma iznini kontrol eder. İzin yoksa istisna fırlatır.
  void assertWritePermitted({required String operation}) {
    if (!_state.isWritePermitted) {
      throw CutoffMaintenanceActiveException(
        'Merkezi kesim kilidi devrede. Veritabanına yazma engellendi.',
        phase: _state.phase,
        operation: operation,
      );
    }
  }

  /// Merkezi kilidi alır ve devam eden yazmaları boşaltır (Drain).
  /// Zaman aşımı veya boşaltılamayan işlem olursa kilidi serbest bırakmaz,
  /// fail-closed error fazına geçirerek `false` döner.
  Future<bool> acquireLock({
    required String tenantId,
    String reason = 'Cutover Catch-Up Reconciliation',
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_state.phase == CutoffMaintenancePhase.locked) {
      if (_state.tenantId != tenantId) {
        throw ArgumentError(
          'Kilit başka bir kiracı için aktif: ${_state.tenantId} != $tenantId',
        );
      }
      return true;
    }

    if (_state.phase == CutoffMaintenancePhase.lockingRequested ||
        _state.phase == CutoffMaintenancePhase.draining) {
      if (_state.tenantId != tenantId) {
        throw ArgumentError(
          'Kilit başka bir kiracı için talep ediliyor: ${_state.tenantId} != $tenantId',
        );
      }
      return await drainer.drain(timeout: timeout);
    }

    _state = _state.copyWith(
      phase: CutoffMaintenancePhase.lockingRequested,
      tenantId: tenantId,
      reason: reason,
    );
    _notify();

    // Yeni yazmaları durdurmak üzere draining fazına geç
    _state = _state.copyWith(phase: CutoffMaintenancePhase.draining);
    _notify();

    final drainedSuccessfully = await drainer.drain(timeout: timeout);
    if (!drainedSuccessfully) {
      _state = _state.copyWith(
        phase: CutoffMaintenancePhase.error,
        errorMessage: 'Devam eden işlemler boşaltılamadı (Drain timeout: $timeout). Geçiş durduruldu.',
      );
      await storage.saveState(_state);
      _notify();
      return false;
    }

    // Başarıyla boşaltıldı — Kilidi aktifleştir
    _state = _state.copyWith(
      phase: CutoffMaintenancePhase.locked,
      lockAcquiredAt: DateTime.now(),
      errorMessage: null,
    );
    await storage.saveState(_state);
    _notify();
    return true;
  }

  /// Kilidi kontrollü biçimde kaldırır ve normal moda döner.
  Future<void> releaseLock() async {
    if (_state.phase == CutoffMaintenancePhase.idle) return;

    _state = _state.copyWith(phase: CutoffMaintenancePhase.releasing);
    _notify();

    drainer.reset();
    _state = const CutoffMaintenanceState(phase: CutoffMaintenancePhase.idle);
    await storage.clear();
    _notify();
  }

  /// Acil durum sıfırlaması
  Future<void> forceReset() async {
    await releaseLock();
  }

  /// Acil durum ve hata koruması (Fail-Closed)
  void setFailClosedError([String? message]) {
    _state = _state.copyWith(
      phase: CutoffMaintenancePhase.error,
      errorMessage: message ?? 'Kritik bakım ve kilit hatası oluştu. Veri bütünlüğünü korumak için yazma işlemleri durduruldu (Fail-Closed).',
    );
    _notify();
  }

  void _notify() {
    _stateStreamController.add(state);
  }

  void dispose() {
    _stateStreamController.close();
  }
}

/// Kesim Noktası (Cutover Checkpoint) Modeli
class CutoverCheckpoint {
  final String tenantId;
  final String sourceDbId;
  final String targetDbId;
  final String snapshotId;
  final DateTime snapshotTimestamp;
  final int lastSequenceId;
  final String? reconciliationHash;
  final String status; // 'pending', 'in_progress', 'reconciled', 'committed', 'rolled_back', 'failed'
  final int version; // İyimser eşzamanlılık kilidi (Optimistic Concurrency)
  final String? failureReason;
  final int retryCount;

  const CutoverCheckpoint({
    required this.tenantId,
    required this.sourceDbId,
    required this.targetDbId,
    required this.snapshotId,
    required this.snapshotTimestamp,
    required this.lastSequenceId,
    this.reconciliationHash,
    required this.status,
    this.version = 1,
    this.failureReason,
    this.retryCount = 0,
  });

  CutoverCheckpoint copyWith({
    String? tenantId,
    String? sourceDbId,
    String? targetDbId,
    String? snapshotId,
    DateTime? snapshotTimestamp,
    int? lastSequenceId,
    String? reconciliationHash,
    String? status,
    int? version,
    String? failureReason,
    int? retryCount,
  }) {
    return CutoverCheckpoint(
      tenantId: tenantId ?? this.tenantId,
      sourceDbId: sourceDbId ?? this.sourceDbId,
      targetDbId: targetDbId ?? this.targetDbId,
      snapshotId: snapshotId ?? this.snapshotId,
      snapshotTimestamp: snapshotTimestamp ?? this.snapshotTimestamp,
      lastSequenceId: lastSequenceId ?? this.lastSequenceId,
      reconciliationHash: reconciliationHash ?? this.reconciliationHash,
      status: status ?? this.status,
      version: version ?? this.version,
      failureReason: failureReason ?? this.failureReason,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toMap() => {
        'tenant_id': tenantId,
        'source_db_id': sourceDbId,
        'target_db_id': targetDbId,
        'snapshot_id': snapshotId,
        'snapshot_timestamp': snapshotTimestamp.toIso8601String(),
        'last_sequence_id': lastSequenceId,
        'reconciliation_hash': reconciliationHash,
        'status': status,
        'version': version,
        'failure_reason': failureReason,
        'retry_count': retryCount,
      };

  factory CutoverCheckpoint.fromMap(Map<String, dynamic> map) {
    return CutoverCheckpoint(
      tenantId: map['tenant_id'] as String,
      sourceDbId: map['source_db_id'] as String,
      targetDbId: map['target_db_id'] as String,
      snapshotId: map['snapshot_id'] as String,
      snapshotTimestamp: DateTime.parse(map['snapshot_timestamp'].toString()),
      lastSequenceId: (map['last_sequence_id'] as num).toInt(),
      reconciliationHash: map['reconciliation_hash'] as String?,
      status: map['status'] as String,
      version: (map['version'] as num?)?.toInt() ?? 1,
      failureReason: map['failure_reason'] as String?,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Kesim Noktası Deposu Arayüzü
abstract class ICutoverCheckpointRepository {
  Future<CutoverCheckpoint?> getLatestCheckpoint(String tenantId);
  Future<void> saveCheckpoint(CutoverCheckpoint checkpoint);
  Future<bool> advanceCheckpoint(CutoverCheckpoint current, CutoverCheckpoint next);
}

/// İyileştirilmiş Bellek İçi Kesim Noktası Deposu (Test ve Mock için)
class InMemoryCutoverCheckpointRepository
    implements ICutoverCheckpointRepository {
  final Map<String, CutoverCheckpoint> _store = {};

  @override
  Future<CutoverCheckpoint?> getLatestCheckpoint(String tenantId) async {
    return _store[tenantId];
  }

  @override
  Future<void> saveCheckpoint(CutoverCheckpoint checkpoint) async {
    _store[checkpoint.tenantId] = checkpoint;
  }

  @override
  Future<bool> advanceCheckpoint(
    CutoverCheckpoint current,
    CutoverCheckpoint next,
  ) async {
    final existing = _store[current.tenantId];
    if (existing == null) {
      if (current.version != 1) return false;
      _store[current.tenantId] = next;
      return true;
    }

    if (existing.version != current.version) {
      // Sürüm uyuşmazlığı — Eşzamanlı çakışma (Optimistic Lock Failure)
      return false;
    }

    _store[current.tenantId] = next.copyWith(version: current.version + 1);
    return true;
  }
}

/// Yazma Yolu Güvenlik Sınıflandırması
enum WritePathSecurityLevel {
  lockProtected,
  partiallyProtected,
  unprotected,
  notVerifiable,
}

class WritePathAuditRecord {
  final String pathName;
  final String callChain;
  final WritePathSecurityLevel level;
  final String description;
  final String remediation;

  const WritePathAuditRecord({
    required this.pathName,
    required this.callChain,
    required this.level,
    required this.description,
    required this.remediation,
  });
}
