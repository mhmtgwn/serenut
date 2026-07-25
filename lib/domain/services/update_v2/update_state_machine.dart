// lib/domain/services/update_v2/update_state_machine.dart
// Serenut Platform — Client-Side Deterministic Update State Machine

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:serenutos/domain/models/update_v2/update_context.dart';
import 'package:serenutos/domain/models/update_v2/update_telemetry_event.dart';
import 'package:serenutos/infrastructure/services/update_v2/update_event_bus.dart';

class InvalidStateTransitionException implements Exception {
  final UpdateState from;
  final UpdateState to;

  InvalidStateTransitionException(this.from, this.to);

  @override
  String toString() =>
      'InvalidStateTransitionException: Illegal state transition from ${from.name} to ${to.name}.';
}

class StateTimeoutException implements Exception {
  final UpdateState state;
  final Duration duration;

  StateTimeoutException(this.state, this.duration);

  @override
  String toString() =>
      'StateTimeoutException: State ${state.name} exceeded allowed timeout of ${duration.inSeconds} seconds.';
}

abstract class StateLifecycle {
  Future<void> entry(UpdateContext context);
  Future<void> execute(UpdateContext context);
  Future<void> exit(UpdateContext context);
}

class UpdateStateMachine {
  final UpdateEventBus _eventBus;
  final String _deviceId;

  UpdateStateMachine({
    required UpdateEventBus eventBus,
    required String deviceId,
  })  : _eventBus = eventBus,
        _deviceId = deviceId;

  // 1. Data-Driven State Transition Guards
  final Map<UpdateState, List<UpdateState>> _allowedTransitions = {
    UpdateState.idle: [UpdateState.checking],
    UpdateState.checking: [UpdateState.precheck, UpdateState.failed],
    UpdateState.precheck: [UpdateState.downloading, UpdateState.failed, UpdateState.idle],
    UpdateState.downloading: [UpdateState.verifying, UpdateState.failed, UpdateState.rollback],
    UpdateState.verifying: [UpdateState.draining, UpdateState.failed, UpdateState.rollback],
    UpdateState.draining: [UpdateState.handshake, UpdateState.failed, UpdateState.rollback],
    UpdateState.handshake: [UpdateState.postInstall, UpdateState.failed, UpdateState.rollback],
    UpdateState.postInstall: [UpdateState.healthCheck, UpdateState.failed, UpdateState.rollback],
    UpdateState.healthCheck: [UpdateState.completed, UpdateState.rollback, UpdateState.failed],
    UpdateState.completed: [UpdateState.idle],
    UpdateState.failed: [UpdateState.idle],
    UpdateState.rollback: [UpdateState.failed, UpdateState.idle],
  };

  // 2. State-Level Timeout Limits
  final Map<UpdateState, Duration> _stateTimeouts = {
    UpdateState.checking: const Duration(seconds: 30),
    UpdateState.precheck: const Duration(seconds: 30),
    UpdateState.downloading: const Duration(minutes: 30),
    UpdateState.verifying: const Duration(minutes: 2),
    UpdateState.draining: const Duration(seconds: 60),
    UpdateState.handshake: const Duration(seconds: 30),
    UpdateState.healthCheck: const Duration(minutes: 5),
  };

  // 3. State-Level Retry Limits
  final Map<UpdateState, int> _stateRetries = {
    UpdateState.checking: 3,
    UpdateState.downloading: 5,
    UpdateState.healthCheck: 2,
  };

  final Map<UpdateState, StateLifecycle> _stateActions = {};

  void registerStateLifecycle(UpdateState state, StateLifecycle lifecycle) {
    _stateActions[state] = lifecycle;
  }

