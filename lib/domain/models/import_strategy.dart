// lib/domain/models/import_strategy.dart

enum DuplicateResolution { skip, update, merge }

class ImportStrategy {
  final bool insertNew;
  final bool updateExisting;
  final bool syncStocks;
  final bool syncPrices;
  final bool syncDescriptions;
  final bool syncImages;
  final bool reactivatePassive;
  final bool deactivateMissing;
  final DuplicateResolution duplicateResolution;

  const ImportStrategy({
    this.insertNew = true,
    this.updateExisting = true,
    this.syncStocks = true,
    this.syncPrices = true,
    this.syncDescriptions = true,
    this.syncImages = true,
    this.reactivatePassive = true,
    this.deactivateMissing = false,
    this.duplicateResolution = DuplicateResolution.update,
  });
}
