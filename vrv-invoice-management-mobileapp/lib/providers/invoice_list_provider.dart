import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../service/listservice.dart';

class InvoiceListState {
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic>? selectedCategory;
  final String searchQuery;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int offset;
  final String? errorMessage;

  const InvoiceListState({
    this.invoices = const [],
    this.categories = const [],
    this.selectedCategory,
    this.searchQuery = '',
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.offset = 0,
    this.errorMessage,
  });

  InvoiceListState copyWith({
    List<Map<String, dynamic>>? invoices,
    List<Map<String, dynamic>>? categories,
    Map<String, dynamic>? selectedCategory,
    String? searchQuery,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? offset,
    String? errorMessage,
    bool clearSelectedCategory = false,
    bool clearErrorMessage = false,
  }) {
    return InvoiceListState(
      invoices: invoices ?? this.invoices,
      categories: categories ?? this.categories,
      selectedCategory:
          clearSelectedCategory
              ? null
              : (selectedCategory ?? this.selectedCategory),
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class InvoiceListNotifier extends Notifier<InvoiceListState> {
  static const int _limit = 10;
  final InvoiceListService _service = InvoiceListService();

  @override
  InvoiceListState build() {
    Future.microtask(_initialize);
    return const InvoiceListState();
  }

  Future<void> _initialize() async {
    await fetchCategories();
    await fetchInvoices();
  }

  Future<void> fetchCategories() async {
    try {
      final categories = await _service.fetchCategories();
      state = state.copyWith(
        categories: [
          {'id': null, 'name': 'All'},
          ...categories.map((c) => {'id': c['id'], 'name': c['name']}),
        ],
        selectedCategory:
            state.selectedCategory ??
            {'id': null, 'name': 'All'},
        clearErrorMessage: true,
      );
    } catch (e) {
      print('Failed to fetch categories: $e');
      state = state.copyWith(
        errorMessage: 'Failed to load categories: $e',
      );
    }
  }

  Future<void> fetchInvoices({String? search, String? categoryId}) async {
    state = state.copyWith(
      isLoading: true,
      offset: 0,
      invoices: const [],
      hasMore: true,
      searchQuery: search ?? '',
    );

    try {
      final invoices = await _service.fetchInvoices(
        search: search,
        category: categoryId,
        limit: _limit,
        offset: 0,
      );
      print('the invoice data: $invoices');
      print('Response type: ${invoices.runtimeType}');
      state = state.copyWith(
        invoices: invoices,
        offset: _limit,
        hasMore: invoices.length == _limit,
        isLoading: false,
      );
    } catch (e) {
      print('❌ Failed to load invoices :$e');
      state = state.copyWith(
        isLoading: false,
        errorMessage: '❌ Failed to load invoices',
      );
    }
  }

  Future<void> fetchMoreInvoices() async {
    if (!state.hasMore || state.isLoadingMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final invoices = await _service.fetchInvoices(
        search: state.searchQuery.isNotEmpty ? state.searchQuery : null,
        category: state.selectedCategory?['id']?.toString(),
        limit: _limit,
        offset: state.offset,
      );
      print('Fetched more invoices: $invoices');
      state = state.copyWith(
        invoices: [...state.invoices, ...invoices],
        offset: state.offset + _limit,
        hasMore: invoices.length == _limit,
        isLoadingMore: false,
      );
    } catch (e) {
      print('❌ Failed to load more invoices :$e');
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: '❌ Failed to load more invoices',
      );
    }
  }

  void clearErrorMessage() {
    state = state.copyWith(clearErrorMessage: true);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> selectCategory(Map<String, dynamic> category) async {
    state = state.copyWith(selectedCategory: category);
    await fetchInvoices(
      search: state.searchQuery.isNotEmpty ? state.searchQuery : null,
      categoryId: category['id']?.toString(),
    );
  }

  void updateInvoiceAiStatus(String invoiceId, String status) {
    final index = state.invoices.indexWhere((inv) => inv['id'] == invoiceId);
    if (index == -1) return;

    final updated = List<Map<String, dynamic>>.from(state.invoices);
    updated[index] = Map<String, dynamic>.from(updated[index])
      ..['ai_status'] = status;
    state = state.copyWith(invoices: updated);
  }

  Future<void> refreshAfterUpload() async {
    await fetchInvoices(
      search: state.searchQuery.isNotEmpty ? state.searchQuery : null,
      categoryId: state.selectedCategory?['id']?.toString(),
    );
  }
}

final invoiceListProvider =
    NotifierProvider<InvoiceListNotifier, InvoiceListState>(
      InvoiceListNotifier.new,
    );

final invoiceListServiceProvider = Provider<InvoiceListService>(
  (ref) => InvoiceListService(),
);