  /// Triggers a state transition, executing exit/entry hooks and publishing events.
  Future<void> transitionTo(UpdateContext context, UpdateState targetState) async {
    final fromState = context.currentState;

    if (fromState == targetState) return;

    // A. Verify Transition Guard rules
    final allowed = _allowedTransitions[fromState] ?? [];
    if (!allowed.contains(targetState)) {
      throw InvalidStateTransitionException(fromState, targetState);
    }

    debugPrint('[FSM] Transitioning ${fromState.name} -> ${targetState.name} (Corr: ${context.correlationId})');

    // B. Run Exit Lifecycle of Current State
    if (_stateActions.containsKey(fromState)) {
      await _stateActions[fromState]!.exit(context);
    }

    // C. Execute the state change
    context.currentState = targetState;

    // D. Publish Telemetry Event via Event Bus
    _eventBus.publish(
      UpdateTelemetryEvent(
        schemaVersion: 1,
        correlationId: context.correlationId,
        deviceId: _deviceId,
        fromVersion: '1.1.9+21',
        toVersion: context.manifest?.version ?? '1.2.0+22',
        eventType: _mapStateToEventType(targetState),
        errorCode: context.errorCode,
        errorMessage: context.errorMessage,
        timestamp: DateTime.now().toIso8601String(),
      ),
    );

    // E. Run Entry Lifecycle of Target State
    if (_stateActions.containsKey(targetState)) {
      await _stateActions[targetState]!.entry(context);

      // F. Run Execution with Timeout & Retry management
      final timeoutDuration = _stateTimeouts[targetState];
      if (timeoutDuration != null) {
        try {
          await _executeWithTimeoutAndRetry(context, targetState, timeoutDuration);
        } catch (e) {
          debugPrint('[FSM] State execution exception in ${targetState.name}: $e');
          context.errorCode = 'UPD-005';
          context.errorMessage = e.toString();
          
          if (targetState == UpdateState.downloading ||
              targetState == UpdateState.verifying ||
              targetState == UpdateState.draining ||
              targetState == UpdateState.healthCheck) {
            await transitionTo(context, UpdateState.rollback);
          } else {
            await transitionTo(context, UpdateState.failed);
          }
        }
      } else {
        await _stateActions[targetState]!.execute(context);
      }
    }
  }

  Future<void> _executeWithTimeoutAndRetry(
    UpdateContext context,
    UpdateState state,
    Duration timeout,
  ) async {
    final maxRetries = _stateRetries[state] ?? 0;
    int attempt = 0;

    while (attempt <= maxRetries) {
      try {
        await _stateActions[state]!.execute(context).timeout(timeout, onTimeout: () {
          throw StateTimeoutException(state, timeout);
        });
        return; // Success
      } catch (e) {
        attempt++;
        if (attempt > maxRetries) {
          rethrow; // Reached limit, propagate error
        }
        debugPrint('[FSM] Retry triggered for state ${state.name} (Attempt $attempt/$maxRetries) due to: $e');
        context.retryCount = attempt;
      }
    }
  }

  UpdateEventType _mapStateToEventType(UpdateState state) {
    switch (state) {
      case UpdateState.checking:
        return UpdateEventType.checkStarted;
      case UpdateState.precheck:
        return UpdateEventType.precheckPassed;
      case UpdateState.downloading:
        return UpdateEventType.downloadStarted;
      case UpdateState.verifying:
        return UpdateEventType.manifestVerified;
      case UpdateState.draining:
        return UpdateEventType.drainStarted;
      case UpdateState.handshake:
        return UpdateEventType.bootstrapperLaunched;
      case UpdateState.postInstall:
        return UpdateEventType.postInstallStarted;
      case UpdateState.healthCheck:
        return UpdateEventType.healthCheckPassed;
      case UpdateState.completed:
        return UpdateEventType.installSuccess;
      case UpdateState.failed:
        return UpdateEventType.installFailed;
      case UpdateState.rollback:
        return UpdateEventType.rollbackExecuted;
      case UpdateState.idle:
        return UpdateEventType.checkStarted;
    }
  }
}
