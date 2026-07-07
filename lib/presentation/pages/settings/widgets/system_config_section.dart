part of '../../settings_page.dart';

// Extracted System Config Section sheets for SettingsPage
extension SettingsSystemConfigSheets on _SettingsPageState {
  void _showMarketSelectionSheet(BuildContext context, DatasetLoaderService datasetLoader) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, child) {
          final markets = ['Migros', 'CarrefourSA', 'A101', 'Şok', 'Mopaş', 'Metro'];
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Zeka Fiyat Karşılaştırma Pazarı',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                ),
                const SizedBox(height: 8),
                const Text(
                  'POS kataloğunda listelenecek karşılaştırma fiyatlarının çekileceği ana pazarı seçin.',
                  style: TextStyle(fontSize: 13, color: _kTextSecondary),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: markets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorderColor),
                    itemBuilder: (context, index) {
                      final m = markets[index];
                      final isSelected = datasetLoader.selectedMarket == m;
                      return ListTile(
                        onTap: () async {
                          await datasetLoader.setSelectedMarket(m);
                          ref.invalidate(productRepositoryProvider);
                          ref.invalidate(productsControllerProvider);
                          if (mounted) {
                            updateState(() {});
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Karşılaştırma pazarı $m olarak güncellendi.'),
                                backgroundColor: _kGreen,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        title: Text(
                          m,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? _kGreen : _kTextPrimary,
                          ),
                        ),
                        trailing: isSelected ? const Icon(Icons.check_rounded, color: _kGreen) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDatasetManagementSheet(BuildContext context, DatasetLoaderService datasetLoader) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, child) {
          return FutureBuilder<List<DatasetVersion>>(
            future: datasetLoader.getAvailableVersions(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 200,
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_kGreen),
                    ),
                  ),
                );
              }
              
              final versions = snapshot.data ?? [];
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Offline Veri Zekası Paketi Yönetimi',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _kTextPrimary),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Scraper tarafından indirilen ve paketlenen ürün katalog zeka versiyonları listelenmektedir.',
                      style: TextStyle(fontSize: 13, color: _kTextSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (versions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'Kayıtlı offline veri paketi bulunamadı.\nLütfen data pipeline üzerinden paket oluşturun.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _kTextSecondary, fontSize: 14),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: versions.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: _kBorderColor),
                          itemBuilder: (context, index) {
                            final v = versions[index];
                            final isActive = datasetLoader.activeVersion == v.version;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Row(
                                children: [
                                  Text(
                                    v.version,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isActive ? _kGreen : _kTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _kGreen.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Bütünlük: %${v.integrityScore.toStringAsFixed(0)}',
                                      style: const TextStyle(fontSize: 10, color: _kGreen, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                'Ürün: ${v.productCount} • Fiyat: ${v.priceCount}\nTarih: ${v.timestamp}',
                                style: const TextStyle(fontSize: 11, color: _kTextSecondary),
                              ),
                              trailing: isActive
                                  ? TextButton(
                                      onPressed: () async {
                                        await datasetLoader.unmountActiveVersion();
                                        ref.invalidate(productRepositoryProvider);
                                        ref.invalidate(productsControllerProvider);
                                        if (mounted) {
                                          updateState(() {});
                                          Navigator.pop(ctx);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Offline veri zekası paketi kaldırıldı. Yerel POS verisine dönüldü.'),
                                              backgroundColor: _kOrange,
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text('Kaldır', style: TextStyle(color: _kPink, fontWeight: FontWeight.bold)),
                                    )
                                  : ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _kGreen,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () async {
                                        final success = await datasetLoader.mountVersion(v.version);
                                        if (success) {
                                          ref.invalidate(productRepositoryProvider);
                                          ref.invalidate(productsControllerProvider);
                                          if (mounted) {
                                            updateState(() {});
                                            Navigator.pop(ctx);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Offline veri zekası paketi ${v.version} aktifleştirildi!'),
                                                backgroundColor: _kGreen,
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text('Aktifleştir'),
                                    ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
