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
      barrierColor: const Color(0xFF0B0F26).withOpacity(0.55),
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF192155).withOpacity(0.25),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2A3577),
                          Color(0xFF141B44),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF141B44).withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Log Out',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF192155),
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will need to sign in again to access your invoices and account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: const Color(0xFFF3F4F7),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF2A3577),
                                  Color(0xFF141B44)
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF141B44).withOpacity(0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.pop(context);
                                _logout(context);
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 13),
                                child: Text(
                                  'Log Out',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Color _getCategoryAccentColor(String? categoryName) {
    final String name = (categoryName ?? 'Uncategorized').toLowerCase();
    if (name == 'all') return const Color(0xFF192155);
    const List<Color> palette = [
      Color(0xFF7C5CFA), // purple
      Color(0xFF3CBD6B), // green
      Color(0xFF1E88E5), // blue
      Color(0xFFE8A33D), // amber
      Color(0xFFE0577B), // pink
      Color(0xFF19A7A0), // teal
      Color(0xFF6C63FF), // indigo
      Color(0xFFEF6C4D), // orange
    ];
    final int hash = name.codeUnits.fold(0, (sum, code) => sum + code);
    return palette[hash % palette.length];
  }

  IconData _getCategoryIcon(String? categoryName) {
    switch ((categoryName ?? '').toLowerCase()) {
      case 'all':
        return Icons.apps_rounded;
      case 'capex':
        return Icons.account_balance_rounded;
      case 'chemical':
        return Icons.science_rounded;
      case 'document':
        return Icons.description_rounded;
      case 'fuel':
        return Icons.local_gas_station_rounded;
      case 'grain':
        return Icons.grass_rounded;
      case 'invoices':
        return Icons.receipt_long_rounded;
      case 'others':
        return Icons.more_horiz_rounded;
      case 'services':
        return Icons.handyman_rounded;
      case 'store and spares':
        return Icons.inventory_2_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  void _showCategoriesFilterDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
              maxWidth: 420,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 14, 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF192155).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.category_rounded,
                            color: Color(0xFF192155),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Category',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF192155),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_categories.length} categories available',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.grey.shade100,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => Navigator.pop(context),
                            child: Padding(
                              padding: const EdgeInsets.all(7),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),

                  // Category list
                  Flexible(
                    child:
                        _categories.isEmpty
                            ? Padding(
                              padding: const EdgeInsets.all(36),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: const Color(0xFF192155),
                                  strokeWidth: 2.4,
                                ),
                              ),
                            )
                            : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                10,
                                12,
                                10,
                              ),
                              itemCount: _categories.length,
                              separatorBuilder:
                                  (_, __) => const SizedBox(height: 3),
                              itemBuilder: (context, index) {
                                final category = _categories[index];
                                final bool isSelected =
                                    _selectedCategory?['id'] ==
                                    category['id'];
                                final Color accent = _getCategoryAccentColor(
                                  category['name'],
                                );
                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      setState(() {
                                        _selectedCategory = category;
                                        _fetchInvoices(
                                          search:
                                              _searchQuery.isNotEmpty
                                                  ? _searchQuery
                                                  : null,
                                          categoryId:
                                              category['id']?.toString(),
                                        );
                                      });
                                      Navigator.pop(context);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 150,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            isSelected
                                                ? const Color(
                                                  0xFF192155,
                                                ).withOpacity(0.06)
                                                : Colors.transparent,
                                        borderRadius: BorderRadius.circular(
                                          14,
                                        ),
                                        border: Border.all(
                                          color:
                                              isSelected
                                                  ? const Color(
                                                    0xFF192155,
                                                  ).withOpacity(0.22)
                                                  : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: accent.withOpacity(0.14),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Icon(
                                              _getCategoryIcon(
                                                category['name'],
                                              ),
                                              size: 16,
                                              color: accent,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              category['name'] ?? '',
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight:
                                                    isSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                color:
                                                    isSelected
                                                        ? const Color(
                                                          0xFF192155,
                                                        )
                                                        : Colors
                                                            .grey
                                                            .shade800,
                                              ),
                                            ),
                                          ),
                                          AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 150,
                                            ),
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color:
                                                  isSelected
                                                      ? const Color(
                                                        0xFF192155,
                                                      )
                                                      : Colors.transparent,
                                              border: Border.all(
                                                color:
                                                    isSelected
                                                        ? const Color(
                                                          0xFF192155,
                                                        )
                                                        : Colors
                                                            .grey
                                                            .shade300,
                                                width: 1.6,
                                              ),
                                            ),
                                            child:
                                                isSelected
                                                    ? const Icon(
                                                      Icons.check_rounded,
                                                      size: 13,
                                                      color: Colors.white,
                                                    )
                                                    : null,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade200),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
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
      },
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
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header ────────────────────────────
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFF3F4FB), Colors.white],
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF192155),
                                      Color(0xFF2E3A78),
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Review AI Extracted Data',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17.5,
                                        color: Color(0xFF192155),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Please confirm the details before saving',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(height: 1, color: const Color(0xFFE3E5EE)),

                          // Form (scrollable if really needed)
                          Expanded(
                            child: Form(
                              key: _formKey,
                              child: SingleChildScrollView(
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  16 + MediaQuery.of(context).viewInsets.bottom,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _sectionLabel('Company Details'),
                                    const SizedBox(height: 10),
                                    DropdownButtonFormField<String>(
                                      decoration: _inputDecoration(
                                        'Select Company',
                                        icon: Icons.apartment_rounded,
                                      ),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF2E3A78),
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
                                    const SizedBox(height: 14),
                                    DropdownButtonFormField<String>(
                                      decoration: _inputDecoration(
                                        'Category',
                                        icon: Icons.category_rounded,
                                      ),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: Color(0xFF2E3A78),
                                      ),
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
                                    const SizedBox(height: 22),
                                    _sectionLabel('Invoice Information'),
                                    const SizedBox(height: 10),
                                    TextField(
                                      decoration: _inputDecoration(
                                        'Invoice Number',
                                        icon: Icons.confirmation_number_outlined,
                                      ),
                                      controller: invoiceNumberController,
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      decoration: _inputDecoration(
                                        'Company Name',
                                        icon: Icons.business_rounded,
                                      ),
                                      controller: companyNameController,
                                      validator:
                                          (value) =>
                                              (value == null ||
                                                      value.trim().isEmpty)
                                                  ? 'Please enter a company name'
                                                  : null,
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      decoration: _inputDecoration(
                                        'Invoice Date',
                                        icon: Icons.event_rounded,
                                      ).copyWith(
                                        suffixIcon: IconButton(
                                          icon: const Icon(
                                            Icons.calendar_today,
                                            color: Color(0xFF192155),
                                            size: 19,
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
                                    const SizedBox(height: 14),
                                    TextField(
                                      decoration: _inputDecoration(
                                        'Amount',
                                        icon: Icons.currency_rupee_rounded,
                                      ),
                                      controller: amountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    ),
                                    const SizedBox(height: 22),
                                    _sectionLabel('Additional Notes'),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      decoration: _inputDecoration(
                                        'Remark',
                                        icon: Icons.sticky_note_2_outlined,
                                      ),
                                      controller: remarkController,
                                      validator:
                                          (value) =>
                                              (value == null ||
                                                      value.trim().isEmpty)
                                                  ? 'Please enter a remark'
                                                  : null,
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        Container(height: 1, color: const Color(0xFFE3E5EE)),

                          // Buttons
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                            child: Row(
                            children: [
                              Expanded(
                              child: OutlinedButton(
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
                                  foregroundColor: const Color(0xFF6B7280),
                                  side: const BorderSide(
                                    color: Color(0xFFE3E5EE),
                                    width: 1.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                  ),
                                ),
                              ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                              flex: 2,
                              child: ElevatedButton(
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
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_rounded, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Confirm',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ),
                            ],
                            ),
                          ),
                        ],
                      ),

                    // Close button
                    Positioned(
                      top: 14,
                      right: 14,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE3E5EE)),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: const Icon(
                            Icons.close,
                            size: 17,
                            color: Color(0xFF6B7280),
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
  InputDecoration _inputDecoration(String label, {IconData? icon}) {
    const navy = Color(0xFF192155);
    const navySoft = Color(0xFF2E3A78);
    const border = Color(0xFFE3E5EE);
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF6B7280),
        fontWeight: FontWeight.w600,
        fontSize: 13.5,
      ),
      floatingLabelStyle: const TextStyle(
        color: navy,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      prefixIcon: icon != null ? Icon(icon, size: 19, color: navySoft) : null,
      filled: true,
      fillColor: const Color(0xFFF7F8FC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: navy, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
    );
  }

  /// Small uppercase section header used inside the review dialog
  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: Color(0xFF2E3A78),
      ),
    );
  }

  void _showUploadOptions(BuildContext context) {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        var cameraStatus = Permission.camera.status;
        var storageStatus = Permission.storage.status;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                // const Color(0xFF192155).withOpacity(0.5),
                Colors.white,
                Colors.white,
              ],
              stops: const [0.0, 0.35],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Upload Invoices',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color.fromARGB(255, 7, 13, 57),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how you\'d like to add your invoice',
                    style: TextStyle(fontSize: 13, color: const Color.fromARGB(255, 54, 54, 54)),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildUploadOptionCard(
                          icon: Icons.camera_alt_rounded,
                          gradientColors: const [
                            Color(0xFF6C8DFA),
                            Color(0xFF7C5CFA),
                          ],
                          title: 'Camera',
                          subtitle: 'Snap a photo of\nyour invoice.',
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
                                if (![
                                  'jpg',
                                  'jpeg',
                                  'png',
                                ].contains(extension)) {
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                ScaffoldMessenger.of(
                                  parentContext,
                                ).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Photo capture cancelled',
                                    ),
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
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildUploadOptionCard(
                          icon: Icons.folder_rounded,
                          gradientColors: const [
                            Color(0xFFFFA751),
                            Color(0xFFE8722A),
                          ],
                          title: 'Files',
                          subtitle: 'Select documents\nfrom your device.',
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
                              FilePickerResult? result = await FilePicker
                                  .platform
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
                                    result.files
                                        .map((f) => File(f.path!))
                                        .toList();
                                int imageCount =
                                    files
                                        .where(
                                          (f) =>
                                              ['jpg', 'jpeg', 'png'].contains(
                                                f.path
                                                    .split('.')
                                                    .last
                                                    .toLowerCase(),
                                              ),
                                        )
                                        .length;
                                int docCount =
                                    files
                                        .where(
                                          (f) =>
                                              ['pdf', 'doc', 'docx'].contains(
                                                f.path
                                                    .split('.')
                                                    .last
                                                    .toLowerCase(),
                                              ),
                                        )
                                        .length;

                                if (imageCount > 0 && docCount > 0) {
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                  ScaffoldMessenger.of(
                                    parentContext,
                                  ).showSnackBar(
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
                                        files
                                            .first; // Replace existing document
                                    _selectedImages = [];
                                    _isPhotoTaken = false;
                                  }
                                });
                                _showSelectedFilesModal(parentContext, "File");
                              } else {
                                if (!mounted) return;
                                ScaffoldMessenger.of(
                                  parentContext,
                                ).showSnackBar(
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  InkWell(
                    onTap: () => Navigator.pop(bottomSheetContext),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        'Cancel',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
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
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Header
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF192155), Color(0xFF2A3577)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF192155,
                                  ).withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Icon(
                              selectedMode == "Photo"
                                  ? Icons.camera_alt_rounded
                                  : Icons.description_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Upload Invoices',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF192155),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Review your selection before submitting',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Compression UI - Show over existing content
                      if (isCompressing)
                        Container(
                          padding: const EdgeInsets.all(24.0),
                          margin: const EdgeInsets.symmetric(vertical: 16.0),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF192155).withOpacity(0.06),
                                Colors.white,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16.0),
                            border: Border.all(
                              color: Color(0xFF192155).withOpacity(0.15),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              const SizedBox(
                                width: 34,
                                height: 34,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  valueColor: AlwaysStoppedAnimation(
                                    Color(0xFF192155),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Compressing image...',
                                style: TextStyle(
                                  fontSize: 15.5,
                                  color: Color(0xFF192155),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Please wait while we optimize your file',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
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
                            strokeWidth: 1.4,
                            radius: const Radius.circular(16.0),
                            color: const Color(0xFF192155).withOpacity(0.35),
                            padding: const EdgeInsets.all(0),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: 26.0,
                              horizontal: 16.0,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF192155).withOpacity(0.03),
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF192155,
                                    ).withOpacity(0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.cloud_upload_outlined,
                                    color: const Color(0xFF192155),
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Supports 1 PDF/DOC/DOCX or up to 3 PNG/JPG (10MB each)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Selected files count (hide during compression)
                      if (!isCompressing)
                        Row(
                          children: [
                            Icon(
                              Icons.folder_copy_rounded,
                              size: 17,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              selectedMode == "Photo"
                                  ? 'Selected Photo'
                                  : 'Selected Files',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF192155),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF192155,
                                ).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                selectedMode == "Photo"
                                    ? '${tempSelectedImages.length}/3'
                                    : '${(tempSelectedFile != null ? 1 : 0) + tempSelectedImages.length}/1',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF192155),
                                ),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 10),

                      // Files list or no files message (hide during compression)
                      if (!isCompressing && !hasSelected)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Text(
                            'No files selected',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade500,
                            ),
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
                                margin: const EdgeInsets.only(bottom: 10.0),
                                padding: const EdgeInsets.all(10.0),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14.0),
                                  border: Border.all(
                                    color: Colors.grey.shade100,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF192155,
                                      ).withOpacity(0.06),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF192155,
                                            ).withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Icon(
                                            isPdf
                                                ? Icons.picture_as_pdf_rounded
                                                : isImage
                                                ? Icons.image_rounded
                                                : Icons.insert_drive_file_rounded,
                                            color: const Color(0xFF192155),
                                            size: 19,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            trimmedFileName,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF192155),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isImage || isPdf)
                                          IconButton(
                                            icon: Icon(
                                              Icons.remove_red_eye_rounded,
                                              color: Colors.blue.shade600,
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
                                          icon: Icon(
                                            Icons.close_rounded,
                                            color: Colors.red.shade400,
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
                                        left: 48.0,
                                        top: 6.0,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          fileSize,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),

                      const SizedBox(height: 20),
                      Divider(color: Colors.grey.shade200, height: 1),
                      const SizedBox(height: 16),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
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
                                      : Colors.grey.shade200,
                              foregroundColor:
                                  hasSelected && !isCompressing
                                      ? Colors.white
                                      : Colors.grey.shade500,
                              elevation: hasSelected && !isCompressing ? 2 : 0,
                              shadowColor: const Color(
                                0xffFF9635,
                              ).withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                            icon: const Icon(
                              Icons.refresh_rounded,
                              size: 17,
                            ),
                            label: const Text(
                              'Reset',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                          child: ElevatedButton(
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
                                      : Colors.grey.shade200,
                              foregroundColor:
                                  isUploadEnabled &&
                                          tempSelectedImages.length < 3 &&
                                          !isCompressing
                                      ? Colors.white
                                      : Colors.grey.shade500,
                              elevation:
                                  isUploadEnabled &&
                                          tempSelectedImages.length < 3 &&
                                          !isCompressing
                                      ? 2
                                      : 0,
                              shadowColor: const Color(
                                0xFF4A90E2,
                              ).withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.add_rounded, size: 17),
                                SizedBox(width: 6),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                          child: ElevatedButton(
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
                                      : Colors.grey.shade300,
                              foregroundColor: Colors.white,
                              elevation: hasSelected && !isCompressing ? 3 : 0,
                              shadowColor: const Color(
                                0xFF192155,
                              ).withOpacity(0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 13,
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
                                        Icon(
                                          Icons.send_rounded,
                                          size: 17,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Submit',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ],
                                    ),
                          ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
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

  Widget _buildUploadOptionCard({
    required IconData icon,
    required List<Color> gradientColors,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // colors: [gradientColors.first.withOpacity(0.07), Colors.white],
            colors: [gradientColors.first.withOpacity(0.07), gradientColors.last.withOpacity(0.07)]
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withOpacity(0.22),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 92,
              height: 86,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: gradientColors.last.withOpacity(0.14),
                    ),
                  ),
                  Positioned(
                    left: 4,
                    top: 12,
                    child: Transform.rotate(
                      angle: -0.24,
                      child: Container(
                        width: 28,
                        height: 38,
                        decoration: BoxDecoration(
                          color: gradientColors.first.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 12,
                    child: Transform.rotate(
                      angle: 0.24,
                      child: Container(
                        width: 28,
                        height: 38,
                        decoration: BoxDecoration(
                          color: gradientColors.last.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradientColors,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: gradientColors.last.withOpacity(0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 28, color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF192155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.grey.shade500,
                height: 1.35,
              ),
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

  Map<String, dynamic> _fileTypeMeta(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return {'icon': Icons.picture_as_pdf_rounded, 'color': const Color(0xFFD64545)};
      case 'doc':
      case 'docx':
        return {'icon': Icons.description_rounded, 'color': const Color(0xFF1E88E5)};
      case 'xls':
      case 'xlsx':
        return {'icon': Icons.grid_on_rounded, 'color': const Color(0xFF3CBD6B)};
      default:
        return {'icon': Icons.insert_drive_file_rounded, 'color': const Color(0xFF7C5CFA)};
    }
  }

  Widget _previewAppBarAction({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: Colors.white.withOpacity(0.14),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: Colors.white, size: 20),
          onPressed: onPressed,
        ),
      ),
    );
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

          // If there is exactly one file overall (image or document), open
          // it directly in the dedicated full-screen viewer so it fills the
          // whole screen instead of sitting in a small card with empty space.
          final int totalFilesCount = imageUrls.length + nonImageUrls.length;
          if (totalFilesCount == 1) {
            final url = imageUrls.isNotEmpty ? imageUrls.first : nonImageUrls.first;
            final extension = _getExtensionFromUrl(url);
            final fileName =
                Uri.parse(url).pathSegments.isNotEmpty
                    ? Uri.parse(url).pathSegments.last
                    : url.split('/').last;
            return _buildFileViewerScaffold(
              title: 'Invoice Preview',
              subtitle: fileName,
              body: _buildInvoiceContent(url, extension),
              onDownload: () => _downloadInvoice(url, fileName),
            );
          }

          // If images or mixed files
          final int totalFiles = imageUrls.length + nonImageUrls.length;
          return Scaffold(
            backgroundColor: const Color(0xFFE9EBF3),
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2A3577), Color(0xFF141B44)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Invoices Preview',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '$totalFiles file${totalFiles == 1 ? '' : 's'} attached',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (imageUrls.isNotEmpty)
                          _previewAppBarAction(
                            icon: Icons.download_rounded,
                            tooltip: 'Download all images',
                            onPressed: () async {
                              for (var imgUrl in imageUrls) {
                                final imgFileName =
                                    Uri.parse(imgUrl).pathSegments.isNotEmpty
                                        ? Uri.parse(imgUrl).pathSegments.last
                                        : imgUrl.split('/').last;
                                await _downloadInvoice(imgUrl, imgFileName);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
              children: [
                if (imageUrls.isNotEmpty) ...[
                  Text(
                    'IMAGES',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var imgUrl in imageUrls)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF192155).withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _openFullScreenImage(context, imgUrl),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Container(
                                  width: double.infinity,
                                  height: 340,
                                  color: const Color(0xFFF3F4F7),
                                  child: Image.network(
                                    imgUrl,
                                    width: double.infinity,
                                    height: 340,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        height: 340,
                                        alignment: Alignment.center,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: const Color(0xFF192155),
                                          value: progress.expectedTotalBytes != null
                                              ? progress.cumulativeBytesLoaded /
                                                  (progress.expectedTotalBytes ?? 1)
                                              : null,
                                        ),
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) => Container(
                                          height: 340,
                                          alignment: Alignment.center,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.broken_image_rounded,
                                                  color: Colors.grey.shade400, size: 32),
                                              const SizedBox(height: 6),
                                              Text('Failed to load image',
                                                  style: TextStyle(
                                                      color: Colors.grey.shade500,
                                                      fontSize: 12.5)),
                                            ],
                                          ),
                                        ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Material(
                                  color: Colors.black.withOpacity(0.45),
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    icon: const Icon(Icons.fullscreen_rounded,
                                        color: Colors.white, size: 20),
                                    onPressed: () =>
                                        _openFullScreenImage(context, imgUrl),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                if (nonImageUrls.isNotEmpty) ...[
                  Text(
                    'DOCUMENTS',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var fileUrl in nonImageUrls)
                    Builder(builder: (context) {
                      final ext = _getExtensionFromUrl(fileUrl);
                      final meta = _fileTypeMeta(ext);
                      final fileFileName =
                          Uri.parse(fileUrl).pathSegments.isNotEmpty
                              ? Uri.parse(fileUrl).pathSegments.last
                              : fileUrl.split('/').last;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF192155).withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => _buildFileViewerScaffold(
                                    title: 'Invoice Preview',
                                    subtitle: fileFileName,
                                    body: _buildInvoiceContent(fileUrl, ext),
                                    onDownload: () =>
                                        _downloadInvoice(fileUrl, fileFileName),
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: (meta['color'] as Color)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(meta['icon'] as IconData,
                                        color: meta['color'] as Color, size: 21),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fileFileName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF192155),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Tap to view · ${ext.toUpperCase()}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Colors.grey.shade500,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded,
                                      color: Colors.grey.shade400),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Scaffold _buildFileViewerScaffold({
    required String title,
    required String subtitle,
    required Widget body,
    required VoidCallback onDownload,
  }) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9EBF3),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(68),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A3577), Color(0xFF141B44)],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.62),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _previewAppBarAction(
                    icon: Icons.download_rounded,
                    tooltip: 'Download',
                    onPressed: onDownload,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: body,
    );
  }

  void _openFullScreenImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 5,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 44,
                    right: 16,
                    child: Material(
                      color: Colors.white.withOpacity(0.15),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Wraps the raw document/image viewer in a framed "paper document" card so
  // the preview reads like an actual invoice sitting on a desk, instead of a
  // flat full-bleed viewer.
  Widget _invoiceDocumentFrame({required Widget child}) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE9EBF3), Color(0xFFDDE0EC)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 6),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF192155).withOpacity(0.18),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildInvoiceContent(String completeUrl, String extension) {
    if (['jpg', 'jpeg', 'png'].contains(extension)) {
      return _invoiceDocumentFrame(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(
                completeUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const CircularProgressIndicator(
                    color: Color(0xFF192155),
                  );
                },
                errorBuilder:
                    (context, error, stackTrace) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_rounded,
                            color: Colors.grey.shade400, size: 36),
                        const SizedBox(height: 8),
                        Text('Failed to load image',
                            style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
              ),
            ),
          ),
        ),
      );
    } else if (extension == 'pdf') {
      return _invoiceDocumentFrame(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: FutureBuilder<String?>(
            future: SharedPreferences.getInstance().then(
              (p) => p.getString('token'),
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF192155)),
                );
              }
              return SfPdfViewer.network(
                completeUrl,
                enableDoubleTapZooming: true,
                enableDocumentLinkAnnotation: false,
                headers:
                    snapshot.data != null
                        ? {'Authorization': 'Bearer ${snapshot.data}'}
                        : {},
              );
            },
          ),
        ),
      );
    } else {
      return _invoiceDocumentFrame(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: Colors.red.shade300, size: 36),
                const SizedBox(height: 8),
                Text(
                  'Unsupported file format',
                  style: TextStyle(color: Colors.red.shade400, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
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
        options:
            token != null
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

  Color _getStatusAccentColor(String? status) {
    final statusText = (status ?? '').toUpperCase().replaceAll('_', ' ');
    switch (statusText) {
      case 'AI PROCESSED':
        return const Color(0xFF2FA65A);
      case 'AI FAILED':
        return const Color(0xFFE05353);
      case 'AI PROCESSING':
        return const Color(0xFFE0A527);
      default:
        return const Color(0xFF3E7BFA);
    }
  }

  Widget _getStatusChip(String? status) {
    final statusText = (status ?? 'actuator').replaceAll('_', ' ');
    Color bgColor;
    Color textColor;

    switch (statusText.toUpperCase()) {
      case 'AI PROCESSED':
        bgColor = const Color(0xFFDFF5E3);
        textColor = const Color(0xFF1E8A44);
        break;
      case 'AI FAILED':
        bgColor = const Color(0xFFFBE0E0);
        textColor = const Color(0xFFC62828);
        break;
      case 'AI PROCESSING':
        bgColor = const Color(0xFFFFF1D6);
        textColor = const Color(0xFFB4740E);
        break;
      default:
        bgColor = const Color(0xFFDCE7FB);
        textColor = const Color(0xFF1E5FBF);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        statusText.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
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
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF192155), Color(0xFF2A3577)],
            ),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(26),
              bottomRight: Radius.circular(26),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF192155).withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Center(
                    child: Text(
                      'Invoice Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                        tooltip: 'Logout',
                        onPressed: () => _showLogoutConfirmation(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF192155).withOpacity(0.08),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Search invoices...',
                            hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 15,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.grey.shade400,
                              size: 22,
                            ),
                            suffixIcon:
                                _searchController.text.isNotEmpty
                                    ? IconButton(
                                      icon: Icon(
                                        Icons.clear_rounded,
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
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient:
                            _selectedCategory?['id'] == null
                                ? null
                                : const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF192155),
                                    Color(0xFF2A3577),
                                  ],
                                ),
                        color:
                            _selectedCategory?['id'] == null
                                ? Colors.white
                                : null,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            _selectedCategory?['id'] == null
                                ? Border.all(color: Colors.grey.shade100)
                                : null,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF192155).withOpacity(
                              _selectedCategory?['id'] == null ? 0.08 : 0.28,
                            ),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.tune_rounded,
                          color:
                              _selectedCategory?['id'] == null
                                  ? Colors.grey.shade500
                                  : Colors.white,
                          size: 22,
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
                              borderRadius: BorderRadius.circular(18),
                              splashColor: Color(0xFF192155).withOpacity(0.15),
                              hoverColor: Colors.grey.shade100,
                              highlightColor: Colors.grey.shade100.withOpacity(
                                0.6,
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.grey.shade100,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF192155,
                                      ).withOpacity(0.08),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 3,
                                          color: _getStatusAccentColor(
                                            invoice['ai_status'],
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          11,
                                          12,
                                          11,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  decoration: BoxDecoration(
                                                    gradient:
                                                        const LinearGradient(
                                                          begin:
                                                              Alignment.topLeft,
                                                          end:
                                                              Alignment
                                                                  .bottomRight,
                                                          colors: [
                                                            Color(0xFF7C5CFA),
                                                            Color(0xFF6C4DDA),
                                                          ],
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(
                                                          0xFF6C4DDA,
                                                        ).withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          0,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .description_rounded,
                                                        size: 10,
                                                        color: Colors.white,
                                                      ),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        invoice['category']?['name'] ??
                                                            'Uncategorized',
                                                        style: const TextStyle(
                                                          fontSize: 9.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    gradient:
                                                        const LinearGradient(
                                                          begin:
                                                              Alignment.topLeft,
                                                          end:
                                                              Alignment
                                                                  .bottomRight,
                                                          colors: [
                                                            Color(0xFF3CBD6B),
                                                            Color(0xFF2FA65A),
                                                          ],
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(
                                                          0xFF2FA65A,
                                                        ).withOpacity(0.3),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          0,
                                                          1,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  child: Text(
                                                    invoice['invoiced_to'] ??
                                                        'No Company Found',
                                                    style: const TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: SingleChildScrollView(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: Text(
                                                      invoice['invoice_number'] ==
                                                              null
                                                          ? "No invoice number found"
                                                          : "#INV-${invoice['invoice_number']}",
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 14.5,
                                                        color: Color(
                                                          0xFF192155,
                                                        ),
                                                        letterSpacing: 0.1,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF192155,
                                                    ).withOpacity(0.08),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    '₹${invoice['amount'] ?? '0'}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 13.5,
                                                      color: Color(0xFF192155),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Container(
                                                  width: 18,
                                                  height: 18,
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade100,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(
                                                    Icons.business_rounded,
                                                    size: 11,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    invoice['company']?['name'] ??
                                                        'No company found',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Divider(
                                              color: Colors.grey.shade200,
                                              thickness: 1,
                                              height: 1,
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .calendar_today_outlined,
                                                      size: 13,
                                                      color:
                                                          Colors.grey.shade500,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      _formatDate(
                                                        invoice['date'] ??
                                                            'No date found',
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            Colors
                                                                .grey
                                                                .shade700,
                                                        fontWeight:
                                                            FontWeight.w500,
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
                                                              left: 6,
                                                            ),
                                                        child: IconButton(
                                                          padding:
                                                              EdgeInsets.zero,
                                                          constraints:
                                                              const BoxConstraints(
                                                                minWidth: 30,
                                                                minHeight: 30,
                                                              ),
                                                          iconSize: 18,
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
                                                                      List<
                                                                        String
                                                                      >
                                                                      fileIds =
                                                                          [];
                                                                      if (uploadedFiles
                                                                              is List &&
                                                                          uploadedFiles
                                                                              .isNotEmpty) {
                                                                        fileIds =
                                                                            uploadedFiles
                                                                                .map(
                                                                                  (
                                                                                    f,
                                                                                  ) =>
                                                                                      f['id']?.toString(),
                                                                                )
                                                                                .where(
                                                                                  (
                                                                                    id,
                                                                                  ) =>
                                                                                      id !=
                                                                                      null,
                                                                                )
                                                                                .cast<
                                                                                  String
                                                                                >()
                                                                                .toList();
                                                                      }
                                                                      print(
                                                                        '🔄 Reprocessing invoice $invoiceId with file IDs: $fileIds',
                                                                      );
                                                                      final result = await InvoiceListService().reprocessInvoice(
                                                                        id:
                                                                            invoiceId,
                                                                        uploadedFileIds:
                                                                            fileIds.isNotEmpty
                                                                                ? fileIds
                                                                                : null,
                                                                      );
                                                                      print(
                                                                        '✅ Reprocess result: $result',
                                                                      );
                                                                      if (mounted) {
                                                                        setState(() {
                                                                          final invoiceIndex = _invoices.indexWhere(
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
                                                                            content: const Text(
                                                                              'Invoice reprocessing started successfully',
                                                                            ),
                                                                            backgroundColor:
                                                                                Colors.green.shade400,
                                                                            behavior:
                                                                                SnackBarBehavior.floating,
                                                                            shape: RoundedRectangleBorder(
                                                                              borderRadius: BorderRadius.circular(
                                                                                12,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        );
                                                                      }
                                                                    } catch (
                                                                      e
                                                                    ) {
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
                                                                      }
                                                                    } finally {
                                                                      if (mounted) {
                                                                        setState(() {
                                                                          _reprocessingIds.remove(
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
                                                                      strokeWidth:
                                                                          2,
                                                                      valueColor:
                                                                          AlwaysStoppedAnimation(
                                                                            Colors.blue[900]!,
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
        width: 88,
        height: 88,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF192155).withOpacity(0.12),
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A3577), Color(0xFF141B44)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF192155).withOpacity(0.4),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () async {
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
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.file_upload_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Upload',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}