import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/invoice_list_provider.dart';
import '../../service/listservice.dart';
import '../app_animations.dart';
import 'invoice_card.dart' as home;

class HomeInvoiceList extends ConsumerWidget {
  final ScrollController scrollController;
  final Set<String> reprocessingIds;
  final String? loadingPreviewId;
  final ValueChanged<String?> onLoadingPreviewIdChanged;
  final void Function(Set<String> reprocessingIds) onReprocessingIdsChanged;
  final Future<void> Function(List<String> publicUrls) onOpenPreview;

  const HomeInvoiceList({
    super.key,
    required this.scrollController,
    required this.reprocessingIds,
    required this.loadingPreviewId,
    required this.onLoadingPreviewIdChanged,
    required this.onReprocessingIdsChanged,
    required this.onOpenPreview,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listState = ref.watch(invoiceListProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child:
          listState.isLoading
              ? const Center(
                key: ValueKey('inv_loading'),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFF1E88E5),
                  ),
                ),
              )
              : listState.invoices.isEmpty
              ? FadeSlideIn(
                key: const ValueKey('inv_empty'),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No invoices found',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Upload your first invoice to get started',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              : ListView.builder(
                key: const ValueKey('inv_list'),
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                itemCount:
                    listState.invoices.length +
                    (listState.isLoadingMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == listState.invoices.length &&
                      listState.isLoadingMore) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(
                            Color(0xFF1E88E5),
                          ),
                        ),
                      ),
                    );
                  }

                  final invoice = listState.invoices[index];
                  final uploadedFilesList =
                      invoice['uploaded_files'] as List? ?? [];
                  final publicUrls =
                      uploadedFilesList
                          .map((f) => (f as Map)['public_url'] as String)
                          .where((url) => url != null)
                          .toList();

                  return home.InvoiceCard(
                    key: ValueKey(invoice['id']),
                    invoice: invoice,
                    index: index,
                    isReprocessing: reprocessingIds.contains(invoice['id']),
                    onTap: () async {
                      if (loadingPreviewId != null) return;
                      if (publicUrls.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No preview available'),
                          ),
                        );
                        return;
                      }

                      onLoadingPreviewIdChanged(invoice['id']);
                      try {
                        await onOpenPreview(publicUrls);
                      } finally {
                        onLoadingPreviewIdChanged(null);
                      }
                    },
                    onReprocess:
                        () => _reprocessInvoice(
                          context,
                          ref,
                          invoice,
                          reprocessingIds,
                          onReprocessingIdsChanged,
                        ),
                  );
                },
              ),
    );
  }

  Future<void> _reprocessInvoice(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> invoice,
    Set<String> reprocessingIds,
    void Function(Set<String> reprocessingIds) onReprocessingIdsChanged,
  ) async {
    final invoiceId = invoice['id'];
    final updatedIds = Set<String>.from(reprocessingIds)..add(invoiceId);
    onReprocessingIdsChanged(updatedIds);

    try {
      final uploadedFiles = invoice['uploaded_files'];
      List<String> fileIds = [];
      if (uploadedFiles is List && uploadedFiles.isNotEmpty) {
        fileIds =
            uploadedFiles
                .map((f) => f['id']?.toString())
                .where((id) => id != null)
                .cast<String>()
                .toList();
      }
      print('🔄 Reprocessing invoice $invoiceId with file IDs: $fileIds');
      final result = await InvoiceListService().reprocessInvoice(
        id: invoiceId,
        uploadedFileIds: fileIds.isNotEmpty ? fileIds : null,
      );
      print('✅ Reprocess result: $result');
      if (context.mounted) {
        ref
            .read(invoiceListProvider.notifier)
            .updateInvoiceAiStatus(invoiceId, 'AI_PROCESSING');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invoice reprocessing started successfully'),
            backgroundColor: Colors.green.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ AI Reprocess Error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'AI Processing Failed: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (context.mounted) {
        final clearedIds = Set<String>.from(updatedIds)..remove(invoiceId);
        onReprocessingIdsChanged(clearedIds);
      }
    }
  }
}
