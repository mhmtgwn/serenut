// lib/domain/services/customer_search_service.dart
import 'dart:async';
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

class CustomerSearchResult {
  final List<CustomerEntity> items;
  final int page;
  final bool hasMore;
  final int requestId;

  CustomerSearchResult({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.requestId,
  });
}

class CustomerSearchService {
  final ICustomerRepository _repository;
  
  // Track current active request generation to prevent out-of-order async race conditions
  int _currentRequestId = 0;

  CustomerSearchService(this._repository);

  String normalizeQuery(String query) {
    return query.normalizeTurkish;
  }

  Future<CustomerSearchResult> searchCustomers({
    required String query,
    required int page,
    required int limit,
    int? expectedRequestId,
    String? companyScope,
  }) async {
    final reqId = expectedRequestId ?? ++_currentRequestId;
    final offset = page * limit;

    final normalized = normalizeQuery(query);

    // Call high performance database filtered query
    final results = await _repository.findFiltered(
      searchQuery: normalized,
      limit: limit,
      offset: offset,
    );

    return CustomerSearchResult(
      items: results,
      page: page,
      hasMore: results.length == limit,
      requestId: reqId,
    );
  }

  int get nextRequestId => ++_currentRequestId;
  int get currentRequestId => _currentRequestId;
}
