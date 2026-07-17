import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../model/InoviceConfirmModel.dart';
import '../service/mainapi.dart';

/// Result returned when this screen is popped.
class ReviewScreenResult {
  final bool? isCommitted; // true=confirmed, false=cancelled, null=X
  const ReviewScreenResult(this.isCommitted);
}

/// Full-screen "Review AI Extracted Data" — replaces the old showDialog
/// so keyboard interactions are smooth and there are no slow overlay anims.
class ExtractedReviewScreen extends ConsumerStatefulWidget {
  final InvoiceConfirmUploadResponse confirmResponse;
  final InvoiceApiService api;
  final List<Map<String, dynamic>> categories;

  const ExtractedReviewScreen({
    super.key,
    required this.confirmResponse,
    required this.api,
    required this.categories,
  });

  @override
  ConsumerState<ExtractedReviewScreen> createState() =>
      _ExtractedReviewScreenState();
}

class _ExtractedReviewScreenState extends ConsumerState<ExtractedReviewScreen> {
  // ── App colours (matching rest of the app) ──────────────────
  static const Color kNavy = Color(0xFF192155);
  static const Color kNavySoft = Color(0xFF2E3A78);
  static const Color kBg = Color(0xFFF7F8FC);
  static const Color kBorder = Color(0xFFE3E5EE);
  static const Color kMuted = Color(0xFF6B7280);

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _invoiceNumberController;
  late final TextEditingController _companyNameController;
  late final TextEditingController _invoiceDateController;
  late final TextEditingController _amountController;
  late final TextEditingController _invoicedToController;
  late final TextEditingController _remarkController;

  String? _selectedCategoryId;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final r = widget.confirmResponse;
    _invoiceNumberController = TextEditingController(
      text: r.aiData.invoiceNumber,
    );
    _companyNameController = TextEditingController(text: r.aiData.companyName);
    _invoiceDateController = TextEditingController(
      text: _formatDate(r.aiData.invoiceDate),
    );
    _amountController = TextEditingController(text: r.aiData.amount.toString());
    _invoicedToController = TextEditingController();
    _remarkController = TextEditingController();
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _companyNameController.dispose();
    _invoiceDateController.dispose();
    _amountController.dispose();
    _invoicedToController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _formatDate(String date) {
    try {
      final d = DateTime.parse(date);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      final now = DateTime.now();
      return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
  }

  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: kMuted,
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
      floatingLabelStyle: const TextStyle(
        color: kNavy,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      prefixIcon: icon != null ? Icon(icon, size: 19, color: kNavySoft) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kNavy, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.9,
        color: kNavySoft,
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────

  void _cancel() {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(const ReviewScreenResult(false));
  }

  Future<void> _confirm() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final uploadedFileIds =
          widget.confirmResponse.uploadedFiles.map((f) => f.id).toList();

      if (uploadedFileIds.isNotEmpty) {
        final aiData = {
          'company_name': _companyNameController.text,
          'invoice_number': _invoiceNumberController.text,
          'amount': double.tryParse(_amountController.text) ?? 0.0,
          'date': _invoiceDateController.text,
          'remarks': _remarkController.text,
          'invoiced_to': _invoicedToController.text,
          'line_items':
              widget.confirmResponse.aiData.lineItems
                  .map((i) => i.toJson())
                  .toList(),
        };
        await widget.api.commitInvoice(
          categoryId: _selectedCategoryId ?? '',
          aiData: aiData,
          uploadedFileIds: uploadedFileIds,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(const ReviewScreenResult(true));
    } catch (e) {
      debugPrint('Commit Error: $e');
      if (!mounted) return;
      Navigator.of(context).pop(const ReviewScreenResult(true));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: kNavy,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: kBg,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    30,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAiBanner(),
                      const SizedBox(height: 24),

                      // Company Details
                      _sectionLabel('Company Details'),
                      const SizedBox(height: 12),
                      _buildCompanyDropdown(),
                      const SizedBox(height: 14),
                      _buildCategoryDropdown(),
                      const SizedBox(height: 26),

                      // Invoice Information
                      _sectionLabel('Invoice Information'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _invoiceNumberController,
                        decoration: _inputDecoration(
                          'Invoice Number',
                          icon: Icons.confirmation_number_outlined,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _companyNameController,
                        decoration: _inputDecoration(
                          'Company Name',
                          icon: Icons.business_rounded,
                        ),
                        validator:
                            (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Please enter a company name'
                                    : null,
                      ),
                      const SizedBox(height: 14),
                      _buildDateField(),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _inputDecoration(
                          'Amount',
                          icon: Icons.currency_rupee_rounded,
                        ),
                      ),
                      const SizedBox(height: 26),

                      // Additional Notes
                      _sectionLabel('Additional Notes'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _remarkController,
                        maxLines: 3,
                        decoration: _inputDecoration(
                          'Remark',
                          icon: Icons.sticky_note_2_outlined,
                        ),
                        validator:
                            (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Please enter a remark'
                                    : null,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kNavy, kNavySoft],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Back button
              Material(
                color: Colors.white.withOpacity(0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _cancel,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Review Extracted Data',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Confirm the details before saving',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // AI badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C5CFA), Color(0xFF4F46E5)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C5CFA).withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF192155).withOpacity(0.06),
            const Color(0xFF7C5CFA).withOpacity(0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF192155).withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7C5CFA), Color(0xFF4F46E5)],
              ),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Extracted Successfully',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: kNavy,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Review and edit the fields below before confirming.',
                  style: TextStyle(
                    fontSize: 12,
                    color: kMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF16A34A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF16A34A).withOpacity(0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 12,
                  color: Color(0xFF16A34A),
                ),
                SizedBox(width: 4),
                Text(
                  'Ready',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyDropdown() {
    return DropdownButtonFormField<String>(
      decoration: _inputDecoration(
        'Select Company',
        icon: Icons.apartment_rounded,
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kNavySoft),
      dropdownColor: Colors.white,
      value:
          _invoicedToController.text.isEmpty
              ? null
              : _invoicedToController.text,
      items:
          ['VRV', 'GRANULE AGRO']
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: kNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
      onChanged:
          (value) => setState(() => _invoicedToController.text = value ?? ''),
      validator: (v) => v == null ? 'Please select a company' : null,
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      decoration: _inputDecoration('Category', icon: Icons.category_rounded),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kNavySoft),
      dropdownColor: Colors.white,
      value: _selectedCategoryId,
      items:
          widget.categories
              .where((c) => c['name'] != null)
              .map(
                (category) => DropdownMenuItem<String>(
                  value: category['id']?.toString(),
                  child: Text(
                    category['name']!,
                    style: const TextStyle(
                      color: kNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
              .toList(),
      onChanged: (value) => setState(() => _selectedCategoryId = value),
      validator:
          (v) => (v == null || v.isEmpty) ? 'Please select a category' : null,
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _invoiceDateController,
      readOnly: true,
      decoration: _inputDecoration(
        'Invoice Date',
        icon: Icons.event_rounded,
      ).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today, color: kNavy, size: 19),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              builder:
                  (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: kNavy,
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        onSurface: kNavy,
                      ),
                    ),
                    child: child!,
                  ),
            );
            if (picked != null) {
              _invoiceDateController.text = _formatDate(
                picked.toIso8601String(),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: kBorder)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0C192155),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kMuted,
                    side: const BorderSide(color: kBorder, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _isSubmitting
                    ? Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [kNavy, kNavySoft],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                      )
                    : Material(
                        color: Colors.transparent,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [kNavy, kNavySoft],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: kNavy.withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: _confirm,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 50,
                              alignment: Alignment.center,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Confirm & Save',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
