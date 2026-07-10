// import 'package:flutter/material.dart';
//
// class InvoiceReviewBottomSheet {
//   static Future<bool?> show({
//     required BuildContext parentContext,
//     required List<Map<String, dynamic>> categories,
//     required String? selectedCategoryId,
//     required TextEditingController invoiceNumberController,
//     required TextEditingController companyNameController,
//     required TextEditingController invoiceDateController,
//     required TextEditingController amountController,
//     required GlobalKey<FormState> formKey,
//     required dynamic
//     confirmResponse, // Assuming this contains uploadedFiles and aiData
//     required dynamic api, // Assuming this is the API service
//     required Function fetchInvoices, // Callback to fetch invoices
//     required Function setState, // Parent widget's setState
//   }) async {
//     return await showModalBottomSheet<bool?>(
//       context: parentContext,
//       isDismissible: false, // Prevent dismissal by tapping outside
//       enableDrag: false, // Prevent dragging to dismiss
//       isScrollControlled: true, // Allow full height for content
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
//       ),
//       builder: (context) {
//         String? localSelectedCategoryId =
//             selectedCategoryId; // Local state for category
//
//         return StatefulBuilder(
//           builder: (BuildContext context, StateSetter sheetSetState) {
//             return SafeArea(
//               child: Padding(
//                 padding: EdgeInsets.only(
//                   bottom:
//                       MediaQuery.of(
//                         context,
//                       ).viewInsets.bottom, // Adjust for keyboard
//                   left: 16,
//                   right: 16,
//                   top: 16,
//                 ),
//                 child: SingleChildScrollView(
//                   child: Form(
//                     key: formKey,
//                     child: Column(
//                       mainAxisSize: MainAxisSize.min,
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const Row(
//                           children: [
//                             Icon(Icons.check_circle, color: Color(0xFF192155)),
//                             SizedBox(width: 8),
//                             Text(
//                               'Review AI \n Extracted Data',
//                               style: TextStyle(
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 18,
//                               ),
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 16),
//                         DropdownButtonFormField<String>(
//                           decoration: InputDecoration(
//                             labelText: 'Category',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(
//                               horizontal: 16,
//                               vertical: 12,
//                             ),
//                             filled: true,
//                             fillColor: Colors.grey.shade100,
//                           ),
//                           value: localSelectedCategoryId,
//                           items:
//                               categories
//                                   .where((category) => category['name'] != null)
//                                   .map(
//                                     (category) => DropdownMenuItem(
//                                       value: category['id']?.toString(),
//                                       child: Text(category['name']!),
//                                     ),
//                                   )
//                                   .toList(),
//                           onChanged: (value) {
//                             sheetSetState(() {
//                               localSelectedCategoryId = value;
//                             });
//                           },
//                           validator: (value) {
//                             if (value == null || value.isEmpty) {
//                               return 'Please select a category';
//                             }
//                             return null;
//                           },
//                         ),
//                         const SizedBox(height: 16),
//                         TextField(
//                           decoration: InputDecoration(
//                             labelText: 'Invoice Number',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(
//                               horizontal: 16,
//                               vertical: 12,
//                             ),
//                             filled: true,
//                             fillColor: Colors.grey.shade100,
//                           ),
//                           controller: invoiceNumberController,
//                         ),
//                         const SizedBox(height: 16),
//                         TextFormField(
//                           decoration: InputDecoration(
//                             labelText: 'Company Name',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(
//                               horizontal: 16,
//                               vertical: 12,
//                             ),
//                             filled: true,
//                             fillColor: Colors.grey.shade100,
//                           ),
//                           controller: companyNameController,
//                           validator: (value) {
//                             if (value == null || value.trim().isEmpty) {
//                               return 'Please enter a company name';
//                             }
//                             return null;
//                           },
//                         ),
//                         const SizedBox(height: 16),
//                         Row(
//                           children: [
//                             Expanded(
//                               child: TextFormField(
//                                 decoration: InputDecoration(
//                                   labelText: 'Invoice Date',
//                                   border: OutlineInputBorder(
//                                     borderRadius: BorderRadius.circular(12),
//                                   ),
//                                   contentPadding: const EdgeInsets.symmetric(
//                                     horizontal: 16,
//                                     vertical: 12,
//                                   ),
//                                   filled: true,
//                                   fillColor: Colors.grey.shade100,
//                                 ),
//                                 controller: invoiceDateController,
//                                 readOnly: true,
//                               ),
//                             ),
//                             const SizedBox(width: 8),
//                             IconButton(
//                               icon: const Icon(
//                                 Icons.calendar_today,
//                                 color: Color(0xFF192155),
//                               ),
//                               onPressed: () async {
//                                 final DateTime? picked = await showDatePicker(
//                                   context: context,
//                                   initialDate: DateTime.now(),
//                                   firstDate: DateTime(2000),
//                                   lastDate: DateTime(2100),
//                                 );
//                                 if (picked != null) {
//                                   invoiceDateController
//                                       .text = _formatDateToYYYYMMDD(
//                                     picked.toIso8601String(),
//                                   );
//                                 }
//                               },
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 16),
//                         TextField(
//                           decoration: InputDecoration(
//                             labelText: 'Amount',
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                             contentPadding: const EdgeInsets.symmetric(
//                               horizontal: 16,
//                               vertical: 12,
//                             ),
//                             filled: true,
//                             fillColor: Colors.grey.shade100,
//                           ),
//                           controller: amountController,
//                           keyboardType: const TextInputType.numberWithOptions(
//                             decimal: true,
//                           ),
//                         ),
//                         const SizedBox(height: 24),
//                         Row(
//                           mainAxisAlignment: MainAxisAlignment.end,
//                           children: [
//                             TextButton(
//                               onPressed: () async {
//                                 try {
//                                   final uploadedFileIds =
//                                       confirmResponse.uploadedFiles
//                                           .map((file) => file.id)
//                                           .toList();
//                                   if (uploadedFileIds.isEmpty) {
//                                     throw Exception(
//                                       'No valid uploaded file IDs found',
//                                     );
//                                   }
//
//                                   await api.cancelUpload(uploadedFileIds);
//                                   ScaffoldMessenger.of(
//                                     parentContext,
//                                   ).showSnackBar(
//                                     SnackBar(
//                                       content: const Text(
//                                         'Upload cancelled for invoice',
//                                       ),
//                                       backgroundColor: Colors.orange.shade400,
//                                       behavior: SnackBarBehavior.floating,
//                                       shape: RoundedRectangleBorder(
//                                         borderRadius: BorderRadius.circular(12),
//                                       ),
//                                     ),
//                                   );
//                                   Navigator.pop(context, false);
//                                 } catch (e) {
//                                   Navigator.pop(context, false);
//                                 } finally {
//                                   await fetchInvoices();
//                                   setState(() {
//                                     _selectedFile = null;
//                                     _selectedImages.clear();
//                                     _isPhotoTaken = false;
//                                   });
//                                 }
//                               },
//                               style: TextButton.styleFrom(
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 24,
//                                   vertical: 12,
//                                 ),
//                               ),
//                               child: Text(
//                                 'Cancel',
//                                 style: TextStyle(color: Colors.grey.shade600),
//                               ),
//                             ),
//                             const SizedBox(width: 8),
//                             ElevatedButton(
//                               onPressed: () async {
//                                 if (!formKey.currentState!.validate()) {
//                                   return;
//                                 }
//                                 try {
//                                   final uploadedFileIds =
//                                       confirmResponse.uploadedFiles
//                                           .map((file) => file.id)
//                                           .toList();
//                                   if (uploadedFileIds.isEmpty) {
//                                     throw Exception(
//                                       'No valid uploaded file IDs found',
//                                     );
//                                   }
//
//                                   final aiData = {
//                                     'company_name': companyNameController.text,
//                                     'invoice_number':
//                                         invoiceNumberController.text,
//                                     'amount':
//                                         double.tryParse(
//                                           amountController.text,
//                                         ) ??
//                                         0.0,
//                                     'date': invoiceDateController.text,
//                                     'line_items':
//                                         confirmResponse.aiData.lineItems
//                                             .map((item) => item.toJson())
//                                             .toList(),
//                                   };
//
//                                   print(
//                                     'Sending commit payload: {category_id: $localSelectedCategoryId, ai_data: $aiData, uploaded_file_ids: $uploadedFileIds}',
//                                   );
//
//                                   await api.commitInvoice(
//                                     categoryId: localSelectedCategoryId ?? '',
//                                     aiData: aiData,
//                                     uploadedFileIds: uploadedFileIds,
//                                   );
//                                   ScaffoldMessenger.of(
//                                     parentContext,
//                                   ).showSnackBar(
//                                     SnackBar(
//                                       content: Text(
//                                         'Invoice ${invoiceNumberController.text} committed successfully',
//                                       ),
//                                       backgroundColor: Colors.green.shade400,
//                                       behavior: SnackBarBehavior.floating,
//                                       shape: RoundedRectangleBorder(
//                                         borderRadius: BorderRadius.circular(12),
//                                       ),
//                                     ),
//                                   );
//                                   Navigator.pop(context, true);
//                                 } catch (e) {
//                                   Navigator.pop(context, true);
//                                 } finally {
//                                   await _fetchInvoices();
//                                   setState(() {
//                                     _selectedFile = null;
//                                     _selectedImages.clear();
//                                     _isPhotoTaken = false;
//                                   });
//                                 }
//                               },
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: const Color(0xFF192155),
//                                 foregroundColor: Colors.white,
//                                 padding: const EdgeInsets.symmetric(
//                                   horizontal: 24,
//                                   vertical: 12,
//                                 ),
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(12),
//                                 ),
//                               ),
//                               child: const Text('OK'),
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 16),
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );
//   }
//
//   static String _formatDateToYYYYMMDD(String isoDate) {
//     final date = DateTime.parse(isoDate);
//     return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
//   }
// }
