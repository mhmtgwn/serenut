import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/repository_providers.dart';

class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  GlobalSearchResult? _result;
  bool _isLoading = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _result = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final repo = ref.read(globalSearchRepositoryProvider);
      final results = await repo.searchAll(query);
      setState(() {
        _result = results;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Arama sırasında hata oluştu: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const kGreen = Color(0xFF10B981);
    const kTextPrimary = Color(0xFF1E293B);
    const kTextSecondary = Color(0xFF64748B);
    const kBorderColor = Color(0xFFE2E8F0);
    const kBgColor = Color(0xFFFAFAFC);

    final customers = _result?.customers ?? [];
    final products = _result?.products ?? [];
    final sales = _result?.sales ?? [];
    final transactions = _result?.transactions ?? [];

    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(fontSize: 15, color: kTextPrimary),
          decoration: InputDecoration(
            hintText: 'Müşteri, ürün, satış veya işlem ara...',
            hintStyle: const TextStyle(color: kTextSecondary),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: kTextSecondary),
                    onPressed: () {
                      _searchController.clear();
                      _performSearch('');
                    },
                  )
                : null,
          ),
          onChanged: (val) {
            _performSearch(val);
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: kGreen),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: kGreen,
          unselectedLabelColor: kTextSecondary,
          indicatorColor: kGreen,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: [
            Tab(text: 'Ürünler (${products.length})'),
            Tab(text: 'Müşteriler (${customers.length})'),
            Tab(text: 'Satışlar (${sales.length})'),
            Tab(text: 'İşlemler (${transactions.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(kGreen)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProductList(products, kTextPrimary, kTextSecondary, kBorderColor),
                _buildCustomerList(customers, kTextPrimary, kTextSecondary, kBorderColor),
                _buildSaleList(sales, kTextPrimary, kTextSecondary, kBorderColor),
                _buildTransactionList(transactions, kTextPrimary, kTextSecondary, kBorderColor),
              ],
            ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: Color(0xFF64748B), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildProductList(List<ProductEntity> list, Color textPrimary, Color textSecondary, Color borderColor) {
    if (_searchController.text.isEmpty) {
      return _buildEmptyState('Arama yapmak için bir şeyler yazın.');
    }
    if (list.isEmpty) {
      return _buildEmptyState('Eşleşen ürün bulunamadı.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final product = list[index];
        return Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(product.name, style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Kategori: ${product.category}', style: TextStyle(color: textSecondary, fontSize: 12)),
                if (product.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(product.description, style: TextStyle(color: textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${product.price.toStringAsFixed(2)} TL', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                const SizedBox(height: 4),
                Text('Stok: ${product.quantity}', style: TextStyle(color: product.quantity <= 0 ? Colors.red : textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            onTap: () {
              context.pushNamed(
                'productEdit',
                pathParameters: {'id': product.id},
                extra: product,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCustomerList(List<CustomerEntity> list, Color textPrimary, Color textSecondary, Color borderColor) {
    if (_searchController.text.isEmpty) {
      return _buildEmptyState('Arama yapmak için bir şeyler yazın.');
    }
    if (list.isEmpty) {
      return _buildEmptyState('Eşleşen müşteri bulunamadı.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final customer = list[index];
        final isDebt = customer.balance < 0;
        return Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: isDebt ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5),
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.bold, color: isDebt ? Colors.red : const Color(0xFF047857)),
              ),
            ),
            title: Text(customer.name, style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
            subtitle: customer.phone.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(customer.phone, style: TextStyle(color: textSecondary, fontSize: 12)),
                  )
                : null,
            trailing: Text(
              '${customer.balance.toStringAsFixed(2)} TL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDebt ? Colors.red : const Color(0xFF047857),
              ),
            ),
            onTap: () {
              context.push('/customers/detail/${customer.id}');
            },
          ),
        );
      },
    );
  }

  Widget _buildSaleList(List<SaleEntity> list, Color textPrimary, Color textSecondary, Color borderColor) {
    if (_searchController.text.isEmpty) {
      return _buildEmptyState('Arama yapmak için bir şeyler yazın.');
    }
    if (list.isEmpty) {
      return _buildEmptyState('Eşleşen satış bulunamadı.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final sale = list[index];
        return Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text('Satış ID: ${sale.id.substring(0, 8)}...', style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Ödeme: ${sale.paymentMethod}', style: TextStyle(color: textSecondary, fontSize: 12)),
                Text('Durum: ${sale.status}', style: TextStyle(color: sale.status == 'cancelled' ? Colors.red : Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: Text(
              '${sale.totalAmount.toStringAsFixed(2)} TL',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            onTap: () {
              context.push('/sales/detail/${sale.id}');
            },
          ),
        );
      },
    );
  }

  Widget _buildTransactionList(List<FinancialTransactionEntity> list, Color textPrimary, Color textSecondary, Color borderColor) {
    if (_searchController.text.isEmpty) {
      return _buildEmptyState('Arama yapmak için bir şeyler yazın.');
    }
    if (list.isEmpty) {
      return _buildEmptyState('Eşleşen finansal işlem bulunamadı.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final tx = list[index];
        final isDebt = tx.type == 'sale';
        return Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Text(
              tx.type == 'sale'
                  ? 'Veresiye Satış'
                  : tx.type == 'payment'
                      ? 'Tahsilat'
                      : tx.type == 'refund'
                          ? 'İade'
                          : 'İşlem: ${tx.type}',
              style: TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (tx.referenceId != null && tx.referenceId!.isNotEmpty)
                  Text('Ref: ${tx.referenceId}', style: TextStyle(color: textSecondary, fontSize: 12)),
                Text('Tarih: ${tx.date}', style: TextStyle(color: textSecondary, fontSize: 11)),
              ],
            ),
            trailing: Text(
              tx.type == 'sale'
                  ? '-${tx.debtAmount.toStringAsFixed(2)} TL'
                  : '+${tx.paidAmount.toStringAsFixed(2)} TL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDebt ? Colors.red : const Color(0xFF047857),
              ),
            ),
            onTap: () {
              context.push('/customers/detail/${tx.customerId}');
            },
          ),
        );
      },
    );
  }
}
