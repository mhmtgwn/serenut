part of '../reports_page.dart';

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({required this.range});

  final DateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(topProductsProvider(range));
    final catalog = ref.watch(allProductsProvider);
    final catalogById = <String, ProductEntity>{
      for (final product in catalog.value ?? const <ProductEntity>[])
        product.id: product,
    };
    return ReportScrollView(
      onRefresh: () async {
        ref.invalidate(topProductsProvider(range));
        ref.invalidate(allProductsProvider);
      },
      children: [
        const ReportSectionHeader(
          eyebrow: 'Ürün performansı',
          title: 'En çok satan ürünler',
          subtitle: 'Seçili dönemde gelire göre ilk 10 ürün',
          icon: Icons.emoji_events_outlined,
        ),
        const SizedBox(height: 14),
        products.when(
          skipLoadingOnReload: true,
          data: (items) => items.isEmpty
              ? const ReportEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Henüz ürün verisi yok',
                  message: 'Seçili dönemde tamamlanmış satış bulunamadı.',
                )
              : _ProductRanking(items: items, catalogById: catalogById),
          loading: () => const ReportLoadingCard(height: 360),
          error: (error, _) => ReportErrorCard(
            message: 'Ürün performansı yüklenemedi.',
            onRetry: () => ref.invalidate(topProductsProvider(range)),
          ),
        ),
      ],
    );
  }
}

class _ProductRanking extends StatelessWidget {
  const _ProductRanking({required this.items, required this.catalogById});

  final List<ProductPerformance> items;
  final Map<String, ProductEntity> catalogById;

  @override
  Widget build(BuildContext context) {
    final maxRevenue = items.fold<double>(
      0,
      (current, item) => math.max(current, item.totalRevenue),
    );
    return ReportPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final product = catalogById[item.productId];
          final progress =
              maxRevenue == 0 ? 0.0 : item.totalRevenue / maxRevenue;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _RankedProductImage(
                      rank: item.rank,
                      productId: item.productId,
                      imageUrl: product?.imageUrl,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${formatReportCurrency(item.totalRevenue)} TL',
                                style: const TextStyle(
                                  color: POSColors.greenDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.categoryName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '${item.totalSold} adet',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 6,
                              backgroundColor: POSColors.surfaceMuted,
                              color: index == 0
                                  ? POSColors.amber
                                  : POSColors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (index != items.length - 1)
                const Divider(height: 1, indent: 64),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _RankedProductImage extends StatelessWidget {
  const _RankedProductImage({
    required this.rank,
    required this.productId,
    required this.imageUrl,
  });

  final int rank;
  final String productId;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final color = switch (rank) {
      1 => POSColors.amberDark,
      2 => POSColors.textSecondary,
      3 => POSColors.orange,
      _ => POSColors.green,
    };
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: ProductImage(
                imageUrl: imageUrl,
                barcode: productId,
                size: 52,
              ),
            ),
          ),
          Positioned(
            left: -4,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: POSColors.card, width: 2),
              ),
              child: Text(
                '$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

