// lib/infrastructure/services/central_background_scheduler.dart
// Serenut OS — Central Background Scheduler (Sprint 4)

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

enum JobPriority { high, medium, low }

abstract class SchedulerJob {
  String get name;
  JobPriority get priority;
  Duration get interval;
  Future<void> execute();
}

class CentralBackgroundScheduler {
  final List<SchedulerJob> _jobs = [];
  final Map<String, DateTime> _lastRunTimes = {};
  final Map<String, int> _backoffFactors = {};

  Timer? _schedulerTimer;
  bool _isPaused = false;
  bool _isNetworkAvailable = true;
  double _batteryLevel = 100.0; // Fallback helper

  CentralBackgroundScheduler(SharedPreferences prefs);

  void registerJob(SchedulerJob job) {
    _jobs.add(job);
    _lastRunTimes[job.name] = DateTime.fromMillisecondsSinceEpoch(0);
    _backoffFactors[job.name] = 0;
  }

  void start() {
    _schedulerTimer?.cancel();
    _schedulerTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => tick());
  }

  void stop() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  void updateNetworkStatus(bool isConnected) {
    _isNetworkAvailable = isConnected;
  }

  void updateBatteryStatus(double batteryPct) {
    _batteryLevel = batteryPct;
  }

  /// Run diagnostics loop tick
  Future<void> tick() async {
    if (_isPaused) return;

    // Adjust job runtime check intervals if battery level is low (Power Saving Mode)
    final double batteryModifier = (_batteryLevel < 20.0) ? 5.0 : 1.0;
    final now = DateTime.now();

    // Sort jobs by priority (High priority runs first)
    final sortedJobs = List<SchedulerJob>.from(_jobs)
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));

    for (final job in sortedJobs) {
      final lastRun =
          _lastRunTimes[job.name] ?? DateTime.fromMillisecondsSinceEpoch(0);

      // Calculate active interval based on battery and exponential backoff
      final int backoffSeconds =
          _backoffFactors[job.name]! * 30; // 30s increment per fail
      final Duration activeInterval =
          (job.interval * batteryModifier) + Duration(seconds: backoffSeconds);

      if (now.difference(lastRun) >= activeInterval) {
        // Skip remote jobs if network is offline
        if (!_isNetworkAvailable && job.priority != JobPriority.high) {
          continue;
        }

        try {
          debugPrint('[Scheduler] Executing job: ${job.name}');
          await job.execute();

          // Reset backoff factor on success
          _lastRunTimes[job.name] = DateTime.now();
          _backoffFactors[job.name] = 0;
        } catch (e) {
          debugPrint('[Scheduler] Error executing job: ${job.name} - $e');
          // Increment exponential backoff up to max factor 10 (5 mins)
          if (_backoffFactors[job.name]! < 10) {
            _backoffFactors[job.name] = _backoffFactors[job.name]! + 1;
          }
        }
      }
    }
  }

  @visibleForTesting
  Map<String, int> get backoffFactors => _backoffFactors;

  @visibleForTesting
  Map<String, DateTime> get lastRunTimes => _lastRunTimes;
}
