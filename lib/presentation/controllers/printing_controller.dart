// lib/presentation/controllers/printing_controller.dart
// Serenut OS — Printing Controller (Phase 5 Layer Boundary)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/providers/printing_providers.dart';

final printingControllerProvider = Provider<PrintingController>((ref) {
  return PrintingController(ref);
});

class PrintingController {
  final Ref _ref;

  PrintingController(this._ref);

  PrintingRepository get _repository => _ref.read(printingRepositoryProvider);

  Future<List<PrintDesignProfile>> getDesignProfiles(PrintDocumentKind kind) {
    return _repository.getDesignProfiles(kind);
  }

  Future<void> saveDesignProfile(PrintDesignProfile profile) async {
    await _repository.saveDesignProfile(profile);
    _ref.invalidate(printDesignProfilesProvider(profile.kind));
  }
}

