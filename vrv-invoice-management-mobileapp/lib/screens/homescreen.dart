import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import '../providers/invoice_list_provider.dart';
import '../service/listservice.dart';
import 'package:dotted_border/dotted_border.dart';
import '../service/mainapi.dart';
import '../model/InoviceConfirmModel.dart';
import 'ai_processing.dart';
import 'extracted_review_screen.dart';
import 'send_otp.dart';
import '../widgets/app_animations.dart';
import '../widgets/home/category_filter_sheet.dart';
import '../widgets/home/home_app_bar.dart';
import '../widgets/home/home_invoice_list.dart';
import '../widgets/home/invoice_search_bar.dart';
import '../widgets/home/upload_bottom_sheet.dart';
import '../utils/invoice_display_utils.dart';
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

class InvoiceManagementScreen extends ConsumerStatefulWidget {
  const InvoiceManagementScreen({super.key});

  @override
  ConsumerState<InvoiceManagementScreen> createState() =>
      _InvoiceManagementScreenState();
}

class _InvoiceManagementScreenState
    extends ConsumerState<InvoiceManagementScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedFile;
  List<File> _selectedImages = [];
  Set<String> _reprocessingIds = <String>{};
  bool _isUploading = false;
  final ScrollController _scrollController = ScrollController();
  bool _isNavigating = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String? _loadingPreviewId;
  bool _isCameraPermissionGranted = false;
  bool _isStoragePermissionGranted = false;
  bool _isPhotoTaken = false;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(() {
      final listState = ref.read(invoiceListProvider);
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !listState.isLoadingMore &&
          listState.hasMore) {
        ref.read(invoiceListProvider.notifier).fetchMoreInvoices();
      }
    });
    _searchFocusNode.addListener(() {
      if (_isNavigating && _searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    });
  }

  void _showListErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _initPermissions() async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    final androidVersion = deviceInfo.version.sdkInt;

    final cameraStatus = await Permission.camera.status;
    bool storageStatus;

    if (androidVersion >= 33) {
      storageStatus = await Permission.photos.status.isGranted;
    } else {
      storageStatus = await Permission.storage.status.isGranted;
    }

    if (mounted) {
      setState(() {
        _isCameraPermissionGranted = cameraStatus.isGranted;
        _isStoragePermissionGranted = storageStatus;
      });
    }

    // Request permissions dynamically once if they are not granted
    if (!cameraStatus.isGranted || !storageStatus) {
      final cameraReq = await Permission.camera.request();
      bool storageReq;
      if (androidVersion >= 33) {
        final statuses = await [Permission.photos, Permission.videos].request();
        storageReq = statuses[Permission.photos]?.isGranted ?? false;
      } else {
        storageReq = await Permission.storage.request().isGranted;
      }

      if (mounted) {
        setState(() {
          _isCameraPermissionGranted = cameraReq.isGranted;
          _isStoragePermissionGranted = storageReq;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    ref.read(invoiceListProvider.notifier).setSearchQuery(query);
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final listState = ref.read(invoiceListProvider);
      ref
          .read(invoiceListProvider.notifier)
          .fetchInvoices(
            search: query.isNotEmpty ? query : null,
            categoryId: listState.selectedCategory?['id']?.toString(),
          );
    });
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      smoothPageRoute(SendOtpScreen()),
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
                        colors: [Color(0xFF2A3577), Color(0xFF141B44)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF2A3577).withOpacity(0.35),
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
                              padding: const EdgeInsets.symmetric(vertical: 13),
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
                                colors: [Color(0xFF2A3577), Color(0xFF141B44)],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF2A3577).withOpacity(0.3),
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

  void _showCategoriesFilterDialog() {
    final listState = ref.read(invoiceListProvider);
    CategoryFilterSheet.show(
      context,
      categories: listState.categories,
      selectedCategory: listState.selectedCategory,
      onCategorySelected: (category) {
        ref.read(invoiceListProvider.notifier).selectCategory(category);
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

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      useSafeArea: false,
      builder:
          (context) => const Dialog.fullscreen(child: AiProcessingScreen()),
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

      print('Showing review screen');

      final confirmResponse = InvoiceConfirmUploadResponse(
        message: 'Upload successful',
        uploadedFiles:
            responses
                .where((r) => r.uploadedFileId != null)
                .map((r) => UploadedFile(id: r.uploadedFileId!, url: ''))
                .toList(),
        aiData: AiData(
          invoiceNumber:
              responses.isNotEmpty ? responses[0].invoiceNumber ?? '' : '',
          companyName:
              responses.isNotEmpty ? responses[0].vendorName ?? '' : '',
          invoiceDate: _formatDateToYYYYMMDD(
            responses.isNotEmpty
                ? responses[0].date ?? DateTime.now().toIso8601String()
                : DateTime.now().toIso8601String(),
          ),
          amount: responses.isNotEmpty ? responses[0].amount ?? 0.0 : 0.0,
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

      // Navigate to the full-screen ExtractedReviewScreen instead of a dialog.
      // This avoids the slow overlay animation and keyboard lag.
      final result = await Navigator.of(parentContext).push<ReviewScreenResult>(
        MaterialPageRoute(
          fullscreenDialog: false,
          builder:
              (_) => ExtractedReviewScreen(
                confirmResponse: confirmResponse,
                api: api,
                categories: categories,
              ),
        ),
      );

      // Map the result back to the same bool? contract as before
      final bool? isCommitted = result?.isCommitted;

      print('Review screen dismissed');

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
      } else if (isCommitted == false) {
        // Cancel button se band hui — pop animation khatam hone do pehle,
        // phir cleanup karo taaki multiple setState ek saath na aayein
        unawaited(() async {
          await Future.delayed(const Duration(milliseconds: 350));
          try {
            final uploadedFileIds =
                confirmResponse.uploadedFiles.map((f) => f.id).toList();
            if (uploadedFileIds.isNotEmpty) {
              await api
                  .cancelUpload(uploadedFileIds)
                  .timeout(
                    const Duration(seconds: 15),
                    onTimeout: () {
                      throw TimeoutException('cancelUpload timed out');
                    },
                  );
            }
          } catch (e) {
            print('Failed to cancel upload: $e');
          }
          try {
            await ref.read(invoiceListProvider.notifier).refreshAfterUpload();
          } catch (e) {
            print('Failed to refresh invoices after cancel: $e');
          }
          if (mounted) {
            setState(() {
              _selectedFile = null;
              _selectedImages.clear();
              _isPhotoTaken = false;
            });
          }
        }());
      } else if (isCommitted == null) {
        // Dialog X se band hui (dialog khud already gone hai yahan) —
        // baaki cleanup background mein karo taaki FAB/upload spinner
        // lambe time tak stuck na rahe agar cancelUpload slow/hang ho
        unawaited(() async {
          // Pop animation khatam hone do pehle
          await Future.delayed(const Duration(milliseconds: 350));
          try {
            final uploadedFileIds =
                confirmResponse.uploadedFiles.map((f) => f.id).toList();
            if (uploadedFileIds.isNotEmpty) {
              await api
                  .cancelUpload(uploadedFileIds)
                  .timeout(
                    const Duration(seconds: 15),
                    onTimeout: () {
                      throw TimeoutException('cancelUpload timed out');
                    },
                  );
            }
            if (mounted) {
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
            }
          } catch (e) {
            print('Failed to cancel upload: $e');
          }
          try {
            await ref.read(invoiceListProvider.notifier).refreshAfterUpload();
          } catch (e) {
            print('Failed to refresh invoices after cancel: $e');
          }
          if (mounted) {
            setState(() {
              _selectedFile = null;
              _selectedImages.clear();
              _isPhotoTaken = false;
            });
          }
        }());
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
      // Pop animation khatam hone do — phir setState karo warna
      // dialog close animation ke saath rebuild race kar sakta hai
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() => _isUploading = false);
        }
        print('Finished _uploadSelectedFiles');
      });
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

  void _showUploadOptions(BuildContext context) {
    UploadBottomSheet.show(
      context,
      onCameraTap: () => _handleCameraUpload(context),
      onFilesTap: () => _handleFilesUpload(context),
    );
  }

  Future<void> _handleCameraUpload(BuildContext parentContext) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (photo != null) {
        final newFile = File(photo.path);
        final extension = photo.path.split('.').last.toLowerCase();
        if (!['jpg', 'jpeg', 'png'].contains(extension)) {
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: const Text('Only JPG or PNG images are allowed.'),
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
              content: const Text('Image size exceeds 10MB limit.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          return;
        }
        setState(() {
          _selectedImages = [newFile];
          _selectedFile = null;
          _isPhotoTaken = true;
        });
        await _showSelectedFilesModal(parentContext, 'Photo');
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
  }

  Future<void> _handleFilesUpload(BuildContext parentContext) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
      );

      if (result != null && result.files.isNotEmpty) {
        final files = result.files.map((f) => File(f.path!)).toList();
        final imageCount =
            files
                .where(
                  (f) => [
                    'jpg',
                    'jpeg',
                    'png',
                  ].contains(f.path.split('.').last.toLowerCase()),
                )
                .length;
        final docCount =
            files
                .where(
                  (f) => [
                    'pdf',
                    'doc',
                    'docx',
                  ].contains(f.path.split('.').last.toLowerCase()),
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
              content: const Text('You can upload a maximum of 3 images.'),
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

        bool exceedsSize = false;
        for (final file in files) {
          final fileSize = await file.length();
          if (fileSize > 10 * 1024 * 1024) {
            exceedsSize = true;
            break;
          }
        }
        if (exceedsSize) {
          ScaffoldMessenger.of(parentContext).showSnackBar(
            SnackBar(
              content: const Text('One or more files exceed 10MB limit.'),
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
            _selectedImages = files;
            _selectedFile = null;
            _isPhotoTaken = false;
          } else {
            _selectedFile = files.first;
            _selectedImages = [];
            _isPhotoTaken = false;
          }
        });
        await _showSelectedFilesModal(parentContext, 'File');
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
  }

  Future<void> _showSelectedFilesModal(
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

    return showModalBottomSheet(
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
                        ),
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

                            // Async file size read to avoid sync I/O in itemBuilder
                            return FutureBuilder<int>(
                              future: file.length(),
                              builder: (context, snapshot) {
                                final fileSize =
                                    snapshot.hasData
                                        ? '${(snapshot.data! / (1024 * 1024)).toStringAsFixed(1)} MB'
                                        : '...';
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                                  : Icons
                                                      .insert_drive_file_rounded,
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
                                                  barrierLabel:
                                                      'Invoice Preview',
                                                  pageBuilder: (
                                                    context,
                                                    anim1,
                                                    anim2,
                                                  ) {
                                                    return Center(
                                                      child: Material(
                                                        color:
                                                            Colors.transparent,
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
                                                                offset:
                                                                    const Offset(
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
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          16,
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
                                                                      height:
                                                                          16,
                                                                    ),
                                                                    SizedBox(
                                                                      width:
                                                                          double
                                                                              .maxFinite,
                                                                      height:
                                                                          400,
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
                                                                      Icons
                                                                          .close,
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
                                                        (tempSelectedFile !=
                                                                null
                                                            ? 1
                                                            : 0),
                                                  );
                                                }
                                                if (tempSelectedImages
                                                    .isEmpty) {
                                                  isFromFilePicker = false;
                                                }
                                                if (tempSelectedFile == null &&
                                                    tempSelectedImages
                                                        .isEmpty) {
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
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 20),
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
                                elevation:
                                    hasSelected && !isCompressing ? 2 : 0,
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
                              icon: const Icon(Icons.refresh_rounded, size: 17),
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
                                  // File mode: single selection only (1 doc or 1 image)
                                  (selectedMode == "File"
                                              ? (tempSelectedFile == null &&
                                                  tempSelectedImages.isEmpty)
                                              : (tempSelectedImages.length <
                                                  3)) &&
                                          isUploadEnabled &&
                                          !isCompressing
                                      ? () async {
                                        if (selectedMode == "File") {
                                          // Single selection (never add a second file)
                                          try {
                                            FilePickerResult? result =
                                                await FilePicker.platform
                                                    .pickFiles(
                                                      allowMultiple: false,
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
                                                content: Text(
                                                  'Camera error: $e',
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
                                              behavior:
                                                  SnackBarBehavior.floating,
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
                                elevation:
                                    hasSelected && !isCompressing ? 3 : 0,
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
                                          Icon(Icons.send_rounded, size: 17),
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
            colors: [
              gradientColors.first.withOpacity(0.07),
              gradientColors.last.withOpacity(0.07),
            ],
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
        return {
          'icon': Icons.picture_as_pdf_rounded,
          'color': const Color(0xFFD64545),
        };
      case 'doc':
      case 'docx':
        return {
          'icon': Icons.description_rounded,
          'color': const Color(0xFF1E88E5),
        };
      case 'xls':
      case 'xlsx':
        return {
          'icon': Icons.grid_on_rounded,
          'color': const Color(0xFF3CBD6B),
        };
      default:
        return {
          'icon': Icons.insert_drive_file_rounded,
          'color': const Color(0xFF7C5CFA),
        };
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
      smoothPageRouteBuilder((context) {
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
          final url =
              imageUrls.isNotEmpty ? imageUrls.first : nonImageUrls.first;
          final extension = _getExtensionFromUrl(url);
          final fileName =
              Uri.parse(url).pathSegments.isNotEmpty
                  ? Uri.parse(url).pathSegments.last
                  : url.split('/').last;
          // Both images and PDFs open the same way: directly inside the
          // framed preview box, with zoom/pan available right there.
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
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
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
                Container(
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
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (int i = 0; i < imageUrls.length; i++) ...[
                        if (i != 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.grey.shade200,
                          ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap:
                                () =>
                                    _openFullScreenImage(context, imageUrls[i]),
                            child: Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  constraints: const BoxConstraints(
                                    minHeight: 220,
                                  ),
                                  color: const Color(0xFFF3F4F7),
                                  child: Image.network(
                                    imageUrls[i],
                                    width: double.infinity,
                                    fit: BoxFit.fitWidth,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return Container(
                                        height: 260,
                                        alignment: Alignment.center,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: const Color(0xFF192155),
                                          value:
                                              progress.expectedTotalBytes !=
                                                      null
                                                  ? progress
                                                          .cumulativeBytesLoaded /
                                                      (progress
                                                              .expectedTotalBytes ??
                                                          1)
                                                  : null,
                                        ),
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              height: 260,
                                              alignment: Alignment.center,
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.broken_image_rounded,
                                                    color: Colors.grey.shade400,
                                                    size: 32,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Failed to load image',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade500,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ],
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
                                      icon: const Icon(
                                        Icons.fullscreen_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed:
                                          () => _openFullScreenImage(
                                            context,
                                            imageUrls[i],
                                          ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.45),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${i + 1}/${imageUrls.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
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
                  Builder(
                    builder: (context) {
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
                                smoothPageRouteBuilder(
                                  (context) => _buildFileViewerScaffold(
                                    title: 'Invoice Preview',
                                    subtitle: fileFileName,
                                    body: _buildInvoiceContent(fileUrl, ext),
                                    onDownload:
                                        () => _downloadInvoice(
                                          fileUrl,
                                          fileFileName,
                                        ),
                                  ),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
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
                                    child: Icon(
                                      meta['icon'] as IconData,
                                      color: meta['color'] as Color,
                                      size: 21,
                                    ),
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
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
        );
      }),
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
                    builder:
                        (context) => IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
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
                        errorBuilder:
                            (context, error, stackTrace) => const Center(
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
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
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
                        Icon(
                          Icons.broken_image_rounded,
                          color: Colors.grey.shade400,
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
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
              return SfPdfViewerTheme(
                data: const SfPdfViewerThemeData(backgroundColor: Colors.white),
                child: SfPdfViewer.network(
                  completeUrl,
                  enableDoubleTapZooming: true,
                  enableDocumentLinkAnnotation: false,
                  headers:
                      snapshot.data != null
                          ? {'Authorization': 'Bearer ${snapshot.data}'}
                          : {},
                ),
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
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red.shade300,
                  size: 36,
                ),
                const SizedBox(height: 8),
                Text(
                  'Unsupported file format',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                  ),
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
    ref.listen<String?>(
      invoiceListProvider.select((state) => state.errorMessage),
      (previous, next) {
        if (next != null && next.isNotEmpty) {
          _showListErrorSnackBar(next);
          ref.read(invoiceListProvider.notifier).clearErrorMessage();
        }
      },
    );

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF3F4F7),
      appBar: HomeAppBar(
        onLogoutPressed: () => _showLogoutConfirmation(context),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final selectedCategory =
                      ref.watch(invoiceListProvider).selectedCategory;
                  return InvoiceSearchBar(
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    selectedCategory: selectedCategory,
                    onFilterPressed: _showCategoriesFilterDialog,
                  );
                },
              ),
              Expanded(
                child: HomeInvoiceList(
                  scrollController: _scrollController,
                  reprocessingIds: _reprocessingIds,
                  loadingPreviewId: _loadingPreviewId,
                  onLoadingPreviewIdChanged: (id) {
                    setState(() => _loadingPreviewId = id);
                  },
                  onReprocessingIdsChanged: (ids) {
                    setState(() => _reprocessingIds = ids);
                  },
                  onOpenPreview: _openInvoicesPreview,
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
                  storageStatus = await Permission.photos.status.isGranted;
                } else {
                  storageStatus = await Permission.storage.status.isGranted;
                }

                // Request permissions dynamically if missing
                if (!cameraStatus.isGranted || !storageStatus) {
                  final cameraReq = await Permission.camera.request();
                  bool storageReq;
                  if (androidVersion >= 33) {
                    final statuses =
                        await [Permission.photos, Permission.videos].request();
                    storageReq =
                        statuses[Permission.photos]?.isGranted ?? false;
                  } else {
                    storageReq = await Permission.storage.request().isGranted;
                  }

                  if (mounted) {
                    setState(() {
                      _isCameraPermissionGranted = cameraReq.isGranted;
                      _isStoragePermissionGranted = storageReq;
                    });
                  }

                  cameraStatus = cameraReq;
                  storageStatus = storageReq;
                }

                if (!cameraStatus.isGranted || !storageStatus) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Please grant camera and storage permissions to add photos or documents.',
                        ),
                        backgroundColor: Colors.red.shade400,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
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
