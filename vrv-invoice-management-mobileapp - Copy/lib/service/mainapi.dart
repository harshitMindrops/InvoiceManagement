import 'dart:convert'; // Added for jsonEncode
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/InoviceConfirmModel.dart';
import '../model/uploadmodel.dart';

class InvoiceApiService {
  final Dio _dio = Dio();

  // Allowed extensions and MIME types
  final List<String> allowedExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'doc',
    'docx',
  ];
  final List<String> allowedMimeTypes = [
    'application/pdf',
    'image/jpeg',
    'image/png',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ];

  Future<List<InvoiceUploadResponse>> uploadInvoices(
    FormData formData, {
    File? singleFile,
    List<File>? images,
    // required String categoryId,
  }) async {
    // formData.fields.add(MapEntry('category_id', categoryId));

    // Validate that only one type of upload is provided
    if (singleFile != null && images != null && images.isNotEmpty) {
      throw Exception(
        'Please provide either a single file or images, not both.',
      );
    }

    if (images != null && images.length > 3) {
      throw Exception('You can only upload up to 3 images at a time.');
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Authorization token not found in SharedPreferences.');
    }

    // Handle single file (PDF/DOC)
    if (singleFile != null) {
      String filePath = singleFile.path;
      String fileName = filePath.split('/').last;
      String? mimeType = lookupMimeType(filePath);
      String extension = fileName.split('.').last.toLowerCase();

      print('\n📁 Single File:');
      print('→ File Name: $fileName');
      print('→ MIME Type: $mimeType');
      print('→ Extension: .$extension');
      print('→ Size: ${await singleFile.length()} bytes');

      if (!['pdf', 'doc', 'docx'].contains(extension) ||
          mimeType == null ||
          ![
            'application/pdf',
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          ].contains(mimeType)) {
        throw Exception('Invalid file type. Allowed types: PDF, DOC, DOCX.');
      }

      final multipartFile = await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: MediaType.parse(mimeType),
      );
      formData.files.add(MapEntry('file', multipartFile));
    }

    // Handle images (JPG/PNG)
    if (images != null && images.isNotEmpty) {
      for (int i = 0; i < images.length; i++) {
        File image = images[i];
        String filePath = image.path;
        String fileName = filePath.split('/').last;
        String? mimeType = lookupMimeType(filePath);
        String extension = fileName.split('.').last.toLowerCase();

        print('\n🖼️ Image ${i + 1}:');
        print('→ File Name: $fileName');
        print('→ MIME Type: $mimeType');
        print('→ Extension: .$extension');
        print('→ Size: ${await image.length()} bytes');

        if (!['jpg', 'jpeg', 'png'].contains(extension) ||
            mimeType == null ||
            !['image/jpeg', 'image/png'].contains(mimeType)) {
          print('❌ Skipping $fileName due to invalid extension or MIME type.');
          continue;
        }

        final multipartFile = await MultipartFile.fromFile(
          filePath,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        );
        formData.files.add(MapEntry('images', multipartFile));
      }
    }

    if (formData.files.isEmpty &&
        (singleFile != null || (images != null && images.isNotEmpty))) {
      throw Exception(
        'No valid files to upload. Allowed types: PDF, DOC, DOCX or JPG, PNG.',
      );
    }

    if (formData.files.isEmpty) {
      print('⚠️ No files provided for upload, proceeding with form data only.');
    } else {
      print(
        '\n🚀 Uploading ${formData.files.length} valid file(s) to backend...',
      );
    }

    print('📤 FormData Fields: ${formData.fields}');
    print('📤 FormData Files: ${formData.files.map((e) => e.key).toList()}');

    try {
      final response = await _dio.post(
        "https://invoice-staging-api.mindrops.com/api/v1/invoices/upload",
        data: formData,
        options: Options(
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "multipart/form-data",
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      print('✅ Response Status: ${response.statusCode}');
      print('📦 Raw Response Body: ${jsonEncode(response.data)}');

      final body = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (body is Map<String, dynamic> && body.containsKey('ai_data')) {
          final aiData = body['ai_data'] as Map<String, dynamic>;
          final uploadedFiles = body['uploaded_files'] as List<dynamic>?;

          print('📋 Parsed AI Data: $aiData');

          List<String> uploadedFileIds = [];
          if (uploadedFiles != null && uploadedFiles.isNotEmpty) {
            uploadedFileIds =
                uploadedFiles
                    .map((file) => file['id']?.toString())
                    .where((id) => id != null)
                    .cast<String>()
                    .toList();
          }

          // Add uploaded_file_id to ai_data
          final modifiedAiData = {
            ...aiData,
            'uploaded_file_id': uploadedFileIds,
            // Add default values for required fields if needed
            'created_at':
                aiData['created_at'] ?? DateTime.now().toIso8601String(),
            'updated_at':
                aiData['updated_at'] ?? DateTime.now().toIso8601String(),
          };

          return uploadedFileIds
              .map(
                (id) => InvoiceUploadResponse.fromJson({
                  ...aiData,
                  'uploaded_file_id': id, // keep for backward compatibility
                }),
              )
              .toList();
        } else {
          throw Exception('Unexpected response format from server: $body');
        }
      } else {
        final errorMessage =
            body is Map && body.containsKey('message')
                ? body['message']
                : 'Unexpected error: ${response.statusCode}';
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: errorMessage,
        );
      }
    } catch (e) {
      print('❌ Upload Error: $e');
      rethrow;
    }
  }

  Future<InvoiceConfirmUploadResponse> commitInvoice({
    required String categoryId,
    required Map<String, dynamic> aiData,
    required List<String> uploadedFileIds,
  }) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Authorization token not found in SharedPreferences.');
    }

    final payload = {
      'category_id': categoryId,
      ...aiData,
      'uploaded_file_ids': uploadedFileIds,
    };

    print('📤 Commit Payload: ${jsonEncode(payload)}');

    try {
      final response = await _dio.post(
        "https://invoice-staging-api.mindrops.com/api/v1/invoices/commit",
        data: jsonEncode(payload),
        options: Options(
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      print('✅ Commit Response Status: ${response.statusCode}');
      print('📦 Commit Response Body: ${jsonEncode(response.data)}');

      final body = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (body is Map<String, dynamic>) {
          return InvoiceConfirmUploadResponse.fromJson(body);
        } else {
          throw Exception('Unexpected response format from server: $body');
        }
      } else {
        final errorMessage =
            body is Map && body.containsKey('message')
                ? body['message']
                : 'Unexpected error: ${response.statusCode}';
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: errorMessage,
        );
      }
    } catch (e) {
      print('❌ Commit Error: $e');
      rethrow;
    }
  }

  Future<void> cancelUpload(List<String> uploadedFileIds) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token == null || token.isEmpty) {
      throw Exception('Authorization token not found in SharedPreferences.');
    }

    print('📤 Cancel Upload File ID: $uploadedFileIds');

    try {
      final response = await _dio.post(
        "https://invoice-staging-api.mindrops.com/api/v1/invoices/cancel-upload",
        data: {'uploaded_file_ids': uploadedFileIds},
        options: Options(
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      print('✅ Cancel Upload Response Status: ${response.statusCode}');
      print('📦 Cancel Upload Response Body: ${jsonEncode(response.data)}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final body = response.data;
        final errorMessage =
            body is Map && body.containsKey('message')
                ? body['message']
                : 'Unexpected error: ${response.statusCode}';
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: errorMessage,
        );
      }
    } catch (e) {
      print('❌ Cancel Upload Error: $e');
      rethrow;
    }
  }
}
