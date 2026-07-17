// import 'dart:math';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/cupertino.dart';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'dart:io';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
// import '../service/listservice.dart';
// import 'package:dotted_border/dotted_border.dart';
// import '../service/mainapi.dart';
// import 'ai_processing.dart';
// import 'send_otp.dart';
// import 'package:device_info_plus/device_info_plus.dart';
// import 'package:dio/dio.dart';
// import 'package:mime/mime.dart';
// import 'package:http_parser/http_parser.dart';
// import 'package:flutter_pdfview/flutter_pdfview.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:intl/intl.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:flutter/services.dart';
//
// class InvoiceManagementScreen extends StatefulWidget {
//   const InvoiceManagementScreen({Key? key}) : super(key: key);
//
//   @override
//   State<InvoiceManagementScreen> createState() =>
//       _InvoiceManagementScreenState();
// }
//
// class _InvoiceManagementScreenState extends State<InvoiceManagementScreen> {
//   final ImagePicker _picker = ImagePicker();
//   File? _selectedFile;
//   List<File> _selectedImages = [];
//   List<dynamic> _invoices = [];
//   Set<String> _reprocessingIds = <String>{};
//   bool _isUploading = false;
//   bool _isLoading = false;
//   bool _isLoadingMore = false;
//   bool _hasMore = true;
//   String _searchQuery = '';
//   int _offset = 0;
//   final int _limit = 10;
//   final ScrollController _scrollController = ScrollController();
//   bool _isNavigating = false;
//   final TextEditingController _searchController = TextEditingController();
//   final FocusNode _searchFocusNode = FocusNode();
//   String? _loadingPreviewId;
//   bool _isCameraPermissionGranted = false;
//   bool _isStoragePermissionGranted = false;
//   List<Map<String, dynamic>> _categories = [];
//   Map<String, dynamic>? _selectedCategory;
//
//   @override
//   void initState() {
//     super.initState();
//     _checkPermissions();
//     _fetchCategories();
//     _fetchInvoices();
//     _searchController.addListener(_onSearchChanged);
//     _scrollController.addListener(() {
//       if (_scrollController.position.pixels >=
//               _scrollController.position.maxScrollExtent - 200 &&
//           !_isLoadingMore &&
//           _hasMore) {
//         _fetchMoreInvoices();
//       }
//     });
//     _searchFocusNode.addListener(() {
//       if (_isNavigating && _searchFocusNode.hasFocus) {
//         _searchFocusNode.unfocus();
//       }
//     });
//   }
//
//   Future<void> _fetchCategories() async {
//     try {
//       final categories = await InvoiceListService().fetchCategories();
//       if (mounted) {
//         setState(() {
//           _categories = [
//             {'id': null, 'name': 'All'},
//             ...categories.map((c) => {'id': c['id'], 'name': c['name']}),
//           ];
//           _selectedCategory = _categories[0]; // Default to 'All'
//         });
//       }
//     } catch (e) {
//       print('Failed to fetch categories: $e');
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to load categories: $e'),
//             backgroundColor: Colors.red.shade400,
//             behavior: SnackBarBehavior.floating,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//           ),
//         );
//       }
//     }
//   }
//
//   Future<void> _checkPermissions() async {
//     final cameraStatus = await Permission.camera.status;
//     final storageStatus = await Permission.storage.status;
//
//     if (!cameraStatus.isGranted) {
//       await Permission.camera.request();
//     }
//     if (!storageStatus.isGranted) {
//       await Permission.storage.request();
//     }
//
//     setState(() {
//       _isCameraPermissionGranted = cameraStatus.isGranted;
//       _isStoragePermissionGranted = storageStatus.isGranted;
//     });
//   }
//
//   @override
//   void dispose() {
//     _searchController.removeListener(_onSearchChanged);
//     _searchController.dispose();
//     _scrollController.dispose();
//     _searchFocusNode.dispose();
//     super.dispose();
//   }
//
//   Future<void> _fetchInvoices({String? search, String? categoryId}) async {
//     setState(() {
//       _isLoading = true;
//       _offset = 0;
//       _invoices.clear();
//       _hasMore = true;
//     });
//     try {
//       final service = InvoiceListService();
//       final invoices = await service.fetchInvoices(
//         search: search,
//         category: categoryId,
//         limit: _limit,
//         offset: _offset,
//       );
//       print("the invoice data: $invoices");
//       setState(() {
//         _invoices = invoices;
//         _offset += _limit;
//         _hasMore = invoices.length == _limit;
//       });
//     } catch (e) {
//       print('❌ Failed to load invoices :$e');
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: const Text('❌ Failed to load invoices'),
//           backgroundColor: Colors.red.shade400,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//         ),
//       );
//     } finally {
//       if (mounted) setState(() => _isLoading = false);
//     }
//   }
//
//   Future<void> _fetchMoreInvoices() async {
//     if (!_hasMore || _isLoadingMore) return;
//     setState(() => _isLoadingMore = true);
//     try {
//       final service = InvoiceListService();
//       final invoices = await service.fetchInvoices(
//         search: _searchQuery.isNotEmpty ? _searchQuery : null,
//         category: _selectedCategory?['id']?.toString(),
//         limit: _limit,
//         offset: _offset,
//       );
//       print("Fetched more invoices: $invoices");
//       setState(() {
//         _invoices.addAll(invoices);
//         _offset += _limit;
//         _hasMore = invoices.length == _limit;
//       });
//     } catch (e) {
//       print('❌ Failed to load more invoices :$e');
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: const Text('❌ Failed to load more invoices'),
//           backgroundColor: Colors.red.shade400,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//         ),
//       );
//     } finally {
//       if (mounted) setState(() => _isLoadingMore = false);
//     }
//   }
//
//   void _onSearchChanged() {
//     final query = _searchController.text.trim();
//     _searchQuery = query;
//     _fetchInvoices(
//       search: query.isNotEmpty ? query : null,
//       categoryId: _selectedCategory?['id']?.toString(),
//     );
//   }
//
//   Future<void> _logout(BuildContext context) async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.clear();
//     if (!mounted) return;
//     Navigator.pushAndRemoveUntil(
//       context,
//       MaterialPageRoute(builder: (context) => newLoginScreen()),
//       (route) => false,
//     );
//   }
//
//   void _showLogoutConfirmation(BuildContext context) {
//     showDialog(
//       context: context,
//       builder:
//           (context) => AlertDialog(
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(20),
//             ),
//             title: const Row(
//               children: [
//                 Icon(Icons.logout_rounded, color: Color(0xFF192155)),
//                 SizedBox(width: 8),
//                 Text('Confirm Logout'),
//               ],
//             ),
//             content: const Text('Are you sure you want to logout?'),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(context),
//                 style: TextButton.styleFrom(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 24,
//                     vertical: 12,
//                   ),
//                 ),
//                 child: Text(
//                   'Cancel',
//                   style: TextStyle(color: Colors.grey.shade600),
//                 ),
//               ),
//               ElevatedButton(
//                 onPressed: () {
//                   Navigator.pop(context);
//                   _logout(context);
//                 },
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: Color(0xFF192155),
//                   foregroundColor: Colors.white,
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 24,
//                     vertical: 12,
//                   ),
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                 ),
//                 child: const Text('Logout'),
//               ),
//             ],
//           ),
//     );
//   }
//
//   void _showCategoriesFilterDialog() {
//     showDialog(
//       context: context,
//       builder:
//           (context) => AlertDialog(
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(20),
//             ),
//             title: const Row(
//               children: [
//                 Icon(Icons.category_rounded, color: Color(0xFF192155)),
//                 SizedBox(width: 8),
//                 Text('Select Category'),
//               ],
//             ),
//             content: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children:
//                     _categories.map((category) {
//                       return RadioListTile<Map<String, dynamic>>(
//                         title: Text(category['name']),
//                         value: category,
//                         groupValue: _selectedCategory,
//                         activeColor: Color(0xFF192155),
//                         onChanged: (value) {
//                           setState(() {
//                             _selectedCategory = value;
//                             _fetchInvoices(
//                               search:
//                                   _searchQuery.isNotEmpty ? _searchQuery : null,
//                               categoryId: value?['id']?.toString(),
//                             );
//                           });
//                           Navigator.pop(context);
//                         },
//                       );
//                     }).toList(),
//               ),
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(context),
//                 child: Text(
//                   'Cancel',
//                   style: TextStyle(color: Colors.grey.shade600),
//                 ),
//               ),
//             ],
//           ),
//     );
//   }
//
//   Future<Map<String, dynamic>?> _showCategoriesSelectionDialog() async {
//     return showDialog<Map<String, dynamic>>(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => AlertDialog(
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(20),
//             ),
//             title: const Row(
//               children: [
//                 Icon(Icons.category_rounded, color: Color(0xFF192155)),
//                 SizedBox(width: 8),
//                 Text('Select Invoice \n Category'),
//               ],
//             ),
//             content: SingleChildScrollView(
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children:
//                     _categories.where((category) => category['id'] != null).map(
//                       (category) {
//                         return ListTile(
//                           title: Text(category['name']),
//                           onTap: () => Navigator.pop(context, category),
//                         );
//                       },
//                     ).toList(),
//               ),
//             ),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.pop(context),
//                 child: Text(
//                   'Cancel',
//                   style: TextStyle(color: Colors.grey.shade600),
//                 ),
//               ),
//             ],
//           ),
//     );
//   }
//
//   Future<void> _uploadSelectedFiles(
//     BuildContext parentContext, {
//     File? singleFile,
//     List<File>? images,
//     required String categoryId,
//   }) async {
//     if (singleFile == null && (images == null || images.isEmpty)) return;
//     if (mounted) setState(() => _isUploading = true);
//
//     _showAIProcessingDialog(parentContext);
//
//     try {
//       final api = InvoiceApiService();
//       final formData = FormData();
//
//       final responses = await api.uploadInvoices(
//         formData,
//         singleFile: singleFile,
//         images: images,
//         categoryId: categoryId,
//       );
//
//       if (!mounted) return;
//       Navigator.pop(parentContext); // Close AI processing dialog
//
//       // Show response dialog with invoice details
//       showDialog(
//         context: parentContext,
//         builder:
//             (context) => AlertDialog(
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(20),
//               ),
//               title: const Row(
//                 children: [
//                   Icon(Icons.check_circle, color: Color(0xFF192155)),
//                   SizedBox(width: 8),
//                   Text('Please Proceed'),
//                 ],
//               ),
//               content: SingleChildScrollView(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children:
//                       responses.asMap().entries.map((entry) {
//                         final index = entry.key;
//                         final response = entry.value;
//                         return Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             if (responses.length > 1) ...[
//                               Text(
//                                 'Invoice ${index + 1}',
//                                 style: const TextStyle(
//                                   fontSize: 16,
//                                   fontWeight: FontWeight.bold,
//                                   color: Color(0xFF192155),
//                                 ),
//                               ),
//                               const SizedBox(height: 8),
//                             ],
//                             TextField(
//                               readOnly: true,
//                               decoration: InputDecoration(
//                                 labelText: 'Invoice Number',
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 contentPadding: const EdgeInsets.symmetric(
//                                   horizontal: 12,
//                                   vertical: 8,
//                                 ),
//                                 hintText:
//                                     response.invoiceNumber ?? 'Not available',
//                                 hintStyle: TextStyle(
//                                   color: Colors.grey.shade600,
//                                 ),
//                               ),
//                               controller: TextEditingController(
//                                 text:
//                                     response.invoiceNumber?.toString() ??
//                                     'Not available',
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             TextField(
//                               readOnly: true,
//                               decoration: InputDecoration(
//                                 labelText: 'Company Name',
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 contentPadding: const EdgeInsets.symmetric(
//                                   horizontal: 12,
//                                   vertical: 8,
//                                 ),
//                                 hintText:
//                                     response.vendorName ?? 'Not available',
//                                 hintStyle: TextStyle(
//                                   color: Colors.grey.shade600,
//                                 ),
//                               ),
//                               controller: TextEditingController(
//                                 text:
//                                     response.vendorName?.toString() ??
//                                     'Not available',
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             TextField(
//                               readOnly: true,
//                               decoration: InputDecoration(
//                                 labelText: 'Invoice Date',
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 contentPadding: const EdgeInsets.symmetric(
//                                   horizontal: 12,
//                                   vertical: 8,
//                                 ),
//                                 hintText: _formatDate(response.date),
//                                 hintStyle: TextStyle(
//                                   color: Colors.grey.shade600,
//                                 ),
//                               ),
//                               controller: TextEditingController(
//                                 text: _formatDate(response.date),
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             TextField(
//                               readOnly: true,
//                               decoration: InputDecoration(
//                                 labelText: 'Amount',
//                                 border: OutlineInputBorder(
//                                   borderRadius: BorderRadius.circular(8),
//                                 ),
//                                 contentPadding: const EdgeInsets.symmetric(
//                                   horizontal: 12,
//                                   vertical: 8,
//                                 ),
//                                 hintText:
//                                     response.amount?.toString() ??
//                                     'Not available',
//                                 hintStyle: TextStyle(
//                                   color: Colors.grey.shade600,
//                                 ),
//                               ),
//                               controller: TextEditingController(
//                                 text:
//                                     response.amount?.toString() ??
//                                     'Not available',
//                               ),
//                             ),
//                             const SizedBox(height: 16),
//                           ],
//                         );
//                       }).toList(),
//                 ),
//               ),
//               actions: [
//                 TextButton(
//                   onPressed: () async {
//                     try {
//                       for (var response in responses) {
//                         if (response.uploadedFileId != null) {
//                           await api.cancelUpload(response.uploadedFileId!);
//                           ScaffoldMessenger.of(parentContext).showSnackBar(
//                             SnackBar(
//                               content: Text(
//                                 'Upload cancelled for invoice ${response.invoiceNumber ?? 'unknown'}',
//                               ),
//                               backgroundColor: Colors.orange.shade400,
//                               behavior: SnackBarBehavior.floating,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                             ),
//                           );
//                         }
//                       }
//                       Navigator.pop(context);
//                       setState(() {
//                         _selectedFile = null;
//                         _selectedImages.clear();
//                       });
//                       await _fetchInvoices(
//                         search: _searchQuery.isNotEmpty ? _searchQuery : null,
//                         categoryId: _selectedCategory?['id']?.toString(),
//                       );
//                     } catch (e) {
//                       ScaffoldMessenger.of(parentContext).showSnackBar(
//                         SnackBar(
//                           content: Text('Failed to cancel upload: $e'),
//                           backgroundColor: Colors.red.shade400,
//                           behavior: SnackBarBehavior.floating,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                         ),
//                       );
//                     }
//                   },
//                   style: TextButton.styleFrom(
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 24,
//                       vertical: 12,
//                     ),
//                   ),
//                   child: Text(
//                     'Cancel',
//                     style: TextStyle(color: Colors.grey.shade600),
//                   ),
//                 ),
//                 ElevatedButton(
//                   onPressed: () async {
//                     try {
//                       for (var response in responses) {
//                         final aiData = {
//                           'company_name': response.vendorName ?? 'Unknown',
//                           'invoice_number': response.invoiceNumber ?? 'Unknown',
//                           'amount': response.amount ?? 0,
//                           'invoice_date':
//                               response.date ?? DateTime.now().toIso8601String(),
//                           'line_items':
//                               response.lineItems != null &&
//                                       response.lineItems!.isNotEmpty
//                                   ? response.lineItems!
//                                       .map(
//                                         (item) => {
//                                           'description': item.description,
//                                           'quantity': item.quantity,
//                                           'price': item.price,
//                                           'total': item.total,
//                                         },
//                                       )
//                                       .toList()
//                                   : [
//                                     {
//                                       'description': 'Default Item',
//                                       'quantity': 1,
//                                       'price': response.amount ?? 0,
//                                       'total': response.amount ?? 0,
//                                     },
//                                   ],
//                         };
//                         await api.commitInvoice(
//                           categoryId: categoryId,
//                           aiData: aiData,
//                         );
//                         ScaffoldMessenger.of(parentContext).showSnackBar(
//                           SnackBar(
//                             content: Text(
//                               'Invoice ${response.invoiceNumber ?? 'unknown'} committed successfully',
//                             ),
//                             backgroundColor: Colors.green.shade400,
//                             behavior: SnackBarBehavior.floating,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         );
//                       }
//                       Navigator.pop(context);
//                       setState(() {
//                         _selectedFile = null;
//                         _selectedImages.clear();
//                       });
//                       await _fetchInvoices(
//                         search: _searchQuery.isNotEmpty ? _searchQuery : null,
//                         categoryId: _selectedCategory?['id']?.toString(),
//                       );
//                     } catch (e) {
//                       ScaffoldMessenger.of(parentContext).showSnackBar(
//                         SnackBar(
//                           content: Text('Failed to commit invoice: $e'),
//                           backgroundColor: Colors.red.shade400,
//                           behavior: SnackBarBehavior.floating,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                         ),
//                       );
//                     }
//                   },
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Color(0xFF192155),
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 24,
//                       vertical: 12,
//                     ),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                   child: const Text('OK'),
//                 ),
//               ],
//             ),
//       );
//
//       ScaffoldMessenger.of(parentContext).showSnackBar(
//         SnackBar(
//           content: Text('Uploaded ${responses.length} invoice(s)!'),
//           backgroundColor: Colors.green.shade400,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//         ),
//       );
//     } catch (e) {
//       Navigator.pop(parentContext); // Close AI processing dialog
//       if (mounted) {
//         ScaffoldMessenger.of(parentContext).showSnackBar(
//           SnackBar(
//             content: Text('Upload failed: $e'),
//             backgroundColor: Colors.red.shade400,
//             behavior: SnackBarBehavior.floating,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//           ),
//         );
//         setState(() => _isUploading = false);
//       }
//     } finally {
//       if (mounted) {
//         setState(() => _isUploading = false);
//       }
//     }
//   }
//
//   void _showAIProcessingDialog(BuildContext context) {
//     bool isFilesUploaded = true;
//     bool isDataExtracted = false;
//     bool isValidated = false;
//     bool isPreparing = false;
//
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder:
//           (context) => StatefulBuilder(
//             builder: (context, setState) {
//               if (isFilesUploaded && !isDataExtracted) {
//                 Future.delayed(const Duration(seconds: 3), () {
//                   if (mounted) setState(() => isDataExtracted = true);
//                 });
//               }
//               if (isDataExtracted && !isValidated) {
//                 Future.delayed(const Duration(seconds: 4), () {
//                   if (mounted) setState(() => isValidated = true);
//                 });
//               }
//               if (isValidated && !isPreparing) {
//                 Future.delayed(const Duration(seconds: 4), () {
//                   if (mounted) setState(() => isPreparing = true);
//                 });
//               }
//
//               return InvoiceCard();
//             },
//           ),
//     );
//   }
//
//   void _showUploadOptions(BuildContext context) {
//     final parentContext = context;
//     showModalBottomSheet(
//       context: context,
//       backgroundColor: Colors.transparent,
//       builder: (BuildContext bottomSheetContext) {
//         return Container(
//           decoration: const BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.only(
//               topLeft: Radius.circular(24),
//               topRight: Radius.circular(24),
//             ),
//           ),
//           child: SafeArea(
//             child: Padding(
//               padding: const EdgeInsets.all(20.0),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   Container(
//                     width: 40,
//                     height: 4,
//                     decoration: BoxDecoration(
//                       color: Colors.grey.shade300,
//                       borderRadius: BorderRadius.circular(2),
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                   const Text(
//                     'Upload Invoice',
//                     style: TextStyle(
//                       fontSize: 20,
//                       fontWeight: FontWeight.bold,
//                       color: Color(0xFF192155),
//                     ),
//                   ),
//                   const SizedBox(height: 20),
//                   _buildUploadOption(
//                     icon: Icons.camera_alt_rounded,
//                     title: 'Take Photo',
//                     subtitle: 'Capture up to 3 images with camera',
//                     onTap: () async {
//                       if (!_isCameraPermissionGranted) {
//                         ScaffoldMessenger.of(parentContext).showSnackBar(
//                           SnackBar(
//                             content: const Text(
//                               'Camera permission is required.',
//                             ),
//                             backgroundColor: Colors.red.shade400,
//                             behavior: SnackBarBehavior.floating,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         );
//                         return;
//                       }
//                       Navigator.pop(bottomSheetContext);
//                       final category = await _showCategoriesSelectionDialog();
//                       if (category == null) return;
//                       try {
//                         final XFile? photo = await _picker.pickImage(
//                           source: ImageSource.camera,
//                           imageQuality: 80,
//                         );
//                         if (photo != null) {
//                           final newFile = File(photo.path);
//                           final extension =
//                               photo.path.split('.').last.toLowerCase();
//                           if (!['jpg', 'jpeg', 'png'].contains(extension)) {
//                             ScaffoldMessenger.of(parentContext).showSnackBar(
//                               SnackBar(
//                                 content: const Text(
//                                   'Only JPG or PNG images are allowed.',
//                                 ),
//                                 behavior: SnackBarBehavior.floating,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                             );
//                             return;
//                           }
//                           if (_selectedImages.length >= 3) {
//                             ScaffoldMessenger.of(parentContext).showSnackBar(
//                               SnackBar(
//                                 content: const Text(
//                                   'You can upload a maximum of 3 images.',
//                                 ),
//                                 behavior: SnackBarBehavior.floating,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                             );
//                             return;
//                           }
//                           if (_selectedFile != null) {
//                             ScaffoldMessenger.of(parentContext).showSnackBar(
//                               SnackBar(
//                                 content: const Text(
//                                   'Cannot upload image when a file is selected.',
//                                 ),
//                                 behavior: SnackBarBehavior.floating,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                             );
//                             return;
//                           }
//                           setState(() => _selectedImages = [newFile]);
//                           _showSelectedFilesModal(parentContext, category);
//                         } else {
//                           if (!mounted) return;
//                           ScaffoldMessenger.of(parentContext).showSnackBar(
//                             SnackBar(
//                               content: const Text('Photo capture cancelled'),
//                               behavior: SnackBarBehavior.floating,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                             ),
//                           );
//                         }
//                       } catch (e) {
//                         if (!mounted) return;
//                         ScaffoldMessenger.of(parentContext).showSnackBar(
//                           SnackBar(
//                             content: Text('Camera error: $e'),
//                             backgroundColor: Colors.red.shade400,
//                             behavior: SnackBarBehavior.floating,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         );
//                       }
//                     },
//                   ),
//                   const SizedBox(height: 12),
//                   _buildUploadOption(
//                     icon: Icons.upload_file_rounded,
//                     title: 'Upload from Device',
//                     subtitle: 'Select 1 PDF/DOC or up to 3 images from storage',
//                     onTap: () async {
//                       if (!_isStoragePermissionGranted) {
//                         ScaffoldMessenger.of(parentContext).showSnackBar(
//                           SnackBar(
//                             content: const Text(
//                               'Storage permission is required.',
//                             ),
//                             backgroundColor: Colors.red.shade400,
//                             behavior: SnackBarBehavior.floating,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         );
//                         return;
//                       }
//                       Navigator.pop(bottomSheetContext);
//                       final category = await _showCategoriesSelectionDialog();
//                       if (category == null) return;
//                       try {
//                         FilePickerResult? result = await FilePicker.platform
//                             .pickFiles(
//                               allowMultiple: true,
//                               type: FileType.custom,
//                               allowedExtensions: [
//                                 'jpg',
//                                 'jpeg',
//                                 'png',
//                                 'pdf',
//                                 'doc',
//                                 'docx',
//                               ],
//                             );
//
//                         if (result != null && result.files.isNotEmpty) {
//                           final files =
//                               result.files.map((f) => File(f.path!)).toList();
//                           int imageCount =
//                               files
//                                   .where(
//                                     (f) => ['jpg', 'jpeg', 'png'].contains(
//                                       f.path.split('.').last.toLowerCase(),
//                                     ),
//                                   )
//                                   .length;
//                           int docCount =
//                               files
//                                   .where(
//                                     (f) => ['pdf', 'doc', 'docx'].contains(
//                                       f.path.split('.').last.toLowerCase(),
//                                     ),
//                                   )
//                                   .length;
//
//                           if (imageCount > 0 && docCount > 0) {
//                             ScaffoldMessenger.of(parentContext).showSnackBar(
//                               SnackBar(
//                                 content: const Text(
//                                   'Cannot upload both images and documents together.',
//                                 ),
//                                 behavior: SnackBarBehavior.floating,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                             );
//                             return;
//                           }
//                           if (imageCount > 3) {
//                             ScaffoldMessenger.of(parentContext).showSnackBar(
//                               SnackBar(
//                                 content: const Text(
//                                   'You can upload a maximum of 3 images.',
//                                 ),
//                                 behavior: SnackBarBehavior.floating,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                             );
//                             return;
//                           }
//                           if (docCount > 1) {
//                             ScaffoldMessenger.of(parentContext).showSnackBar(
//                               SnackBar(
//                                 content: const Text(
//                                   'You can upload only 1 document (PDF/DOC/DOCX).',
//                                 ),
//                                 behavior: SnackBarBehavior.floating,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                             );
//                             return;
//                           }
//
//                           setState(() {
//                             if (imageCount > 0) {
//                               _selectedImages = files;
//                               _selectedFile = null;
//                             } else {
//                               _selectedFile = files.first;
//                               _selectedImages = [];
//                             }
//                           });
//                           _showSelectedFilesModal(parentContext, category);
//                         } else {
//                           if (!mounted) return;
//                           ScaffoldMessenger.of(parentContext).showSnackBar(
//                             SnackBar(
//                               content: const Text('No files selected'),
//                               behavior: SnackBarBehavior.floating,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                             ),
//                           );
//                         }
//                       } catch (e) {
//                         if (!mounted) return;
//                         ScaffoldMessenger.of(parentContext).showSnackBar(
//                           SnackBar(
//                             content: Text('File selection error: $e'),
//                             backgroundColor: Colors.red.shade400,
//                             behavior: SnackBarBehavior.floating,
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                         );
//                       }
//                     },
//                   ),
//                   const SizedBox(height: 20),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
//
//   void _showSelectedFilesModal(
//     BuildContext parentContext,
//     Map<String, dynamic> category,
//   ) {
//     File? tempSelectedFile = _selectedFile;
//     List<File> tempSelectedImages = List.from(_selectedImages);
//
//     showModalBottomSheet(
//       context: parentContext,
//       backgroundColor: Colors.transparent,
//       isScrollControlled: true,
//       builder: (BuildContext modalContext) {
//         return StatefulBuilder(
//           builder: (BuildContext context, StateSetter modalSetState) {
//             return Container(
//               decoration: const BoxDecoration(
//                 color: Colors.white,
//                 borderRadius: BorderRadius.only(
//                   topLeft: Radius.circular(24),
//                   topRight: Radius.circular(24),
//                 ),
//               ),
//               child: SafeArea(
//                 child: Padding(
//                   padding: const EdgeInsets.all(16.0),
//                   child: Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Container(
//                         padding: const EdgeInsets.all(16.0),
//                         color: Color(0xFFF5F5F5),
//                         child: Center(
//                           child: Text(
//                             'Upload Invoices (${category['name']})',
//                             style: const TextStyle(
//                               fontSize: 20,
//                               fontWeight: FontWeight.bold,
//                               color: Color(0xFF192155),
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 16),
//                       DottedBorder(
//                         options: RoundedRectDottedBorderOptions(
//                           dashPattern: [8, 4],
//                           strokeWidth: 1,
//                           radius: const Radius.circular(8.0),
//                           color: Colors.grey.shade400,
//                           padding: const EdgeInsets.all(0),
//                         ),
//                         child: Padding(
//                           padding: const EdgeInsets.all(16.0),
//                           child: Column(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               Text(
//                                 'Supports 1 PDF/DOC/DOCX or up to 3 PNG/JPG (10MB each)',
//                                 textAlign: TextAlign.center,
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: Colors.grey.shade600,
//                                 ),
//                               ),
//                               const SizedBox(height: 16),
//                               Row(
//                                 mainAxisAlignment: MainAxisAlignment.center,
//                                 children: [
//                                   ElevatedButton(
//                                     onPressed: () async {
//                                       try {
//                                         FilePickerResult? result =
//                                             await FilePicker.platform.pickFiles(
//                                               allowMultiple:
//                                                   tempSelectedFile == null,
//                                               type: FileType.custom,
//                                               allowedExtensions:
//                                                   tempSelectedFile == null
//                                                       ? ['jpg', 'jpeg', 'png']
//                                                       : ['pdf', 'doc', 'docx'],
//                                             );
//                                         if (result != null &&
//                                             result.files.isNotEmpty) {
//                                           final newFiles =
//                                               result.files
//                                                   .map((f) => File(f.path!))
//                                                   .toList();
//                                           int currentImageCount =
//                                               tempSelectedImages.length;
//                                           int newImageCount =
//                                               newFiles
//                                                   .where(
//                                                     (f) => [
//                                                       'jpg',
//                                                       'jpeg',
//                                                       'png',
//                                                     ].contains(
//                                                       f.path
//                                                           .split('.')
//                                                           .last
//                                                           .toLowerCase(),
//                                                     ),
//                                                   )
//                                                   .length;
//                                           int newDocCount =
//                                               newFiles
//                                                   .where(
//                                                     (f) => [
//                                                       'pdf',
//                                                       'doc',
//                                                       'docx',
//                                                     ].contains(
//                                                       f.path
//                                                           .split('.')
//                                                           .last
//                                                           .toLowerCase(),
//                                                     ),
//                                                   )
//                                                   .length;
//
//                                           if (tempSelectedFile != null &&
//                                               newDocCount > 0) {
//                                             ScaffoldMessenger.of(
//                                               parentContext,
//                                             ).showSnackBar(
//                                               SnackBar(
//                                                 content: const Text(
//                                                   'Only one document can be uploaded.',
//                                                 ),
//                                                 behavior:
//                                                     SnackBarBehavior.floating,
//                                                 shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(12),
//                                                 ),
//                                               ),
//                                             );
//                                             return;
//                                           }
//                                           if (tempSelectedImages.isNotEmpty &&
//                                               newDocCount > 0) {
//                                             ScaffoldMessenger.of(
//                                               parentContext,
//                                             ).showSnackBar(
//                                               SnackBar(
//                                                 content: const Text(
//                                                   'Cannot upload documents when images are selected.',
//                                                 ),
//                                                 behavior:
//                                                     SnackBarBehavior.floating,
//                                                 shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(12),
//                                                 ),
//                                               ),
//                                             );
//                                             return;
//                                           }
//                                           if (currentImageCount +
//                                                   newImageCount >
//                                               3) {
//                                             ScaffoldMessenger.of(
//                                               parentContext,
//                                             ).showSnackBar(
//                                               SnackBar(
//                                                 content: const Text(
//                                                   'You can upload a maximum of 3 images.',
//                                                 ),
//                                                 behavior:
//                                                     SnackBarBehavior.floating,
//                                                 shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(12),
//                                                 ),
//                                               ),
//                                             );
//                                             return;
//                                           }
//
//                                           modalSetState(() {
//                                             if (newDocCount > 0) {
//                                               tempSelectedFile = newFiles.first;
//                                               tempSelectedImages.clear();
//                                             } else {
//                                               tempSelectedImages.addAll(
//                                                 newFiles,
//                                               );
//                                               tempSelectedFile = null;
//                                             }
//                                           });
//                                         } else {
//                                           ScaffoldMessenger.of(
//                                             parentContext,
//                                           ).showSnackBar(
//                                             SnackBar(
//                                               content: const Text(
//                                                 'No files selected',
//                                               ),
//                                               behavior:
//                                                   SnackBarBehavior.floating,
//                                               shape: RoundedRectangleBorder(
//                                                 borderRadius:
//                                                     BorderRadius.circular(12),
//                                               ),
//                                             ),
//                                           );
//                                         }
//                                       } catch (e) {
//                                         ScaffoldMessenger.of(
//                                           parentContext,
//                                         ).showSnackBar(
//                                           SnackBar(
//                                             content: Text(
//                                               'File selection error: $e',
//                                             ),
//                                             backgroundColor:
//                                                 Colors.red.shade400,
//                                             behavior: SnackBarBehavior.floating,
//                                             shape: RoundedRectangleBorder(
//                                               borderRadius:
//                                                   BorderRadius.circular(12),
//                                             ),
//                                           ),
//                                         );
//                                       }
//                                     },
//                                     style: ElevatedButton.styleFrom(
//                                       backgroundColor: Color(0xFF192155),
//                                       foregroundColor: Colors.white,
//                                       shape: RoundedRectangleBorder(
//                                         borderRadius: BorderRadius.circular(
//                                           8.0,
//                                         ),
//                                       ),
//                                     ),
//                                     child: Text(
//                                       tempSelectedFile == null
//                                           ? 'Upload Images'
//                                           : 'Upload Document',
//                                     ),
//                                   ),
//                                   if (tempSelectedFile == null) ...[
//                                     const SizedBox(width: 16),
//                                     ElevatedButton(
//                                       onPressed: () async {
//                                         try {
//                                           final ImagePicker picker =
//                                               ImagePicker();
//                                           final XFile? photo = await picker
//                                               .pickImage(
//                                                 source: ImageSource.camera,
//                                               );
//                                           if (photo != null) {
//                                             final File newFile = File(
//                                               photo.path,
//                                             );
//                                             final extension =
//                                                 photo.path
//                                                     .split('.')
//                                                     .last
//                                                     .toLowerCase();
//                                             if (![
//                                               'jpg',
//                                               'jpeg',
//                                               'png',
//                                             ].contains(extension)) {
//                                               ScaffoldMessenger.of(
//                                                 parentContext,
//                                               ).showSnackBar(
//                                                 SnackBar(
//                                                   content: const Text(
//                                                     'Only JPG or PNG images are allowed.',
//                                                   ),
//                                                   behavior:
//                                                       SnackBarBehavior.floating,
//                                                   shape: RoundedRectangleBorder(
//                                                     borderRadius:
//                                                         BorderRadius.circular(
//                                                           12,
//                                                         ),
//                                                   ),
//                                                 ),
//                                               );
//                                               return;
//                                             }
//                                             if (tempSelectedImages.length >=
//                                                 3) {
//                                               ScaffoldMessenger.of(
//                                                 parentContext,
//                                               ).showSnackBar(
//                                                 SnackBar(
//                                                   content: const Text(
//                                                     'You can upload a maximum of 3 images.',
//                                                   ),
//                                                   behavior:
//                                                       SnackBarBehavior.floating,
//                                                   shape: RoundedRectangleBorder(
//                                                     borderRadius:
//                                                         BorderRadius.circular(
//                                                           12,
//                                                         ),
//                                                   ),
//                                                 ),
//                                               );
//                                               return;
//                                             }
//                                             if (tempSelectedFile != null) {
//                                               ScaffoldMessenger.of(
//                                                 parentContext,
//                                               ).showSnackBar(
//                                                 SnackBar(
//                                                   content: const Text(
//                                                     'Cannot upload image when a document is selected.',
//                                                   ),
//                                                   behavior:
//                                                       SnackBarBehavior.floating,
//                                                   shape: RoundedRectangleBorder(
//                                                     borderRadius:
//                                                         BorderRadius.circular(
//                                                           12,
//                                                         ),
//                                                   ),
//                                                 ),
//                                               );
//                                               return;
//                                             }
//
//                                             final fileSize =
//                                                 await newFile.length();
//                                             if (fileSize > 10 * 1024 * 1024) {
//                                               ScaffoldMessenger.of(
//                                                 parentContext,
//                                               ).showSnackBar(
//                                                 SnackBar(
//                                                   content: const Text(
//                                                     'Image size exceeds 10MB limit.',
//                                                   ),
//                                                   behavior:
//                                                       SnackBarBehavior.floating,
//                                                   shape: RoundedRectangleBorder(
//                                                     borderRadius:
//                                                         BorderRadius.circular(
//                                                           12,
//                                                         ),
//                                                   ),
//                                                 ),
//                                               );
//                                               return;
//                                             }
//
//                                             modalSetState(() {
//                                               tempSelectedImages.add(newFile);
//                                             });
//                                           } else {
//                                             ScaffoldMessenger.of(
//                                               parentContext,
//                                             ).showSnackBar(
//                                               SnackBar(
//                                                 content: const Text(
//                                                   'No photo captured',
//                                                 ),
//                                                 behavior:
//                                                     SnackBarBehavior.floating,
//                                                 shape: RoundedRectangleBorder(
//                                                   borderRadius:
//                                                       BorderRadius.circular(12),
//                                                 ),
//                                               ),
//                                             );
//                                           }
//                                         } catch (e) {
//                                           ScaffoldMessenger.of(
//                                             parentContext,
//                                           ).showSnackBar(
//                                             SnackBar(
//                                               content: Text('Camera error: $e'),
//                                               backgroundColor:
//                                                   Colors.red.shade400,
//                                               behavior:
//                                                   SnackBarBehavior.floating,
//                                               shape: RoundedRectangleBorder(
//                                                 borderRadius:
//                                                     BorderRadius.circular(12),
//                                               ),
//                                             ),
//                                           );
//                                         }
//                                       },
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor: Color(0xFF192155),
//                                         foregroundColor: Colors.white,
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius: BorderRadius.circular(
//                                             8.0,
//                                           ),
//                                         ),
//                                       ),
//                                       child: const Text('Take Photo'),
//                                     ),
//                                   ],
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                       const SizedBox(height: 16),
//                       Text(
//                         'Selected Files (${(tempSelectedFile != null ? 1 : 0) + tempSelectedImages.length}/${tempSelectedFile != null ? 1 : 3})',
//                         style: const TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           color: Color(0xFF192155),
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       (tempSelectedFile == null && tempSelectedImages.isEmpty)
//                           ? const Padding(
//                             padding: EdgeInsets.all(16.0),
//                             child: Text(
//                               'No files selected',
//                               style: TextStyle(
//                                 fontSize: 14,
//                                 color: Colors.grey,
//                               ),
//                             ),
//                           )
//                           : Flexible(
//                             child: ListView.builder(
//                               shrinkWrap: true,
//                               itemCount:
//                                   (tempSelectedFile != null ? 1 : 0) +
//                                   tempSelectedImages.length,
//                               itemBuilder: (context, index) {
//                                 File file;
//                                 bool isImage;
//                                 bool isPdf;
//                                 if (tempSelectedFile != null && index == 0) {
//                                   file = tempSelectedFile!;
//                                   isImage = ['jpg', 'jpeg', 'png'].contains(
//                                     file.path.split('.').last.toLowerCase(),
//                                   );
//                                   isPdf =
//                                       file.path.split('.').last.toLowerCase() ==
//                                       'pdf';
//                                 } else {
//                                   file =
//                                       tempSelectedImages[index -
//                                           (tempSelectedFile != null ? 1 : 0)];
//                                   isImage = ['jpg', 'jpeg', 'png'].contains(
//                                     file.path.split('.').last.toLowerCase(),
//                                   );
//                                   isPdf =
//                                       file.path.split('.').last.toLowerCase() ==
//                                       'pdf';
//                                 }
//                                 final fileNameParts = file.path
//                                     .split('/')
//                                     .last
//                                     .split(' ');
//                                 final trimmedFileName =
//                                     fileNameParts.length > 2
//                                         ? '${fileNameParts.take(2).join(' ')}...'
//                                         : fileNameParts.join(' ');
//                                 final fileSize =
//                                     (file.lengthSync() / (1024 * 1024))
//                                         .toStringAsFixed(1) +
//                                     'MB';
//
//                                 return Container(
//                                   margin: const EdgeInsets.only(bottom: 8.0),
//                                   padding: const EdgeInsets.all(8.0),
//                                   color: Color(0xFFF5F5F5),
//                                   child: Column(
//                                     crossAxisAlignment:
//                                         CrossAxisAlignment.start,
//                                     children: [
//                                       Row(
//                                         children: [
//                                           if (isPdf)
//                                             const Icon(
//                                               Icons.picture_as_pdf,
//                                               color: Color(0xFF192155),
//                                             ),
//                                           if (isImage)
//                                             const Icon(
//                                               Icons.image,
//                                               color: Color(0xFF192155),
//                                             ),
//                                           if (!(isPdf || isImage))
//                                             const Icon(
//                                               Icons.insert_drive_file,
//                                               color: Color(0xFF192155),
//                                             ),
//                                           const SizedBox(width: 8),
//                                           Expanded(
//                                             child: Text(
//                                               trimmedFileName,
//                                               style: const TextStyle(
//                                                 fontSize: 14,
//                                               ),
//                                               overflow: TextOverflow.ellipsis,
//                                             ),
//                                           ),
//                                           if (isImage || isPdf)
//                                             IconButton(
//                                               icon: const Icon(
//                                                 Icons.remove_red_eye,
//                                                 color: Colors.blue,
//                                               ),
//                                               onPressed: () {
//                                                 if (isImage) {
//                                                   Navigator.push(
//                                                     context,
//                                                     MaterialPageRoute(
//                                                       builder:
//                                                           (_) => Scaffold(
//                                                             appBar: AppBar(
//                                                               title: const Text(
//                                                                 'File Preview',
//                                                               ),
//                                                               backgroundColor:
//                                                                   Color(
//                                                                     0xFF192155,
//                                                                   ),
//                                                               foregroundColor:
//                                                                   Colors.white,
//                                                             ),
//                                                             body: Image.file(
//                                                               file,
//                                                               fit:
//                                                                   BoxFit
//                                                                       .contain,
//                                                             ),
//                                                           ),
//                                                     ),
//                                                   );
//                                                 } else if (isPdf) {
//                                                   Navigator.push(
//                                                     context,
//                                                     MaterialPageRoute(
//                                                       builder:
//                                                           (_) => Scaffold(
//                                                             appBar: AppBar(
//                                                               title: const Text(
//                                                                 'File Preview',
//                                                               ),
//                                                               backgroundColor:
//                                                                   Color(
//                                                                     0xFF192155,
//                                                                   ),
//                                                               foregroundColor:
//                                                                   Colors.white,
//                                                             ),
//                                                             body: PDFView(
//                                                               filePath:
//                                                                   file.path,
//                                                               onError:
//                                                                   (
//                                                                     error,
//                                                                   ) => const Center(
//                                                                     child: Text(
//                                                                       '❌ Unable to load PDF',
//                                                                       style: TextStyle(
//                                                                         fontSize:
//                                                                             16,
//                                                                       ),
//                                                                     ),
//                                                                   ),
//                                                               onPageError:
//                                                                   (
//                                                                     page,
//                                                                     error,
//                                                                   ) => const Center(
//                                                                     child: Text(
//                                                                       '❌ Unable to load PDF page',
//                                                                       style: TextStyle(
//                                                                         fontSize:
//                                                                             16,
//                                                                       ),
//                                                                     ),
//                                                                   ),
//                                                             ),
//                                                           ),
//                                                     ),
//                                                   );
//                                                 }
//                                               },
//                                             ),
//                                           IconButton(
//                                             icon: const Icon(
//                                               Icons.close,
//                                               color: Colors.red,
//                                             ),
//                                             onPressed: () {
//                                               modalSetState(() {
//                                                 if (tempSelectedFile != null &&
//                                                     index == 0) {
//                                                   tempSelectedFile = null;
//                                                 } else {
//                                                   tempSelectedImages.removeAt(
//                                                     index -
//                                                         (tempSelectedFile !=
//                                                                 null
//                                                             ? 1
//                                                             : 0),
//                                                   );
//                                                 }
//                                               });
//                                             },
//                                           ),
//                                         ],
//                                       ),
//                                       Padding(
//                                         padding: const EdgeInsets.only(
//                                           left: 32.0,
//                                         ),
//                                         child: Text(
//                                           '($fileSize)',
//                                           style: const TextStyle(fontSize: 14),
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 );
//                               },
//                             ),
//                           ),
//                       const SizedBox(height: 16),
//                       if (tempSelectedFile != null ||
//                           tempSelectedImages.isNotEmpty)
//                         ElevatedButton(
//                           onPressed:
//                               _isUploading
//                                   ? null
//                                   : () async {
//                                     Navigator.pop(modalContext);
//                                     await _uploadSelectedFiles(
//                                       parentContext,
//                                       singleFile: tempSelectedFile,
//                                       images: tempSelectedImages,
//                                       categoryId:
//                                           category['id']?.toString() ?? '',
//                                     );
//                                   },
//                           style: ElevatedButton.styleFrom(
//                             backgroundColor: Color(0xFF192155),
//                             foregroundColor: Colors.white,
//                             padding: const EdgeInsets.symmetric(
//                               horizontal: 24,
//                               vertical: 12,
//                             ),
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                           child:
//                               _isUploading
//                                   ? const SizedBox(
//                                     height: 20,
//                                     width: 20,
//                                     child: CircularProgressIndicator(
//                                       color: Colors.white,
//                                       strokeWidth: 2,
//                                     ),
//                                   )
//                                   : Row(
//                                     mainAxisSize: MainAxisSize.min,
//                                     children: const [
//                                       Icon(Icons.send_outlined, size: 18),
//                                       SizedBox(width: 8),
//                                       Text('Submit for Processing'),
//                                     ],
//                                   ),
//                         ),
//                       const SizedBox(height: 16),
//                     ],
//                   ),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     ).whenComplete(() {
//       setState(() {
//         _selectedFile = null;
//         _selectedImages.clear();
//       });
//     });
//   }
//
//   Widget _buildUploadOption({
//     required IconData icon,
//     required String title,
//     required String subtitle,
//     required VoidCallback onTap,
//   }) {
//     return Container(
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.shade200),
//       ),
//       child: ListTile(
//         contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
//         leading: Container(
//           padding: const EdgeInsets.all(12),
//           decoration: BoxDecoration(
//             color: Colors.blue.shade50,
//             borderRadius: BorderRadius.circular(12),
//           ),
//           child: Icon(icon, color: Color(0xFF192155), size: 24),
//         ),
//         title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
//         subtitle: Text(
//           subtitle,
//           style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
//         ),
//         trailing: Icon(
//           Icons.arrow_forward_ios,
//           size: 16,
//           color: Colors.grey.shade400,
//         ),
//         onTap: onTap,
//       ),
//     );
//   }
//
//   Future<void> _openInvoicePreview(String publicUrl) async {
//     final fullUrl = 'https://invoice-api.mindrops.com$publicUrl';
//     final extension = publicUrl.split('.').last.toLowerCase();
//
//     setState(() => _isNavigating = true);
//     try {
//       if (extension == 'pdf') {
//         try {
//           final dio = Dio();
//           final tempDir = await getTemporaryDirectory();
//           final fileName = publicUrl.split('/').last;
//           final tempFile = File('${tempDir.path}/$fileName');
//
//           await dio.download(fullUrl, tempFile.path);
//
//           if (!mounted) return;
//
//           await Navigator.push(
//             context,
//             MaterialPageRoute(
//               builder:
//                   (_) => Scaffold(
//                     appBar: AppBar(
//                       title: const Text('Invoice Preview'),
//                       backgroundColor: const Color(0xFF192155),
//                       foregroundColor: Colors.white,
//                       elevation: 0,
//                       shape: const RoundedRectangleBorder(
//                         borderRadius: BorderRadius.only(
//                           bottomLeft: Radius.circular(16),
//                           bottomRight: Radius.circular(16),
//                         ),
//                       ),
//                       actions: [
//                         IconButton(
//                           icon: const Icon(Icons.download_rounded),
//                           onPressed: () async {
//                             await _downloadInvoice(fullUrl, fileName);
//                           },
//                         ),
//                       ],
//                     ),
//                     body: Container(
//                       margin: const EdgeInsets.all(16),
//                       decoration: BoxDecoration(
//                         borderRadius: BorderRadius.circular(16),
//                         boxShadow: [
//                           BoxShadow(
//                             color: Colors.black.withOpacity(0.1),
//                             blurRadius: 10,
//                             offset: const Offset(0, 5),
//                           ),
//                         ],
//                       ),
//                       child: ClipRRect(
//                         borderRadius: BorderRadius.circular(16),
//                         child: SfPdfViewer.file(
//                           tempFile,
//                           canShowScrollStatus: true,
//                           canShowPaginationDialog: true,
//                           enableDoubleTapZooming: true,
//                           onDocumentLoadFailed:
//                               (details) => ScaffoldMessenger.of(
//                                 context,
//                               ).showSnackBar(
//                                 SnackBar(
//                                   content: Text(
//                                     'Failed to load PDF: ${details.description}',
//                                   ),
//                                   backgroundColor: Colors.red.shade400,
//                                   behavior: SnackBarBehavior.floating,
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(12),
//                                   ),
//                                 ),
//                               ),
//                         ),
//                       ),
//                     ),
//                   ),
//             ),
//           );
//         } catch (e) {
//           if (!mounted) return;
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text('Failed to load PDF: $e'),
//               backgroundColor: Colors.red.shade400,
//               behavior: SnackBarBehavior.floating,
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(12),
//               ),
//             ),
//           );
//         }
//       } else {
//         await Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder:
//                 (_) => Scaffold(
//                   appBar: AppBar(
//                     title: const Text('Invoice Preview'),
//                     backgroundColor: const Color(0xFF192155),
//                     foregroundColor: Colors.white,
//                     elevation: 0,
//                     shape: const RoundedRectangleBorder(
//                       borderRadius: BorderRadius.only(
//                         bottomLeft: Radius.circular(16),
//                         bottomRight: Radius.circular(16),
//                       ),
//                     ),
//                     actions: [
//                       IconButton(
//                         icon: const Icon(Icons.download_rounded),
//                         onPressed: () async {
//                           await _downloadInvoice(
//                             fullUrl,
//                             publicUrl.split('/').last,
//                           );
//                         },
//                       ),
//                     ],
//                   ),
//                   body: Container(
//                     margin: const EdgeInsets.all(16),
//                     width: double.infinity,
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(16),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black.withOpacity(0.1),
//                           blurRadius: 10,
//                           offset: const Offset(0, 5),
//                         ),
//                       ],
//                     ),
//                     child: ClipRRect(
//                       borderRadius: BorderRadius.circular(16),
//                       child: InteractiveViewer(
//                         child: Image.network(
//                           fullUrl,
//                           fit: BoxFit.cover,
//                           loadingBuilder: (context, child, loading) {
//                             if (loading == null) return child;
//                             return const Center(
//                               child: CircularProgressIndicator(),
//                             );
//                           },
//                           errorBuilder:
//                               (context, error, stackTrace) => const Center(
//                                 child: Text(
//                                   'Unable to load image',
//                                   style: TextStyle(fontSize: 16),
//                                 ),
//                               ),
//                         ),
//                       ),
//                     ),
//                   ),
//                 ),
//           ),
//         );
//       }
//     } finally {
//       if (mounted) {
//         setState(() => _isNavigating = false);
//       }
//     }
//   }
//
//   Future<void> _downloadInvoice(String url, String fileName) async {
//     if (Platform.isAndroid) {
//       bool permissionGranted = false;
//       int? androidVersion;
//
//       try {
//         final deviceInfo = DeviceInfoPlugin();
//         final androidInfo = await deviceInfo.androidInfo;
//         androidVersion = androidInfo.version.sdkInt;
//         print('Android SDK version: $androidVersion');
//       } catch (e) {
//         print('Failed to get Android version: $e');
//         if (!mounted) return;
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to detect Android version: $e'),
//             backgroundColor: Colors.red.shade400,
//             behavior: SnackBarBehavior.floating,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//             duration: Duration(seconds: 5),
//           ),
//         );
//         return;
//       }
//
//       try {
//         if (androidVersion != null && androidVersion >= 30) {
//           var status = await Permission.manageExternalStorage.status;
//           print('MANAGE_EXTERNAL_STORAGE status: $status');
//           if (status.isDenied || status.isRestricted) {
//             status = await Permission.manageExternalStorage.request();
//             print('Requested MANAGE_EXTERNAL_STORAGE, new status: $status');
//           }
//           if (status.isGranted) {
//             permissionGranted = true;
//           } else if (status.isPermanentlyDenied || status.isRestricted) {
//             if (!mounted) return;
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: const Text(
//                   'Storage permission is restricted or permanently denied. Please enable "Allow all file access" in app settings.',
//                 ),
//                 backgroundColor: Colors.red.shade400,
//                 behavior: SnackBarBehavior.floating,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 action: SnackBarAction(
//                   label: 'Settings',
//                   textColor: Colors.white,
//                   onPressed: () async {
//                     await openAppSettings();
//                   },
//                 ),
//               ),
//             );
//             return;
//           } else if (status.isDenied) {
//             if (!mounted) return;
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: const Text(
//                   'Storage permission denied. Please grant permission to download files.',
//                 ),
//                 backgroundColor: Colors.red.shade400,
//                 behavior: SnackBarBehavior.floating,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 action: SnackBarAction(
//                   label: 'Retry',
//                   textColor: Colors.white,
//                   onPressed: () {
//                     _downloadInvoice(url, fileName);
//                   },
//                 ),
//               ),
//             );
//             return;
//           }
//         } else {
//           var status = await Permission.storage.status;
//           print('STORAGE status: $status');
//           if (!status.isGranted) {
//             status = await Permission.storage.request();
//             print('Requested STORAGE, new status: $status');
//           }
//           if (status.isGranted) {
//             permissionGranted = true;
//           } else if (status.isPermanentlyDenied) {
//             if (!mounted) return;
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: const Text(
//                   'Storage permission is permanently denied. Please enable it in app settings.',
//                 ),
//                 backgroundColor: Colors.red.shade400,
//                 behavior: SnackBarBehavior.floating,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 action: SnackBarAction(
//                   label: 'Settings',
//                   textColor: Colors.white,
//                   onPressed: () async {
//                     await openAppSettings();
//                   },
//                 ),
//               ),
//             );
//             return;
//           } else if (status.isDenied) {
//             if (!mounted) return;
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(
//                 content: const Text(
//                   'Storage permission denied. Please grant permission to download files.',
//                 ),
//                 backgroundColor: Colors.red.shade400,
//                 behavior: SnackBarBehavior.floating,
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 action: SnackBarAction(
//                   label: 'Retry',
//                   textColor: Colors.white,
//                   onPressed: () {
//                     _downloadInvoice(url, fileName);
//                   },
//                 ),
//               ),
//             );
//             return;
//           }
//         }
//       } catch (e) {
//         if (!mounted) return;
//         print('Permission request error: $e');
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('Failed to request storage permission: $e'),
//             backgroundColor: Colors.red.shade400,
//             behavior: SnackBarBehavior.floating,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(12),
//             ),
//             duration: Duration(seconds: 5),
//           ),
//         );
//         return;
//       }
//
//       if (!permissionGranted) {
//         return;
//       }
//     }
//
//     bool _loading = false;
//     setState(() {
//       _loading = true;
//     });
//
//     try {
//       final dio = Dio();
//       String filePath;
//       if (Platform.isAndroid) {
//         filePath = '/storage/emulated/0/Download/$fileName';
//       } else if (Platform.isIOS) {
//         final downloadsDir = await getApplicationDocumentsDirectory();
//         filePath = '${downloadsDir.path}/$fileName';
//       } else {
//         throw Exception('Unsupported platform');
//       }
//
//       await dio.download(url, filePath);
//
//       if (!mounted) return;
//
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Invoice saved to Downloads folder.'),
//           backgroundColor: Colors.green.shade400,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//           duration: Duration(seconds: 4),
//         ),
//       );
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to download invoice: $e'),
//           backgroundColor: Colors.red.shade400,
//           behavior: SnackBarBehavior.floating,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//           duration: Duration(seconds: 3),
//         ),
//       );
//     } finally {
//       if (mounted) {
//         setState(() {
//           _loading = false;
//         });
//       }
//     }
//   }
//
//   Widget _getStatusChip(String? status) {
//     final statusText = (status ?? 'actuator').replaceAll('_', ' ');
//     Color borderColor;
//     Color textColor;
//
//     switch (statusText.toUpperCase()) {
//       case 'AI PROCESSED':
//         borderColor = Colors.green.shade100;
//         textColor = Colors.green.shade700;
//         break;
//       case 'AI FAILED':
//         borderColor = Colors.red.shade100;
//         textColor = Colors.red.shade700;
//         break;
//       case 'AI PROCESSING':
//         borderColor = Colors.orange.shade100;
//         textColor = Colors.orange.shade700;
//         break;
//       default:
//         borderColor = Colors.blue.shade100;
//         textColor = Colors.blue.shade700;
//     }
//
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//       decoration: BoxDecoration(
//         border: Border.all(color: borderColor),
//         borderRadius: BorderRadius.circular(12),
//       ),
//       child: Text(
//         statusText,
//         style: TextStyle(
//           color: textColor,
//           fontSize: 11,
//           fontWeight: FontWeight.w600,
//         ),
//       ),
//     );
//   }
//
//   String _formatDate(String? date) {
//     if (date == null) return 'No date Found';
//     try {
//       final DateTime parsedDate = DateTime.parse(date);
//       return DateFormat('dd/MM/yyyy').format(parsedDate);
//     } catch (e) {
//       return 'No date Found';
//     }
//   }
//
//   Color _getColorForCategory(String? categoryName) {
//     final String name = categoryName ?? 'Uncategorized';
//     final int hash = name.codeUnits.fold(0, (sum, code) => sum + code);
//     final Random random = Random(hash);
//     return Color((random.nextDouble() * 0xFFFFFF).toInt()).withOpacity(0.3);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.grey.shade100,
//       appBar: AppBar(
//         title: const Text(
//           'Invoice Management',
//           style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
//         ),
//         backgroundColor: Color(0xFF192155),
//         foregroundColor: Colors.white,
//         elevation: 0,
//         actions: [
//           Container(
//             margin: const EdgeInsets.only(right: 12),
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.2),
//               borderRadius: BorderRadius.circular(8),
//             ),
//             child: IconButton(
//               icon: const Icon(Icons.logout_rounded, size: 20),
//               tooltip: 'Logout',
//               onPressed: () => _showLogoutConfirmation(context),
//             ),
//           ),
//         ],
//         shape: const RoundedRectangleBorder(
//           borderRadius: BorderRadius.only(
//             bottomLeft: Radius.circular(16),
//             bottomRight: Radius.circular(16),
//           ),
//         ),
//       ),
//       body: Stack(
//         children: [
//           Column(
//             children: [
//               Container(
//                 padding: const EdgeInsets.fromLTRB(16, 16, 10, 2),
//                 child: Row(
//                   children: [
//                     Expanded(
//                       child: Container(
//                         decoration: BoxDecoration(
//                           color: Colors.white,
//                           borderRadius: BorderRadius.circular(8),
//                           border: Border.all(color: Colors.grey.shade200),
//                         ),
//                         child: TextField(
//                           controller: _searchController,
//                           focusNode: _searchFocusNode,
//                           decoration: InputDecoration(
//                             hintText: 'Search invoices...',
//                             prefixIcon: Icon(
//                               Icons.search_rounded,
//                               color: Colors.grey.shade400,
//                               size: 20,
//                             ),
//                             suffixIcon:
//                                 _searchController.text.isNotEmpty
//                                     ? IconButton(
//                                       icon: Icon(
//                                         Icons.clear,
//                                         color: Colors.grey.shade400,
//                                       ),
//                                       onPressed: () {
//                                         _searchController.clear();
//                                         FocusScope.of(context).unfocus();
//                                       },
//                                     )
//                                     : null,
//                             border: InputBorder.none,
//                             contentPadding: const EdgeInsets.symmetric(
//                               horizontal: 16,
//                               vertical: 12,
//                             ),
//                           ),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Container(
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(8),
//                         border: Border.all(color: Colors.grey.shade200),
//                       ),
//                       child: IconButton(
//                         icon: Icon(
//                           Icons.filter_list_rounded,
//                           color:
//                               _selectedCategory?['id'] == null
//                                   ? Colors.grey.shade400
//                                   : Color(0xFF192155),
//                         ),
//                         tooltip: 'Filter by Category',
//                         onPressed: _showCategoriesFilterDialog,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Expanded(
//                 child:
//                     _isLoading
//                         ? const Center(
//                           child: CircularProgressIndicator(
//                             valueColor: AlwaysStoppedAnimation<Color>(
//                               Color(0xFF1E88E5),
//                             ),
//                           ),
//                         )
//                         : _invoices.isEmpty
//                         ? Center(
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(
//                                 Icons.receipt_long_outlined,
//                                 size: 64,
//                                 color: Colors.grey.shade300,
//                               ),
//                               const SizedBox(height: 12),
//                               Text(
//                                 'No invoices found',
//                                 style: TextStyle(
//                                   fontSize: 16,
//                                   color: Colors.grey.shade500,
//                                   fontWeight: FontWeight.w500,
//                                 ),
//                               ),
//                               const SizedBox(height: 6),
//                               Text(
//                                 'Upload your first invoice to get started',
//                                 style: TextStyle(
//                                   fontSize: 13,
//                                   color: Colors.grey.shade400,
//                                 ),
//                               ),
//                             ],
//                           ),
//                         )
//                         : ListView.builder(
//                           controller: _scrollController,
//                           padding: const EdgeInsets.all(16),
//                           itemCount:
//                               _invoices.length + (_isLoadingMore ? 1 : 0),
//                           itemBuilder: (context, index) {
//                             if (index == _invoices.length && _isLoadingMore) {
//                               return const Center(
//                                 child: Padding(
//                                   padding: EdgeInsets.all(16.0),
//                                   child: CircularProgressIndicator(
//                                     valueColor: AlwaysStoppedAnimation<Color>(
//                                       Color(0xFF1E88E5),
//                                     ),
//                                   ),
//                                 ),
//                               );
//                             }
//
//                             final invoice = _invoices[index];
//                             final uploadedFile = invoice['uploaded_file'];
//                             final publicUrl = uploadedFile?['public_url'];
//
//                             return InkWell(
//                               onTap: () async {
//                                 if (_loadingPreviewId != null) return;
//                                 if (publicUrl == null) {
//                                   ScaffoldMessenger.of(context).showSnackBar(
//                                     const SnackBar(
//                                       content: Text('No preview available'),
//                                     ),
//                                   );
//                                   return;
//                                 }
//                                 setState(
//                                   () => _loadingPreviewId = invoice['id'],
//                                 );
//                                 try {
//                                   await _openInvoicePreview(publicUrl);
//                                 } finally {
//                                   if (mounted)
//                                     setState(() => _loadingPreviewId = null);
//                                 }
//                               },
//                               borderRadius: BorderRadius.circular(12),
//                               splashColor: Color(0xFF192155).withOpacity(0.2),
//                               hoverColor: Colors.grey.shade200,
//                               highlightColor: Colors.grey.shade100.withOpacity(
//                                 0.7,
//                               ),
//                               child: Container(
//                                 margin: const EdgeInsets.only(bottom: 12),
//                                 decoration: BoxDecoration(
//                                   color: Colors.white,
//                                   border: Border.all(
//                                     color: Colors.grey.shade200,
//                                   ),
//                                   borderRadius: BorderRadius.circular(12),
//                                   boxShadow: [
//                                     BoxShadow(
//                                       color: Colors.black.withOpacity(0.05),
//                                       blurRadius: 6,
//                                       offset: const Offset(0, 2),
//                                     ),
//                                   ],
//                                 ),
//                                 child: Padding(
//                                   padding: const EdgeInsets.all(8),
//                                   child: Column(
//                                     crossAxisAlignment:
//                                         CrossAxisAlignment.start,
//                                     children: [
//                                       Container(
//                                         decoration: BoxDecoration(
//                                           color: _getColorForCategory(
//                                             invoice['category']?['name'],
//                                           ),
//                                           borderRadius: BorderRadius.circular(
//                                             12,
//                                           ),
//                                         ),
//                                         padding: EdgeInsets.symmetric(
//                                           horizontal: 10,
//                                           vertical: 4,
//                                         ),
//                                         child: Text(
//                                           invoice['category']?['name'] ??
//                                               'Uncategorized',
//                                           style: TextStyle(
//                                             fontSize: 10,
//                                             color: Colors.grey.shade600,
//                                           ),
//                                         ),
//                                       ),
//                                       const SizedBox(height: 4),
//                                       Row(
//                                         mainAxisAlignment:
//                                             MainAxisAlignment.spaceBetween,
//                                         children: [
//                                           Expanded(
//                                             child: SingleChildScrollView(
//                                               scrollDirection: Axis.horizontal,
//                                               child: Text(
//                                                 invoice['invoice_number'] ==
//                                                         null
//                                                     ? "No invoice number found"
//                                                     : "#INV-${invoice['invoice_number']}",
//                                                 style: const TextStyle(
//                                                   fontWeight: FontWeight.w600,
//                                                   fontSize: 16,
//                                                   color: Colors.black87,
//                                                 ),
//                                               ),
//                                             ),
//                                           ),
//                                           SizedBox(width: 24),
//                                           Text(
//                                             '\₹${invoice['amount'] ?? '0'}',
//                                             style: const TextStyle(
//                                               fontWeight: FontWeight.w600,
//                                               fontSize: 16,
//                                               color: Color(0xFF192155),
//                                             ),
//                                           ),
//                                         ],
//                                       ),
//                                       const SizedBox(height: 8),
//                                       Align(
//                                         alignment: Alignment.centerLeft,
//                                         child: Text(
//                                           invoice['vendor_name'] ??
//                                               'No company found',
//                                           style: TextStyle(
//                                             fontSize: 14,
//                                             color: Colors.grey.shade600,
//                                           ),
//                                         ),
//                                       ),
//                                       const SizedBox(height: 9),
//                                       Divider(
//                                         color: Colors.grey.shade200,
//                                         thickness: 1,
//                                         height: 1,
//                                       ),
//                                       const SizedBox(height: 9),
//                                       Row(
//                                         children: [
//                                           Row(
//                                             children: [
//                                               Icon(
//                                                 Icons.calendar_today,
//                                                 size: 14,
//                                                 color: Colors.grey.shade500,
//                                               ),
//                                               const SizedBox(width: 6),
//                                               Text(
//                                                 _formatDate(
//                                                   invoice['date'] ??
//                                                       'No date found',
//                                                 ),
//                                                 style: TextStyle(
//                                                   fontSize: 13,
//                                                   color: Colors.grey.shade600,
//                                                 ),
//                                               ),
//                                             ],
//                                           ),
//                                           const Spacer(),
//                                           Row(
//                                             children: [
//                                               if (invoice['ai_status'] ==
//                                                   "AI_FAILED")
//                                                 Padding(
//                                                   padding:
//                                                       const EdgeInsets.only(
//                                                         left: 10,
//                                                       ),
//                                                   child: IconButton(
//                                                     onPressed:
//                                                         _reprocessingIds
//                                                                 .contains(
//                                                                   invoice['id'],
//                                                                 )
//                                                             ? null
//                                                             : () async {
//                                                               final invoiceId =
//                                                                   invoice['id'];
//                                                               setState(() {
//                                                                 _reprocessingIds
//                                                                     .add(
//                                                                       invoiceId,
//                                                                     );
//                                                               });
//
//                                                               try {
//                                                                 await InvoiceListService()
//                                                                     .reprocessInvoice(
//                                                                       id:
//                                                                           invoiceId,
//                                                                     );
//
//                                                                 if (mounted) {
//                                                                   setState(() {
//                                                                     final invoiceIndex =
//                                                                         _invoices.indexWhere(
//                                                                           (
//                                                                             inv,
//                                                                           ) =>
//                                                                               inv['id'] ==
//                                                                               invoiceId,
//                                                                         );
//                                                                     if (invoiceIndex !=
//                                                                         -1) {
//                                                                       _invoices[invoiceIndex]['ai_status'] =
//                                                                           'AI_PROCESSING';
//                                                                     }
//                                                                   });
//
//                                                                   ScaffoldMessenger.of(
//                                                                     context,
//                                                                   ).showSnackBar(
//                                                                     SnackBar(
//                                                                       content:
//                                                                           const Text(
//                                                                             'Invoice reprocessing started successfully',
//                                                                           ),
//                                                                       backgroundColor:
//                                                                           Colors
//                                                                               .green
//                                                                               .shade400,
//                                                                       behavior:
//                                                                           SnackBarBehavior
//                                                                               .floating,
//                                                                       shape: RoundedRectangleBorder(
//                                                                         borderRadius:
//                                                                             BorderRadius.circular(
//                                                                               12,
//                                                                             ),
//                                                                       ),
//                                                                     ),
//                                                                   );
//                                                                 }
//                                                               } catch (e) {
//                                                                 if (mounted) {
//                                                                   print(
//                                                                     "AI Processing Failed $e",
//                                                                   );
//                                                                   ScaffoldMessenger.of(
//                                                                     context,
//                                                                   ).showSnackBar(
//                                                                     SnackBar(
//                                                                       content: Text(
//                                                                         'AI Processing Failed',
//                                                                       ),
//                                                                       backgroundColor:
//                                                                           Colors
//                                                                               .red
//                                                                               .shade400,
//                                                                       behavior:
//                                                                           SnackBarBehavior
//                                                                               .floating,
//                                                                       shape: RoundedRectangleBorder(
//                                                                         borderRadius:
//                                                                             BorderRadius.circular(
//                                                                               12,
//                                                                             ),
//                                                                       ),
//                                                                     ),
//                                                                   );
//                                                                 }
//                                                               } finally {
//                                                                 if (mounted) {
//                                                                   setState(() {
//                                                                     _reprocessingIds
//                                                                         .remove(
//                                                                           invoiceId,
//                                                                         );
//                                                                   });
//                                                                 }
//                                                               }
//                                                             },
//                                                     icon:
//                                                         _reprocessingIds
//                                                                 .contains(
//                                                                   invoice['id'],
//                                                                 )
//                                                             ? SizedBox(
//                                                               width: 24,
//                                                               height: 24,
//                                                               child: CircularProgressIndicator(
//                                                                 strokeWidth: 2,
//                                                                 valueColor:
//                                                                     AlwaysStoppedAnimation(
//                                                                       Colors
//                                                                           .blue[900]!,
//                                                                     ),
//                                                               ),
//                                                             )
//                                                             : Icon(
//                                                               CupertinoIcons
//                                                                   .arrow_clockwise,
//                                                               color:
//                                                                   Colors
//                                                                       .blue[900],
//                                                             ),
//                                                   ),
//                                                 ),
//                                               _getStatusChip(
//                                                 invoice['ai_status'],
//                                               ),
//                                             ],
//                                           ),
//                                         ],
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ),
//                             );
//                           },
//                         ),
//               ),
//             ],
//           ),
//           if (_loadingPreviewId != null)
//             Container(
//               color: Colors.black45,
//               child: const Center(
//                 child: CircularProgressIndicator(
//                   valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E88E5)),
//                 ),
//               ),
//             ),
//         ],
//       ),
//       floatingActionButton: Container(
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(12),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.1),
//               blurRadius: 10,
//               offset: const Offset(0, 3),
//             ),
//           ],
//         ),
//         child: FloatingActionButton.extended(
//           onPressed: () {
//             if (!_isCameraPermissionGranted || !_isStoragePermissionGranted) {
//               ScaffoldMessenger.of(context).showSnackBar(
//                 SnackBar(
//                   content: Text(
//                     'Please grant camera and storage permissions to add photos or documents.',
//                   ),
//                   backgroundColor: Colors.red.shade400,
//                   behavior: SnackBarBehavior.floating,
//                   shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                 ),
//               );
//               return;
//             }
//             _showUploadOptions(context);
//           },
//           backgroundColor: Color(0xFF192155),
//           foregroundColor: Colors.white,
//           icon: const Icon(Icons.upload_rounded, size: 20),
//           label: const Text('Upload', style: TextStyle(fontSize: 14)),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//         ),
//       ),
//     );
//   }
// }
