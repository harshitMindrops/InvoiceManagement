import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../service/listservice.dart';
import 'package:dotted_border/dotted_border.dart';
import '../service/mainapi.dart';
import '../model/InoviceConfirmModel.dart';
import 'ai_processing.dart';
import 'send_otp.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:image/image.dart' as img;

class InvoiceManagementScreen extends StatefulWidget {
  const InvoiceManagementScreen({Key? key}) : super(key: key);

  @override
  State<InvoiceManagementScreen> createState() =>
      _InvoiceManagementScreenState();
}

class _InvoiceManagementScreenState extends State<InvoiceManagementScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedFile;
  List<File> _selectedImages = [];
  // List<dynamic> _invoices = [];
  List<Map<String, dynamic>> _invoices = [];
  Set<String> _reprocessingIds = <String>{};
  bool _isUploading = false;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _searchQuery = '';
  int _offset = 0;
  final int _limit = 10;
  final ScrollController _scrollController = ScrollController();
  bool _isNavigating = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? _loadingPreviewId;
  bool _isCameraPermissionGranted = false;
  bool _isStoragePermissionGranted = false;
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _selectedCategory;
  bool _isPhotoTaken = false; // Track if photo was taken

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _fetchCategories();
    _fetchInvoices();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !_isLoadingMore &&
          _hasMore) {
        _fetchMoreInvoices();
      }
    });
    _searchFocusNode.addListener(() {
      if (_isNavigating && _searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    });
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await InvoiceListService().fetchCategories();
      if (mounted) {
        setState(() {
          _categories = [
            {'id': null, 'name': 'All'},
            ...categories.map((c) => {'id': c['id'], 'name': c['name']}),
          ];
          _selectedCategory = _categories[0];
        });
      }
    } catch (e) {
      print('Failed to fetch categories: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load categories: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future _checkPermissions() async {
    bool cameraGranted = false;
    bool storageGranted = false;

    // Get device info to check Android version
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final androidVersion = deviceInfo.version.sdkInt;

    while (!cameraGranted || !storageGranted) {
      // Check & request camera permission
      var cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        cameraStatus = await Permission.camera.request();
      }
      cameraGranted = cameraStatus.isGranted;

      // Check & request storage permissions based on Android version
      if (androidVersion >= 33) {
        // Android 13+ - Use granular media permissions
        final Map<Permission, PermissionStatus> statuses =
            await [
              Permission.photos, // READ_MEDIA_IMAGES
              Permission.videos, // READ_MEDIA_VIDEO
              // Permission.audio,   // Uncomment if you need audio access
            ].request();

        // Check if at least photos permission is granted (since you're handling images)
        storageGranted = statuses[Permission.photos]?.isGranted ?? false;
      } else {
        // Android 12 and below - Use traditional storage permission
        final storageStatus = await Permission.storage.status;
        if (!storageStatus.isGranted) {
          final newStatus = await Permission.storage.request();
          storageGranted = newStatus.isGranted;
        } else {
          storageGranted = true;
        }
      }

      // Update state
      setState(() {
        _isCameraPermissionGranted = cameraGranted;
        _isStoragePermissionGranted = storageGranted;
      });

      print(
        "camera: $_isCameraPermissionGranted : storage: $_isStoragePermissionGranted",
      );

      // Show dialog if permissions still denied
      if (!cameraGranted || !storageGranted) {
        await showDialog(
          context: context,
          builder:
              (ctx) => AlertDialog(
                title: Text("Permissions Required"),
                content: Text(
                  "Camera and storage permissions are needed to proceed. Please allow them.",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text("OK"),
                  ),
                ],
              ),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  IconData _getFileIcon(String url) {
    final extension = url.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png'].contains(extension)) {
      return Icons.image;
    } else if (extension == 'pdf') {
      return Icons.picture_as_pdf;
    } else {
      return Icons.insert_drive_file;
    }
  }

  String _getFileName(String url) {
    // Extract the file name from the URL
    final uri = Uri.parse(url);
    return uri.pathSegments.last;
  }

  Future<void> _fetchInvoices({String? search, String? categoryId}) async {
    setState(() {
      _isLoading = true;
      _offset = 0;
      _invoices.clear();
      _hasMore = true;
    });
    try {
      final service = InvoiceListService();
      final invoices = await service.fetchInvoices(
        search: search,
        category: categoryId,
        limit: _limit,
        offset: _offset,
      );
      print("the invoice data: $invoices");
      print("Response type: ${invoices.runtimeType}");
      setState(() {
        _invoices = invoices;
        _offset += _limit;
        _hasMore = invoices.length == _limit;
      });
    } catch (e) {
      print('❌ Failed to load invoices :$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('❌ Failed to load invoices'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMoreInvoices() async {
    if (!_hasMore || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final service = InvoiceListService();
      final invoices = await service.fetchInvoices(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        category: _selectedCategory?['id']?.toString(),
        limit: _limit,
        offset: _offset,
      );
      print("Fetched more invoices: $invoices");
      setState(() {
        _invoices.addAll(invoices);
        _offset += _limit;
        _hasMore = invoices.length == _limit;
      });
    } catch (e) {
      print('❌ Failed to load more invoices :$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('❌ Failed to load more invoices'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchQuery = query;
    _fetchInvoices(
      search: query.isNotEmpty ? query : null,
      categoryId: _selectedCategory?['id']?.toString(),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => SendOtpScreen()),
      (route) => false,
    );
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.logout_rounded, color: Color(0xFF192155)),
                SizedBox(width: 8),
                Text('Confirm Logout'),
              ],
            ),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _logout(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF192155),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
    );
  }

  void _showCategoriesFilterDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.category_rounded, color: Color(0xFF192155)),
                SizedBox(width: 8),
                Text('Select Category'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    _categories.map((category) {
                      return RadioListTile<Map<String, dynamic>>(
                        title: Text(category['name']),
                        value: category,
                        groupValue: _selectedCategory,
                        activeColor: Color(0xFF192155),
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value;
                            _fetchInvoices(
                              search:
                                  _searchQuery.isNotEmpty ? _searchQuery : null,
                              categoryId: value?['id']?.toString(),
                            );
                          });
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _uploadSelectedFiles(
    BuildContext parentContext, {
    File? singleFile,
    List<File>? images,
  }) async {
    if (singleFile == null && images == null) return;
    if (singleFile != null && images != null) {
      print('Invalid input: both singleFile and images provided');
      if (mounted) setState(() => _isUploading = false);
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(
          content: const Text('Cannot upload both a document and images'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    print('Starting _uploadSelectedFiles');

    final formData = FormData();
    if (singleFile != null) {
      final fileName = singleFile.path.split('/').last;
      final mimeType =
          lookupMimeType(singleFile.path) ?? 'application/octet-stream';
      formData.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(
            singleFile.path,
            filename: fileName,
            contentType: MediaType.parse(mimeType),
          ),
        ),
      );
      print('Added single file to FormData: $fileName');
    } else if (images != null) {
      for (var image in images) {
        final fileName = image.path.split('/').last;
        final mimeType = lookupMimeType(image.path) ?? 'image/jpeg';
        formData.files.add(
          MapEntry(
            'images',
            await MultipartFile.fromFile(
              image.path,
              filename: fileName,
              contentType: MediaType.parse(mimeType),
            ),
          ),
        );
        print('Added image to FormData: $fileName');
      }
    }

    final dialogCompleter = Completer<void>();
    String progressMessage = 'Uploading files...';
    bool isDataExtracted = false;
    bool isValidated = false;
    bool isPreparing = false;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              if (!isDataExtracted) {
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted && context.mounted) {
                    setState(() {
                      isDataExtracted = true;
                      progressMessage = 'Extracting data with AI...';
                    });
                  }
                });
              }
              if (isDataExtracted && !isValidated) {
                Future.delayed(const Duration(seconds: 4), () {
                  if (mounted && context.mounted) {
                    setState(() {
                      isValidated = true;
                      progressMessage = 'Validating data...';
                    });
                  }
                });
              }
              if (isValidated && !isPreparing) {
                Future.delayed(const Duration(seconds: 4), () {
                  if (mounted && context.mounted) {
                    setState(() {
                      isPreparing = true;
                      progressMessage = 'Preparing invoice data...';
                    });
                  }
                });
              }

              return InvoiceCard();
            },
          ),
    ).then((_) {
      if (!dialogCompleter.isCompleted) dialogCompleter.complete();
    });

    try {
      final api = InvoiceApiService();
      print('Fetching categories');
      final categories = await InvoiceListService().fetchCategories();
      print('Categories fetched: $categories');
      String? selectedCategoryId;

      print('Calling uploadInvoices API');
      final responses = await api.uploadInvoices(formData);
      print('API response: $responses');

      if (mounted) {
        Navigator.pop(parentContext);
        dialogCompleter.complete();
      }

      if (!mounted) return;

      print('Showing review dialog');

      final invoicedToController = TextEditingController();
      final remarkController = TextEditingController();

      final invoiceNumberController = TextEditingController(
        text: responses.isNotEmpty ? responses[0].invoiceNumber : null,
      );
      final companyNameController = TextEditingController(
        text: responses.isNotEmpty ? responses[0].vendorName : null,
      );
      final invoiceDateController = TextEditingController(
        text: _formatDateToYYYYMMDD(
          responses.isNotEmpty
              ? responses[0].date ?? DateTime.now().toIso8601String()
              : DateTime.now().toIso8601String(),
        ),
      );
      final amountController = TextEditingController(
        text: responses.isNotEmpty ? responses[0].amount?.toString() : null,
      );

      final confirmResponse = InvoiceConfirmUploadResponse(
        message: 'Upload successful',
        uploadedFiles:
            responses
                .where((r) => r.uploadedFileId != null)
                .map((r) => UploadedFile(id: r.uploadedFileId!, url: ''))
                .toList(),
        aiData: AiData(
          invoiceNumber: invoiceNumberController.text,
          companyName: companyNameController.text,
          invoiceDate: invoiceDateController.text,
          amount: double.tryParse(amountController.text) ?? 0.0,
          dueDate:
              responses.isNotEmpty
                  ? responses[0].dueDate ?? DateTime.now().toIso8601String()
                  : DateTime.now().toIso8601String(),
          lineItems:
              responses.isNotEmpty && responses[0].lineItems != null
                  ? responses[0].lineItems!
                      .map(
                        (item) =>
                            LineItem.fromJson(item as Map<String, dynamic>),
                      )
                      .toList()
                  : [LineItem(description: 'Default Item', total: 0.0)],
        ),
      );

      print(
        'Uploaded File IDs: ${confirmResponse.uploadedFiles.map((file) => file.id).toList()}',
      );

      final _formKey = GlobalKey<FormState>();

      bool? isCommitted = await showDialog<bool>(
        context: parentContext,
        barrierDismissible: false,
        builder: (context) {
          return MediaQuery.removeViewInsets(
            // Prevents keyboard from shrinking the dialog
            removeBottom: true,
            context: context,
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 40,
              ),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                height: MediaQuery.of(context).size.height * 0.85,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                      child: Column(
                        children: [
                          // Title
                          Row(
                            children: const [
                              Icon(
                                Icons.check_circle,
                                color: Color(0xFF192155),
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Review AI Extracted Data',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 1, color: Colors.grey),
                          const SizedBox(height: 8),

                          // Form (scrollable if really needed)
                          Expanded(
                            child: Form(
                              key: _formKey,
                              child: SingleChildScrollView(
                                padding: EdgeInsets.only(
                                  left: 4,
                                  right: 4,
                                  bottom:
                                      MediaQuery.of(context)
                                          .viewInsets
                                          .bottom, // Adjust for keyboard
                                ),
                                child: Column(
                                  children: [
                                    DropdownButtonFormField<String>(
                                      decoration: _inputDecoration(
                                        'Select Company',
                                      ),
                                      value:
                                          invoicedToController.text.isEmpty
                                              ? null
                                              : invoicedToController.text,
                                      items:
                                          ['VRV', 'GRANULE AGRO']
                                              .map(
                                                (company) => DropdownMenuItem(
                                                  value: company,
                                                  child: Text(company),
                                                ),
                                              )
                                              .toList(),
                                      onChanged: (value) {
                                        invoicedToController.text = value ?? '';
                                      },
                                      validator:
                                          (value) =>
                                              value == null
                                                  ? 'Please select a company'
                                                  : null,
                                    ),
                                    const SizedBox(
                                      height: 8,
                                    ), // Reduced from 12
                                    DropdownButtonFormField<String>(
                                      decoration: _inputDecoration('Category'),
                                      value: selectedCategoryId,
                                      items:
                                          categories
                                              .where((c) => c['name'] != null)
                                              .map(
                                                (category) => DropdownMenuItem(
                                                  value:
                                                      category['id']
                                                          ?.toString(),
                                                  child: Text(
                                                    category['name']!,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                      onChanged:
                                          (value) => selectedCategoryId = value,
                                      validator:
                                          (value) =>
                                              (value == null || value.isEmpty)
                                                  ? 'Please select a category'
                                                  : null,
                                    ),
                                    const SizedBox(
                                      height: 8,
                                    ), // Reduced from 12
                                    TextField(
                                      decoration: _inputDecoration(
                                        'Invoice Number',
                                      ),
                                      controller: invoiceNumberController,
                                    ),
                                    const SizedBox(
                                      height: 8,
                                    ), // Reduced from 12
                                    TextFormField(
                                      decoration: _inputDecoration(
                                        'Company Name',
                                      ),
                                      controller: companyNameController,
                                      validator:
                                          (value) =>
                                              (value == null ||
                                                      value.trim().isEmpty)
                                                  ? 'Please enter a company name'
                                                  : null,
                                    ),
                                    const SizedBox(
                                      height: 8,
                                    ), // Reduced from 12
                                    TextFormField(
                                      decoration: _inputDecoration(
                                        'Invoice Date',
                                      ).copyWith(
                                        suffixIcon: IconButton(
                                          icon: const Icon(
                                            Icons.calendar_today,
                                            color: Color(0xFF192155),
                                          ),
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: DateTime.now(),
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100),
                                            );
                                            if (picked != null) {
                                              invoiceDateController
                                                  .text = _formatDateToYYYYMMDD(
                                                picked.toIso8601String(),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      controller: invoiceDateController,
                                      readOnly: true,
                                    ),
                                    const SizedBox(
                                      height: 8,
                                    ), // Reduced from 12
                                    TextField(
                                      decoration: _inputDecoration('Amount'),
                                      controller: amountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    ),
                                    const SizedBox(
                                      height: 8,
                                    ), // Reduced from 12
                                    TextFormField(
                                      decoration: _inputDecoration('Remark'),
                                      controller: remarkController,
                                      validator:
                                          (value) =>
                                              (value == null ||
                                                      value.trim().isEmpty)
                                                  ? 'Please enter a remark'
                                                  : null,
                                    ),
                                    const SizedBox(
                                      height: 16,
                                    ), // Reduced from 20
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              OutlinedButton(
                                onPressed: () async {
                                  final uploadedFileIds =
                                      confirmResponse.uploadedFiles
                                          .map((f) => f.id)
                                          .toList();
                                  if (uploadedFileIds.isNotEmpty) {
                                    await api.cancelUpload(uploadedFileIds);
                                  }
                                  Navigator.pop(context, false);
                                  await _fetchInvoices();
                                  setState(() {
                                    _selectedFile = null;
                                    _selectedImages.clear();
                                    _isPhotoTaken = false;
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  if (!_formKey.currentState!.validate())
                                    return;

                                  try {
                                    final uploadedFileIds =
                                        confirmResponse.uploadedFiles
                                            .map((f) => f.id)
                                            .toList();
                                    if (uploadedFileIds.isNotEmpty) {
                                      final aiData = {
                                        'company_name':
                                            companyNameController.text,
                                        'invoice_number':
                                            invoiceNumberController.text,
                                        'amount':
                                            double.tryParse(
                                              amountController.text,
                                            ) ??
                                            0.0,
                                        'date': invoiceDateController.text,
                                        'remarks':
                                            remarkController
                                                .text, // Add remarks field if needed
                                        'invoiced_to':
                                            invoicedToController.text,
                                        'line_items':
                                            confirmResponse.aiData.lineItems
                                                .map((i) => i.toJson())
                                                .toList(),
                                      };
                                      await api.commitInvoice(
                                        categoryId: selectedCategoryId ?? '',
                                        aiData: aiData,
                                        uploadedFileIds: uploadedFileIds,
                                      );
                                    }
                                    Navigator.pop(context, true);
                                  } catch (e) {
                                    debugPrint("❌ Commit Error: $e");
                                    Navigator.pop(context, true);
                                  } finally {
                                    await _fetchInvoices();
                                    setState(() {
                                      _selectedFile = null;
                                      _selectedImages.clear();
                                      _isPhotoTaken = false;
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF192155),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Confirm'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Close button
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(Icons.close, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      invoiceNumberController.dispose();
      companyNameController.dispose();
      invoiceDateController.dispose();
      amountController.dispose();

      print('Review dialog dismissed');

      if (isCommitted == true) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(
            content: Text('Uploaded invoice(s)! successfully'),
            backgroundColor: Colors.green.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else if (isCommitted == null) {
        // Dialog dismissed without button press, treat as cancel
        try {
          for (var file in confirmResponse.uploadedFiles) {
            await api.cancelUpload([file.id]);
          }
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: const Text('Upload cancelled'),
              backgroundColor: Colors.orange.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        } catch (e) {
          print('Failed to cancel upload: $e');
        }
        await _fetchInvoices();
        setState(() {
          _selectedFile = null;
          _selectedImages.clear();
          _isPhotoTaken = false;
        });
      }
      // CHANGE END
    } catch (e) {
      print('Upload Error: $e');
      if (e is DioException) {
        print(
          'DioException Details: ${e.response?.data}, Status: ${e.response?.statusCode}',
        );
      }
      if (!dialogCompleter.isCompleted) {
        Navigator.pop(parentContext);
        dialogCompleter.complete();
      }
      ScaffoldMessenger.of(parentContext).showSnackBar(
        SnackBar(
          content: Text(
            'Upload failed: ${e is DioException ? e.response?.data['message'] ?? e.message : e}',
          ),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
      print('Finished _uploadSelectedFiles');
    }
  }

  String _formatDateToYYYYMMDD(String date) {
    try {
      final parsedDate = DateTime.parse(date);
      return "${parsedDate.year}-${parsedDate.month.toString().padLeft(2, '0')}-${parsedDate.day.toString().padLeft(2, '0')}";
    } catch (e) {
      print('Error parsing date: $e');
      final now = DateTime.now();
      return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    }
  }

  /// Helper for consistent form field styling
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade100,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // Future<void> _showAIProcessingDialog(BuildContext context) async {
  //   bool isFilesUploaded = true;
  //   bool isDataExtracted = false;
  //   bool isValidated = false;
  //   bool isPreparing = false;
  //
  //   await showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder:
  //         (context) => StatefulBuilder(
  //           builder: (context, setState) {
  //             String message = 'Uploading files...';
  //             if (isFilesUploaded && !isDataExtracted) {
  //               Future.delayed(const Duration(seconds: 3), () {
  //                 if (mounted) {
  //                   setState(() {
  //                     isDataExtracted = true;
  //                     message = 'Extracting data with AI...';
  //                   });
  //                 }
  //               });
  //             }
  //             if (isDataExtracted && !isValidated) {
  //               Future.delayed(const Duration(seconds: 4), () {
  //                 if (mounted) {
  //                   setState(() {
  //                     isValidated = true;
  //                     message = 'Validating data...';
  //                   });
  //                 }
  //               });
  //             }
  //             if (isValidated && !isPreparing) {
  //               Future.delayed(const Duration(seconds: 4), () {
  //                 if (mounted) {
  //                   setState(() {
  //                     isPreparing = true;
  //                     message = 'Preparing invoice data...';
  //                   });
  //                 }
  //               });
  //             }
  //
  //             return InvoiceCard();
  //           },
  //         ),
  //   );
  // }

  void _showUploadOptions(BuildContext context) {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        var cameraStatus = Permission.camera.status;
        var storageStatus = Permission.storage.status;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Upload Invoice',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF192155),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildUploadOption(
                    icon: Icons.camera_alt_rounded,
                    title: 'Take Photo',
                    subtitle: 'Capture up to 3 images with camera',
                    onTap: () async {
                      if (cameraStatus.isGranted == false) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Camera permission is required.',
                            ),
                            backgroundColor: Colors.red.shade400,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(bottomSheetContext);
                      try {
                        final XFile? photo = await _picker.pickImage(
                          source: ImageSource.camera,
                          imageQuality: 80,
                        );
                        if (photo != null) {
                          final newFile = File(photo.path);
                          final extension =
                              photo.path.split('.').last.toLowerCase();
                          if (!['jpg', 'jpeg', 'png'].contains(extension)) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Only JPG or PNG images are allowed.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }
                          final fileSize = await newFile.length();
                          if (fileSize > 10 * 1024 * 1024) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Image size exceeds 10MB limit.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            _selectedImages = [
                              newFile,
                            ]; // Replace existing images
                            _selectedFile = null;
                            _isPhotoTaken = true;
                          });
                          _showSelectedFilesModal(parentContext, "Photo");
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: const Text('Photo capture cancelled'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: Text('Camera error: $e'),
                            backgroundColor: Colors.red.shade400,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildUploadOption(
                    icon: Icons.upload_file_rounded,
                    title: 'Upload from Device',
                    subtitle: 'Select 1 PDF/DOC ',
                    onTap: () async {
                      if (storageStatus.isGranted == false) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Storage permission is required.',
                            ),
                            backgroundColor: Colors.red.shade400,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(bottomSheetContext);
                      try {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                              allowMultiple: true,
                              type: FileType.custom,
                              allowedExtensions: [
                                'pdf',
                                'doc',
                                'docx',
                                'jpg',
                                'jpeg',
                                'png',
                              ],
                            );

                        if (result != null && result.files.isNotEmpty) {
                          final files =
                              result.files.map((f) => File(f.path!)).toList();
                          int imageCount =
                              files
                                  .where(
                                    (f) => ['jpg', 'jpeg', 'png'].contains(
                                      f.path.split('.').last.toLowerCase(),
                                    ),
                                  )
                                  .length;
                          int docCount =
                              files
                                  .where(
                                    (f) => ['pdf', 'doc', 'docx'].contains(
                                      f.path.split('.').last.toLowerCase(),
                                    ),
                                  )
                                  .length;

                          if (imageCount > 0 && docCount > 0) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Cannot upload both images and documents together.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }
                          if (imageCount > 3) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'You can upload a maximum of 3 images.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }
                          if (docCount > 1) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'You can upload only 1 document (PDF/DOC/DOCX).',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }
                          // Moved size check here to cover both images and documents
                          bool exceedsSize = false;
                          for (var file in files) {
                            final fileSize = await file.length();
                            if (fileSize > 10 * 1024 * 1024) {
                              exceedsSize = true;
                              break;
                            }
                          }
                          if (exceedsSize) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'One or more files exceed 10MB limit.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                            return;
                          }

                          setState(() {
                            if (imageCount > 0) {
                              _selectedImages =
                                  files; // Replace existing images
                              _selectedFile = null;
                              _isPhotoTaken = false;
                            } else {
                              _selectedFile =
                                  files.first; // Replace existing document
                              _selectedImages = [];
                              _isPhotoTaken = false;
                            }
                          });
                          _showSelectedFilesModal(parentContext, "File");
                        } else {
                          if (!mounted) return;
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: const Text('No files selected'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: Text('File selection error: $e'),
                            backgroundColor: Colors.red.shade400,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSelectedFilesModal(
    BuildContext parentContext,
    String selectedMode,
  ) {
    File? tempSelectedFile = _selectedFile;
    List<File> tempSelectedImages = List.from(_selectedImages);
    bool isFromFilePicker = false; // Track if images are from file picker
    bool isCompressing = false; // Track compression state

    // Function to compress image while maintaining quality
    Future<File> _compressImage(File file, StateSetter modalSetState) async {
      modalSetState(() {
        isCompressing = true; // Show compression animation
      });

      try {
        final image = img.decodeImage(await file.readAsBytes());
        if (image == null) {
          modalSetState(() {
            isCompressing = false;
          });
          return file;
        }

        // Encode as JPEG with high quality (adjust quality as needed, 85 is a good balance)
        final compressedImage = img.encodeJpg(image, quality: 85);

        // Create a temporary file for compressed image
        final tempDir = await getTemporaryDirectory();
        final tempPath =
            '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final compressedFile = File(tempPath)
          ..writeAsBytesSync(compressedImage);

        modalSetState(() {
          isCompressing = false; // Hide compression animation
        });
        return compressedFile;
      } catch (e) {
        modalSetState(() {
          isCompressing = false; // Ensure animation stops on error
        });
        rethrow;
      }
    }

    showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter modalSetState) {
            bool hasSelected =
                tempSelectedFile != null || tempSelectedImages.isNotEmpty;
            bool isImageMode = tempSelectedFile == null;
            bool isUploadEnabled =
                (tempSelectedFile == null && tempSelectedImages.length < 3) &&
                !isFromFilePicker &&
                !isCompressing; // Also check isCompressing

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: Center(
                          child: Text(
                            'Upload Invoices',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF192155),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Compression UI - Show over existing content
                      if (isCompressing)
                        Container(
                          padding: const EdgeInsets.all(24.0),
                          margin: const EdgeInsets.symmetric(vertical: 16.0),
                          decoration: BoxDecoration(
                            color: Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(
                              color: Color(0xFF192155).withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Compressing image...',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF192155),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Please wait while we optimize your file',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                      // File support info (only show when not compressing and no files selected)
                      if (!isCompressing && !hasSelected)
                        DottedBorder(
                          options: RoundedRectDottedBorderOptions(
                            dashPattern: [8, 4],
                            strokeWidth: 1,
                            radius: const Radius.circular(8.0),
                            color: Colors.grey.shade400,
                            padding: const EdgeInsets.all(0),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Supports 1 PDF/DOC/DOCX or up to 3 PNG/JPG (10MB each)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Selected files count (hide during compression)
                      if (!isCompressing)
                        Text(
                          selectedMode == "Photo"
                              ? 'Selected Photo (${tempSelectedImages.length}/3)'
                              : 'Selected Files (${(tempSelectedFile != null ? 1 : 0) + tempSelectedImages.length}/1)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF192155),
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Files list or no files message (hide during compression)
                      if (!isCompressing && !hasSelected)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'No files selected',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        )
                      else if (!isCompressing && hasSelected)
                        Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount:
                                (tempSelectedFile != null ? 1 : 0) +
                                tempSelectedImages.length,
                            itemBuilder: (context, index) {
                              File file;
                              bool isImage;
                              bool isPdf;
                              if (tempSelectedFile != null && index == 0) {
                                file = tempSelectedFile!;
                                isImage = ['jpg', 'jpeg', 'png'].contains(
                                  file.path.split('.').last.toLowerCase(),
                                );
                                isPdf =
                                    file.path.split('.').last.toLowerCase() ==
                                    'pdf';
                              } else {
                                file =
                                    tempSelectedImages[index -
                                        (tempSelectedFile != null ? 1 : 0)];
                                isImage = ['jpg', 'jpeg', 'png'].contains(
                                  file.path.split('.').last.toLowerCase(),
                                );
                                isPdf =
                                    file.path.split('.').last.toLowerCase() ==
                                    'pdf';
                              }
                              final fileNameParts = file.path
                                  .split('/')
                                  .last
                                  .split(' ');
                              final trimmedFileName =
                                  fileNameParts.length > 2
                                      ? '${fileNameParts.take(2).join(' ')}...'
                                      : fileNameParts.join(' ');
                              final fileSize =
                                  (file.lengthSync() / (1024 * 1024))
                                      .toStringAsFixed(1) +
                                  'MB';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8.0),
                                padding: const EdgeInsets.all(12.0),
                                decoration: BoxDecoration(
                                  color: Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (isPdf)
                                          const Icon(
                                            Icons.picture_as_pdf,
                                            color: Color(0xFF192155),
                                            size: 20,
                                          ),
                                        if (isImage)
                                          const Icon(
                                            Icons.image,
                                            color: Color(0xFF192155),
                                            size: 20,
                                          ),
                                        if (!isPdf && !isImage)
                                          const Icon(
                                            Icons.insert_drive_file,
                                            color: Color(0xFF192155),
                                            size: 20,
                                          ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            trimmedFileName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isImage || isPdf)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.remove_red_eye,
                                              color: Colors.blue,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              showGeneralDialog(
                                                context: context,
                                                barrierDismissible: true,
                                                barrierLabel: 'Invoice Preview',
                                                pageBuilder: (
                                                  context,
                                                  anim1,
                                                  anim2,
                                                ) {
                                                  return Center(
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: Container(
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 24,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color:
                                                                  Colors
                                                                      .black26,
                                                              blurRadius: 12,
                                                              offset: Offset(
                                                                0,
                                                                6,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Stack(
                                                          children: [
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets.fromLTRB(
                                                                    24,
                                                                    56,
                                                                    24,
                                                                    24,
                                                                  ),
                                                              child: Column(
                                                                mainAxisSize:
                                                                    MainAxisSize
                                                                        .min,
                                                                children: [
                                                                  const Text(
                                                                    'Invoice Preview',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          22,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 16,
                                                                  ),
                                                                  Divider(
                                                                    height: 1,
                                                                    thickness:
                                                                        1,
                                                                    color:
                                                                        Colors
                                                                            .grey[300],
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 16,
                                                                  ),
                                                                  SizedBox(
                                                                    width:
                                                                        double
                                                                            .maxFinite,
                                                                    height: 400,
                                                                    child:
                                                                        isImage
                                                                            ? ClipRRect(
                                                                              borderRadius: BorderRadius.circular(
                                                                                8,
                                                                              ),
                                                                              child: Image.file(
                                                                                file,
                                                                                fit:
                                                                                    BoxFit.contain,
                                                                              ),
                                                                            )
                                                                            : isPdf
                                                                            ? PDFView(
                                                                              filePath:
                                                                                  file.path,
                                                                              onError: (
                                                                                error,
                                                                              ) {
                                                                                ScaffoldMessenger.of(
                                                                                  context,
                                                                                ).showSnackBar(
                                                                                  SnackBar(
                                                                                    content: Text(
                                                                                      'Failed to load PDF: $error',
                                                                                    ),
                                                                                    backgroundColor:
                                                                                        Colors.red.shade400,
                                                                                    behavior:
                                                                                        SnackBarBehavior.floating,
                                                                                    shape: RoundedRectangleBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              },
                                                                              onPageError: (
                                                                                page,
                                                                                error,
                                                                              ) {
                                                                                ScaffoldMessenger.of(
                                                                                  context,
                                                                                ).showSnackBar(
                                                                                  SnackBar(
                                                                                    content: Text(
                                                                                      'Failed to load page $page: $error',
                                                                                    ),
                                                                                    backgroundColor:
                                                                                        Colors.red.shade400,
                                                                                    behavior:
                                                                                        SnackBarBehavior.floating,
                                                                                    shape: RoundedRectangleBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              },
                                                                            )
                                                                            : const Center(
                                                                              child: Text(
                                                                                'Unsupported file type',
                                                                              ),
                                                                            ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            Positioned(
                                                              top: 12,
                                                              right: 12,
                                                              child: InkWell(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      24,
                                                                    ),
                                                                onTap:
                                                                    () =>
                                                                        Navigator.of(
                                                                          context,
                                                                        ).pop(),
                                                                child: Container(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        8,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    shape:
                                                                        BoxShape
                                                                            .circle,
                                                                    color:
                                                                        Colors
                                                                            .grey[200],
                                                                  ),
                                                                  child: const Icon(
                                                                    Icons.close,
                                                                    size: 20,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                                transitionBuilder: (
                                                  context,
                                                  anim1,
                                                  anim2,
                                                  child,
                                                ) {
                                                  return FadeTransition(
                                                    opacity: anim1,
                                                    child: child,
                                                  );
                                                },
                                                transitionDuration:
                                                    const Duration(
                                                      milliseconds: 250,
                                                    ),
                                              );
                                            },
                                          ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.close,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            modalSetState(() {
                                              if (tempSelectedFile != null &&
                                                  index == 0) {
                                                tempSelectedFile = null;
                                              } else {
                                                tempSelectedImages.removeAt(
                                                  index -
                                                      (tempSelectedFile != null
                                                          ? 1
                                                          : 0),
                                                );
                                              }
                                              // Re-enable Add button if removing last image from file picker
                                              if (tempSelectedImages.isEmpty) {
                                                isFromFilePicker = false;
                                              }
                                              // Ensure compression state is reset when removing files
                                              if (tempSelectedFile == null &&
                                                  tempSelectedImages.isEmpty) {
                                                isCompressing = false;
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 32.0,
                                        top: 4.0,
                                      ),
                                      child: Text(
                                        '($fileSize)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed:
                                hasSelected && !isCompressing
                                    ? () {
                                      modalSetState(() {
                                        tempSelectedFile = null;
                                        tempSelectedImages.clear();
                                        isFromFilePicker =
                                            false; // Reset to enable Add button
                                        isCompressing =
                                            false; // Reset compression state
                                      });
                                    }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  hasSelected && !isCompressing
                                      ? Color(0xffFF9635)
                                      : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              minimumSize: Size(100, 48),
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text('Reset'),
                          ),
                          ElevatedButton(
                            onPressed:
                                isUploadEnabled &&
                                        tempSelectedImages.length < 3 &&
                                        !isCompressing
                                    ? () async {
                                      if (selectedMode == "File") {
                                        // Show dialog to choose between camera and file picker
                                        try {
                                          FilePickerResult? result =
                                              await FilePicker.platform
                                                  .pickFiles(
                                                    allowMultiple: true,
                                                    type: FileType.custom,
                                                    allowedExtensions: [
                                                      'jpg',
                                                      'jpeg',
                                                      'png',
                                                      'pdf',
                                                      'doc',
                                                      'docx',
                                                    ],
                                                  );
                                          if (result != null &&
                                              result.files.isNotEmpty) {
                                            List<File> newFiles = [];

                                            for (var f in result.files) {
                                              if (f.path != null) {
                                                File file = File(f.path!);
                                                final fileSize =
                                                    await file.length();
                                                if (fileSize >
                                                    10 * 1024 * 1024) {
                                                  continue; // Skip files over 10MB
                                                }

                                                if ([
                                                  'jpg',
                                                  'jpeg',
                                                  'png',
                                                ].contains(
                                                  file.path
                                                      .split('.')
                                                      .last
                                                      .toLowerCase(),
                                                )) {
                                                  // Compress image files
                                                  file = await _compressImage(
                                                    file,
                                                    modalSetState,
                                                  );
                                                }
                                                newFiles.add(file);
                                              }
                                            }

                                            if (newFiles.isEmpty) {
                                              ScaffoldMessenger.of(
                                                parentContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'One or more files exceed 10MB limit.',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            if (tempSelectedImages.length +
                                                    newFiles
                                                        .where(
                                                          (f) => [
                                                            'jpg',
                                                            'jpeg',
                                                            'png',
                                                          ].contains(
                                                            f.path
                                                                .split('.')
                                                                .last
                                                                .toLowerCase(),
                                                          ),
                                                        )
                                                        .length >
                                                3) {
                                              ScaffoldMessenger.of(
                                                parentContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'You can upload a maximum of 3 images.',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            modalSetState(() {
                                              tempSelectedImages.addAll(
                                                newFiles
                                                    .where(
                                                      (f) => [
                                                        'jpg',
                                                        'jpeg',
                                                        'png',
                                                      ].contains(
                                                        f.path
                                                            .split('.')
                                                            .last
                                                            .toLowerCase(),
                                                      ),
                                                    )
                                                    .toList(),
                                              );
                                              final docFiles =
                                                  newFiles
                                                      .where(
                                                        (f) => [
                                                          'pdf',
                                                          'doc',
                                                          'docx',
                                                        ].contains(
                                                          f.path
                                                              .split('.')
                                                              .last
                                                              .toLowerCase(),
                                                        ),
                                                      )
                                                      .toList();
                                              if (docFiles.isNotEmpty) {
                                                tempSelectedFile =
                                                    docFiles.first;
                                              }
                                              isFromFilePicker = true;
                                            });
                                          }
                                        } catch (e) {
                                          modalSetState(() {
                                            isCompressing =
                                                false; // Reset compression state on error
                                          });
                                          ScaffoldMessenger.of(
                                            parentContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'File selection error: $e',
                                              ),
                                              backgroundColor:
                                                  Colors.red.shade400,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        // Original photo capture logic for non-File mode
                                        try {
                                          final ImagePicker picker =
                                              ImagePicker();
                                          final XFile? photo = await picker
                                              .pickImage(
                                                source: ImageSource.camera,
                                              );
                                          if (photo != null) {
                                            File file = File(photo.path);
                                            final fileSize =
                                                await file.length();
                                            if (fileSize > 10 * 1024 * 1024) {
                                              ScaffoldMessenger.of(
                                                parentContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'Photo exceeds 10MB limit.',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            if (tempSelectedImages.length >=
                                                3) {
                                              ScaffoldMessenger.of(
                                                parentContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: const Text(
                                                    'You can upload a maximum of 3 images.',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            // Compress the image
                                            file = await _compressImage(
                                              file,
                                              modalSetState,
                                            );
                                            modalSetState(() {
                                              tempSelectedImages.add(file);
                                              tempSelectedFile = null;
                                              isFromFilePicker = false;
                                            });
                                          }
                                        } catch (e) {
                                          modalSetState(() {
                                            isCompressing =
                                                false; // Reset compression state on error
                                          });
                                          ScaffoldMessenger.of(
                                            parentContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text('Camera error: $e'),
                                              backgroundColor:
                                                  Colors.red.shade400,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isUploadEnabled &&
                                          tempSelectedImages.length < 3 &&
                                          !isCompressing
                                      ? Color(0xFF4A90E2)
                                      : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              minimumSize: Size(100, 48),
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.add, size: 18),
                                SizedBox(width: 8),
                                Text('Add'),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed:
                                hasSelected && !_isUploading && !isCompressing
                                    ? () async {
                                      if (tempSelectedFile != null &&
                                          tempSelectedImages.isNotEmpty) {
                                        ScaffoldMessenger.of(
                                          parentContext,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Cannot upload both a document and images.',
                                            ),
                                            backgroundColor:
                                                Colors.red.shade400,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.pop(modalContext);
                                      setState(() {
                                        _selectedFile = tempSelectedFile;
                                        _selectedImages = tempSelectedImages;
                                      });
                                      await _uploadSelectedFiles(
                                        parentContext,
                                        singleFile: tempSelectedFile,
                                        images:
                                            tempSelectedImages.isEmpty
                                                ? null
                                                : tempSelectedImages,
                                      );
                                    }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  hasSelected && !isCompressing
                                      ? Color(0xFF192155)
                                      : Colors.grey.shade400,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              minimumSize: Size(100, 48),
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child:
                                _isUploading
                                    ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.send_outlined, size: 18),
                                        SizedBox(width: 8),
                                        Text('Submit'),
                                      ],
                                    ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUploadOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Color(0xFF192155)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF192155),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  // Helper to extract clean file extension from URL (strips query params)
  String _getExtensionFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final pathParts = uri.path.split('.');
      if (pathParts.length > 1) {
        return pathParts.last.toLowerCase();
      }
    } catch (_) {}
    return '';
  }

  // Helper to build full URL from relative or absolute path
  // API returns relative paths like /api/files/invoices/...pdf
  String _buildFullUrl(String url) {
    if (url.startsWith('http')) return url;
    const baseDomain = 'https://invoice-staging-api.mindrops.com';
    // Ensure no double slashes
    final path = url.startsWith('/') ? url : '/$url';
    return '$baseDomain$path';
  }

  Future<void> _openInvoicesPreview(List<String> urls) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          final imageUrls =
              urls
                  .where((url) {
                    final ext = _getExtensionFromUrl(url);
                    return ['jpg', 'jpeg', 'png'].contains(ext);
                  })
                  .map(_buildFullUrl)
                  .toList();

          final nonImageUrls =
              urls
                  .where((url) {
                    final ext = _getExtensionFromUrl(url);
                    return !['jpg', 'jpeg', 'png'].contains(ext);
                  })
                  .map(_buildFullUrl)
                  .toList();

          // If only one non-image file, open directly
          if (nonImageUrls.length == 1 && imageUrls.isEmpty) {
            final url = nonImageUrls.first;
            final extension = _getExtensionFromUrl(url);
            final fileName = Uri.parse(url).pathSegments.isNotEmpty
                ? Uri.parse(url).pathSegments.last
                : url.split('/').last;
            return Scaffold(
              appBar: AppBar(
                backgroundColor: const Color(0xFF192155),
                foregroundColor: Colors.white,
                title: const Text('Invoice Preview'),
                actions: [
                  IconButton(
                    onPressed: () {
                      _downloadInvoice(url, fileName);
                    },
                    icon: const Icon(Icons.download),
                  ),
                ],
              ),
              body: _buildInvoiceContent(url, extension),
            );
          }

          // If images or mixed files
          return Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFF192155),
              foregroundColor: Colors.white,
              title: const Text('Invoices Preview'),
              actions: [
                if (imageUrls.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () async {
                      for (var imgUrl in imageUrls) {
                        final imgFileName = Uri.parse(imgUrl).pathSegments.isNotEmpty
                            ? Uri.parse(imgUrl).pathSegments.last
                            : imgUrl.split('/').last;
                        await _downloadInvoice(imgUrl, imgFileName);
                      }
                    },
                  ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (imageUrls.isNotEmpty) ...[
                    for (var imgUrl in imageUrls)
                      Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12),
                          ),
                          child: Image.network(
                            imgUrl,
                            fit: BoxFit.contain,
                            errorBuilder:
                                (context, error, stackTrace) => const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                    child: Text('Failed to load image'),
                                  ),
                                ),
                          ),
                        ),
                      ),
                  ],
                  if (nonImageUrls.isNotEmpty) ...[
                    for (var fileUrl in nonImageUrls)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf),
                          label: Text('Open ${fileUrl.split('/').last}'),
                          onPressed: () {
                            final ext = _getExtensionFromUrl(fileUrl);
                            final fileFileName = Uri.parse(fileUrl).pathSegments.isNotEmpty
                                ? Uri.parse(fileUrl).pathSegments.last
                                : fileUrl.split('/').last;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => Scaffold(
                                      appBar: AppBar(
                                        backgroundColor: const Color(
                                          0xFF192155,
                                        ),
                                        foregroundColor: Colors.white,
                                        title: Text(fileFileName),
                                        actions: [
                                          IconButton(
                                            onPressed: () {
                                              _downloadInvoice(
                                                fileUrl,
                                                fileFileName,
                                              );
                                            },
                                            icon: const Icon(Icons.download),
                                          ),
                                        ],
                                      ),
                                      body: _buildInvoiceContent(fileUrl, ext),
                                    ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInvoiceContent(String completeUrl, String extension) {
    if (['jpg', 'jpeg', 'png'].contains(extension)) {
      return Center(
        child: Image.network(
          completeUrl,
          fit: BoxFit.contain,
          errorBuilder:
              (context, error, stackTrace) =>
                  const Center(child: Text('Failed to load image')),
        ),
      );
    } else if (extension == 'pdf') {
      return FutureBuilder<String?>(
        future: SharedPreferences.getInstance().then((p) => p.getString('token')),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SfPdfViewer.network(
            completeUrl,
            enableDoubleTapZooming: true,
            enableDocumentLinkAnnotation: false,
            headers: snapshot.data != null
                ? {'Authorization': 'Bearer ${snapshot.data}'}
                : {},
          );
        },
      );
    } else {
      return Center(
        child: Text(
          'Unsupported file format',
          style: TextStyle(color: Colors.red.shade400),
        ),
      );
    }
  }

  Future<void> _downloadInvoice(String url, String fileName) async {
    bool permissionGranted = false;

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt <= 29) {
        final status = await Permission.storage.status;
        if (!status.isGranted) {
          await Permission.storage.request();
        }
        permissionGranted = await Permission.storage.isGranted;
      } else {
        permissionGranted = true;
      }
    } else if (Platform.isIOS) {
      permissionGranted = true;
    }

    if (!permissionGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Storage permission is required.'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    bool _loading = false;
    setState(() {
      _loading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      final dio = Dio();
      String filePath;
      if (Platform.isAndroid) {
        filePath = '/storage/emulated/0/Download/$fileName';
      } else if (Platform.isIOS) {
        final downloadsDir = await getApplicationDocumentsDirectory();
        filePath = '${downloadsDir.path}/$fileName';
      } else {
        throw Exception('Unsupported platform');
      }

      await dio.download(
        url,
        filePath,
        options: token != null
            ? Options(headers: {'Authorization': 'Bearer $token'})
            : null,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invoice saved to Downloads folder.'),
          backgroundColor: Colors.green.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download invoice: $e'),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _getStatusChip(String? status) {
    final statusText = (status ?? 'actuator').replaceAll('_', ' ');
    Color borderColor;
    Color textColor;

    switch (statusText.toUpperCase()) {
      case 'AI PROCESSED':
        borderColor = Colors.green.shade100;
        textColor = Colors.green.shade700;
        break;
      case 'AI FAILED':
        borderColor = Colors.red.shade100;
        textColor = Colors.red.shade700;
        break;
      case 'AI PROCESSING':
        borderColor = Colors.orange.shade100;
        textColor = Colors.orange.shade700;
        break;
      default:
        borderColor = Colors.blue.shade100;
        textColor = Colors.blue.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDate(String? date) {
    if (date == null) return 'No date Found';
    try {
      final DateTime parsedDate = DateTime.parse(date);
      return DateFormat('dd/MM/yyyy').format(parsedDate);
    } catch (e) {
      return 'No date Found';
    }
  }

  Color _getColorForCategory(String? categoryName) {
    final String name = categoryName ?? 'Uncategorized';
    final int hash = name.codeUnits.fold(0, (sum, code) => sum + code);
    final Random random = Random(hash);
    return Color((random.nextDouble() * 0xFFFFFF).toInt()).withOpacity(0.3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'Invoice Management',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        backgroundColor: Color(0xFF192155),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded, size: 20),
              tooltip: 'Logout',
              onPressed: () => _showLogoutConfirmation(context),
            ),
          ),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 10, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search invoices...',
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            suffixIcon:
                                _searchController.text.isNotEmpty
                                    ? IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        color: Colors.grey.shade400,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        FocusScope.of(context).unfocus();
                                      },
                                    )
                                    : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.filter_list_rounded,
                          color:
                              _selectedCategory?['id'] == null
                                  ? Colors.grey.shade400
                                  : Color(0xFF192155),
                        ),
                        tooltip: 'Filter by Category',
                        onPressed: _showCategoriesFilterDialog,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child:
                    _isLoading
                        ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF1E88E5),
                            ),
                          ),
                        )
                        : _invoices.isEmpty
                        ? Center(
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
                        )
                        : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount:
                              _invoices.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _invoices.length && _isLoadingMore) {
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

                            final invoice = _invoices[index];

                            // CORRECTED: Handle uploaded_files as a List
                            final uploadedFilesList =
                                invoice['uploaded_files'] as List? ?? [];

                            final publicUrls =
                                uploadedFilesList
                                    .map(
                                      (f) => (f as Map)['public_url'] as String,
                                    )
                                    .where((url) => url != null)
                                    .toList();

                            return InkWell(
                              onTap: () async {
                                if (_loadingPreviewId != null) return;
                                if (publicUrls.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('No preview available'),
                                    ),
                                  );
                                  return;
                                }

                                setState(
                                  () => _loadingPreviewId = invoice['id'],
                                );
                                try {
                                  await _openInvoicesPreview(publicUrls);
                                } finally {
                                  if (mounted)
                                    setState(() => _loadingPreviewId = null);
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              splashColor: Color(0xFF192155).withOpacity(0.2),
                              hoverColor: Colors.grey.shade200,
                              highlightColor: Colors.grey.shade100.withOpacity(
                                0.7,
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            decoration: BoxDecoration(
                                              color: _getColorForCategory(
                                                invoice['category']?['name'],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            child: Text(
                                              invoice['category']?['name'] ??
                                                  'Uncategorized',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade900,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: _getColorForCategory(
                                                invoice['invoiced_to'],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            child: Text(
                                              invoice['invoiced_to'] ??
                                                  'No Company Found ',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade900,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              child: Text(
                                                invoice['invoice_number'] ==
                                                        null
                                                    ? "No invoice number found"
                                                    : "#INV-${invoice['invoice_number']}",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 24),
                                          Text(
                                            '₹${invoice['amount'] ?? '0'}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 16,
                                              color: Color(0xFF192155),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          invoice['company']?['name'] ??
                                              'No company found',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // CORRECTED: Display uploaded file information
                                      // if (uploadedFile != null &&
                                      //     publicUrl != null)
                                      //   Row(
                                      //     children: [
                                      //       Icon(
                                      //         _getFileIcon(publicUrl),
                                      //         size: 16,
                                      //         color: Colors.grey.shade600,
                                      //       ),
                                      //       const SizedBox(width: 6),
                                      //       Expanded(
                                      //         child: Text(
                                      //           uploadedFile['original_name'] ??
                                      //               _getFileName(publicUrl),
                                      //           style: TextStyle(
                                      //             fontSize: 13,
                                      //             color: Colors.grey.shade600,
                                      //           ),
                                      //           overflow: TextOverflow.ellipsis,
                                      //         ),
                                      //       ),
                                      //       if (_loadingPreviewId ==
                                      //           invoice['id'])
                                      //         Padding(
                                      //           padding: const EdgeInsets.only(
                                      //             left: 8,
                                      //           ),
                                      //           child: SizedBox(
                                      //             width: 16,
                                      //             height: 16,
                                      //             child: CircularProgressIndicator(
                                      //               strokeWidth: 2,
                                      //               valueColor:
                                      //                   AlwaysStoppedAnimation(
                                      //                     Colors.blue[900]!,
                                      //                   ),
                                      //             ),
                                      //           ),
                                      //         ),
                                      //     ],
                                      //   )
                                      // else
                                      //   Text(
                                      //     'No file uploaded',
                                      //     style: TextStyle(
                                      //       fontSize: 13,
                                      //       color: Colors.grey.shade600,
                                      //     ),
                                      //   ),
                                      const SizedBox(height: 9),
                                      Divider(
                                        color: Colors.grey.shade200,
                                        thickness: 1,
                                        height: 1,
                                      ),
                                      const SizedBox(height: 9),
                                      Row(
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today,
                                                size: 14,
                                                color: Colors.grey.shade500,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                _formatDate(
                                                  invoice['date'] ??
                                                      'No date found',
                                                ),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          Row(
                                            children: [
                                              if (invoice['ai_status'] ==
                                                  "AI_FAILED")
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 10,
                                                      ),
                                                  child: IconButton(
                                                    onPressed:
                                                        _reprocessingIds
                                                                .contains(
                                                                  invoice['id'],
                                                                )
                                                            ? null
                                                            : () async {
                                                              final invoiceId =
                                                                  invoice['id'];
                                                              setState(() {
                                                                _reprocessingIds
                                                                    .add(
                                                                      invoiceId,
                                                                    );
                                                              });
                                                              try {
                                                                // Extract uploaded file IDs from the invoice data
                                                                final uploadedFiles =
                                                                    invoice['uploaded_files'];
                                                                List<String> fileIds = [];
                                                                if (uploadedFiles is List &&
                                                                    uploadedFiles.isNotEmpty) {
                                                                  fileIds = uploadedFiles
                                                                      .map((f) =>
                                                                          f['id']?.toString())
                                                                      .where((id) => id != null)
                                                                      .cast<String>()
                                                                      .toList();
                                                                }
                                                                print(
                                                                  '🔄 Reprocessing invoice $invoiceId with file IDs: $fileIds',
                                                                );
                                                                final result = await InvoiceListService()
                                                                    .reprocessInvoice(
                                                                      id: invoiceId,
                                                                      uploadedFileIds:
                                                                          fileIds.isNotEmpty
                                                                              ? fileIds
                                                                              : null,
                                                                    );
                                                                print('✅ Reprocess result: $result');
                                                                if (mounted) {
                                                                  setState(() {
                                                                    final invoiceIndex =
                                                                        _invoices.indexWhere(
                                                                          (
                                                                            inv,
                                                                          ) =>
                                                                              inv['id'] ==
                                                                              invoiceId,
                                                                        );
                                                                    if (invoiceIndex !=
                                                                        -1) {
                                                                      _invoices[invoiceIndex]['ai_status'] =
                                                                          'AI_PROCESSING';
                                                                    }
                                                                  });
                                                                  ScaffoldMessenger.of(
                                                                    context,
                                                                  ).showSnackBar(
                                                                    SnackBar(
                                                                      content:
                                                                          const Text(
                                                                            'Invoice reprocessing started successfully',
                                                                          ),
                                                                      backgroundColor:
                                                                          Colors
                                                                              .green
                                                                              .shade400,
                                                                      behavior:
                                                                          SnackBarBehavior
                                                                              .floating,
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                  );
                                                                }
                                                              } catch (e) {
                                                                print(
                                                                  '❌ AI Reprocess Error: $e',
                                                                );
                                                                if (mounted) {
                                                                  ScaffoldMessenger.of(
                                                                    context,
                                                                  ).showSnackBar(
                                                                    SnackBar(
                                                                      content: Text(
                                                                        'AI Processing Failed: ${e.toString().replaceAll('Exception: ', '')}',
                                                                      ),
                                                                      backgroundColor:
                                                                          Colors
                                                                              .red
                                                                              .shade400,
                                                                      behavior:
                                                                          SnackBarBehavior
                                                                              .floating,
                                                                      shape: RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                  );
                                                                }
                                                              } finally {
                                                                if (mounted) {
                                                                  setState(() {
                                                                    _reprocessingIds
                                                                        .remove(
                                                                          invoiceId,
                                                                        );
                                                                  });
                                                                }
                                                              }
                                                            },
                                                    icon:
                                                        _reprocessingIds
                                                                .contains(
                                                                  invoice['id'],
                                                                )
                                                            ? SizedBox(
                                                              width: 24,
                                                              height: 24,
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                valueColor:
                                                                    AlwaysStoppedAnimation(
                                                                      Colors
                                                                          .blue[900]!,
                                                                    ),
                                                              ),
                                                            )
                                                            : Icon(
                                                              CupertinoIcons
                                                                  .arrow_clockwise,
                                                              color:
                                                                  Colors
                                                                      .blue[900],
                                                            ),
                                                  ),
                                                ),
                                              _getStatusChip(
                                                invoice['ai_status'],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ],
          ),
          if (_loadingPreviewId != null)
            Container(
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E88E5)),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () async {
            final deviceInfo = await DeviceInfoPlugin().androidInfo;
            final androidVersion = deviceInfo.version.sdkInt;

            var cameraStatus = await Permission.camera.status;
            bool storageStatus;

            if (androidVersion >= 33) {
              // Check photos permission for Android 13+
              storageStatus = await Permission.photos.status.then(
                (status) => status.isGranted,
              );
            } else {
              // Check traditional storage permission for Android 12-
              storageStatus = await Permission.storage.status.then(
                (status) => status.isGranted,
              );
            }

            print("The camera status: $cameraStatus");
            print(
              "The storage status: ${storageStatus ? 'granted' : 'denied'}",
            );

            if (!cameraStatus.isGranted || !storageStatus) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Please grant camera and storage permissions to add photos or documents.',
                  ),
                  backgroundColor: Colors.red.shade400,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
              return;
            }
            _showUploadOptions(context);
          },
          backgroundColor: Color(0xFF192155),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.upload_rounded, size: 20),
          label: const Text('Upload', style: TextStyle(fontSize: 14)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
