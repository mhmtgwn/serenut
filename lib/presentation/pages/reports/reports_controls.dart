part of '../reports_page.dart';

class _ReportsTopBar extends StatelessWidget {
  const _ReportsTopBar({
    required this.compact,
    required this.range,
    required this.isExporting,
    required this.isOnline,
    required this.onExport,
  });

  final bool compact;
  final DateRange range;
  final bool isExporting;
  final bool isOnline;
  final ValueChanged<String> onExport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: POSColors.card,
        border: Border(bottom: BorderSide(color: POSColors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 24,
              vertical: compact ? 10 : 16,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Geri',
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: POSColors.greenLight,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: const Icon(
                    Icons.query_stats_rounded,
                    color: POSColors.greenDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Raporlar',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (!compact)
                        Text(
                          '${_rangeDescription(range)} işletme görünümü',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (!compact)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: _LiveDataBadge(),
                  ),
                if (isExporting)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  _ExportMenu(
                    compact: compact,
                    isOnline: isOnline,
                    onSelected: onExport,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDataBadge extends StatelessWidget {
  const _LiveDataBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: POSColors.greenLight,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: POSColors.green),
          SizedBox(width: 6),
          Text(
            'Güncel veri',
            style: TextStyle(
              color: POSColors.greenDark,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportMenu extends StatelessWidget {
  const _ExportMenu({
    required this.compact,
    required this.isOnline,
    required this.onSelected,
  });

  final bool compact;
  final bool isOnline;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Raporu dışa aktar',
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'sales',
          child: _ExportItem(
            icon: Icons.receipt_long_outlined,
            title: 'Satış raporu',
            format: 'Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'stock',
          child: _ExportItem(
            icon: Icons.inventory_2_outlined,
            title: 'Stok raporu',
            format: 'Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'end_of_day',
          child: _ExportItem(
            icon: Icons.today_outlined,
            title: 'Gün sonu raporu',
            format: 'Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'vat',
          child: _ExportItem(
            icon: Icons.percent_rounded,
            title: 'KDV matrah raporu',
            format: 'Excel',
          ),
        ),
        if (isOnline) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'cloud_sales',
            child: _ExportItem(
              icon: Icons.cloud_download_outlined,
              title: 'Bulut satış geçmişi',
              format: 'CSV',
            ),
          ),
          const PopupMenuItem(
            value: 'cloud_products',
            child: _ExportItem(
              icon: Icons.cloud_download_outlined,
              title: 'Bulut ürün analizi',
              format: 'CSV',
            ),
          ),
          const PopupMenuItem(
            value: 'cloud_debtors',
            child: _ExportItem(
              icon: Icons.cloud_download_outlined,
              title: 'Bulut alacak listesi',
              format: 'CSV',
            ),
          ),
        ],
      ],
      child: Container(
        height: 42,
        padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 14),
        decoration: BoxDecoration(
          color: POSColors.green,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18),
            if (!compact) ...[
              const SizedBox(width: 8),
              const Text(
                'Dışa aktar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportItem extends StatelessWidget {
  const _ExportItem({
    required this.icon,
    required this.title,
    required this.format,
  });

  final IconData icon;
  final String title;
  final String format;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: POSColors.green, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(title)),
        Text(
          format,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: POSColors.textDisabled,
              ),
        ),
      ],
    );
  }
}

class _ReportsControls extends StatelessWidget {
  const _ReportsControls({
    required this.compact,
    required this.selectedRange,
    required this.tabController,
    required this.onRangeSelected,
  });

  final bool compact;
  final DateRange selectedRange;
  final TabController tabController;
  final ValueChanged<DateRange> onRangeSelected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1440),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 24,
            compact ? 12 : 18,
            compact ? 12 : 24,
            0,
          ),
          child: Column(
            children: [
              _DateRangeSelector(
                selected: selectedRange,
                onSelected: onRangeSelected,
              ),
              SizedBox(height: compact ? 10 : 14),
              _ReportTabs(controller: tabController, compact: compact),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateRangeSelector extends StatelessWidget {
  const _DateRangeSelector({
    required this.selected,
    required this.onSelected,
  });

  final DateRange selected;
  final ValueChanged<DateRange> onSelected;

  @override
  Widget build(BuildContext context) {
    final presets = [
      DateRange.today(),
      DateRange.thisWeek(),
      DateRange.thisMonth(),
      DateRange.last3Months(),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: POSColors.card,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: POSColors.border),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.calendar_month_outlined,
              size: 19,
              color: POSColors.textSecondary,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: presets.map((range) {
                  final active = selected.preset == range.preset;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Material(
                      color: active ? POSColors.greenLight : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () => onSelected(range),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Text(
                            range.label,
                            style: TextStyle(
                              color: active
                                  ? POSColors.greenDark
                                  : POSColors.textSecondary,
                              fontSize: 12,
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _pickCustomRange(context),
            tooltip: 'Özel tarih aralığı',
            icon: Icon(
              selected.preset == DateRangePreset.custom
                  ? Icons.event_available_rounded
                  : Icons.tune_rounded,
              size: 19,
            ),
            style: IconButton.styleFrom(
              foregroundColor: selected.preset == DateRangePreset.custom
                  ? POSColors.green
                  : POSColors.textSecondary,
              backgroundColor: selected.preset == DateRangePreset.custom
                  ? POSColors.greenLight
                  : POSColors.surfaceMuted,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: DateTimeRange(start: selected.from, end: selected.to),
      helpText: 'RAPOR DÖNEMİNİ SEÇİN',
      saveText: 'Uygula',
      cancelText: 'Vazgeç',
    );
    if (result != null) onSelected(DateRange.custom(result.start, result.end));
  }
}

class _ReportTabs extends StatelessWidget {
  const _ReportTabs({required this.controller, required this.compact});

  final TabController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: POSColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: TabBar(
        controller: controller,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: POSColors.text,
        unselectedLabelColor: POSColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        indicator: BoxDecoration(
          color: POSColors.card,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: POSColors.border),
          boxShadow: const [
            BoxShadow(
              color: POSColors.shadowColor,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        tabs: [
          _tab(Icons.point_of_sale_rounded, 'Satış'),
          _tab(Icons.inventory_2_outlined, 'Ürünler'),
          _tab(Icons.account_balance_wallet_outlined,
              compact ? 'Alacak' : 'Alacaklar'),
          _tab(Icons.insights_rounded, 'Analiz'),
        ],
      ),
    );
  }

  Tab _tab(IconData icon, String label) => Tab(
        height: 46,
        iconMargin: EdgeInsets.only(bottom: compact ? 2 : 0, right: 6),
        icon: Icon(icon, size: 18),
        text: label,
      );
}

