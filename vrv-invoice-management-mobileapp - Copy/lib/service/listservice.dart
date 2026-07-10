// listservice.dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvoiceListService {
  final Dio _dio = Dio();

  // Future<List<dynamic>> fetchInvoices({
  //   String? search,
  //   String? category,
  //   int limit = 10,
  //   int offset = 0,
  // }) async {
  //   final prefs = await SharedPreferences.getInstance();
  //   final token = prefs.getString("token");
  //
  //   if (token == null || token.isEmpty) {
  //     throw Exception("Token missing. Login required.");
  //   }
  //
  //   final Map<String, dynamic> payload = {
  //     'limit': limit,
  //     'offset': offset,
  //     'sortBy': 'created_at',
  //     'sortOrder': 'desc',
  //     'filters': <String, dynamic>{},
  //   };
  //
  //   if (category != null) {
  //     (payload['filters'] as Map<String, dynamic>)['category_id'] = category;
  //   }
  //
  //   if (search != null && search.trim().isNotEmpty) {
  //     (payload['filters'] as Map<String, dynamic>)['search'] = search.trim();
  //   }
  //
  //   final response = await _dio.post(
  //     'https://invoice-api.mindrops.com/api/v1/invoices',
  //     data: payload,
  //     options: Options(
  //       headers: {
  //         "Authorization": "Bearer $token",
  //         "Content-Type": "application/json",
  //       },
  //       validateStatus: (status) => status != null && status < 600,
  //     ),
  //   );
  //
  //   print('🔽 Invoice List Response: ${response.data}');
  //
  //   if (response.statusCode == 200) {
  //     final body = response.data;
  //
  //     if (body is Map<String, dynamic> && body.containsKey('invoices')) {
  //       return body['invoices'] as List<dynamic>;
  //     } else {
  //       throw Exception('Unexpected response: "invoices" key missing.');
  //     }
  //   } else {
  //     throw Exception(
  //       'API error ${response.statusCode}: ${response.statusMessage}',
  //     );
  //   }
  // }

  Future<List<Map<String, dynamic>>> fetchInvoices({
    String? search,
    String? category,
    int limit = 10,
    int offset = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");

    print("Token: $token");

    if (token == null || token.isEmpty) {
      throw Exception("Token missing. Login required.");
    }

    final Map<String, dynamic> payload = {
      'limit': limit,
      'offset': offset,
      'sortBy': 'created_at',
      'sortOrder': 'desc',
      'filters': <String, dynamic>{},
    };

    if (category != null) {
      payload['filters']['category_id'] = category;
    }

    if (search != null && search.trim().isNotEmpty) {
      payload['filters']['search'] = search.trim();
    }

    final response = await _dio.post(
      'https://invoice-staging-api.mindrops.com/api/v1/invoices',
      data: payload,
      options: Options(
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    print('🔽 Invoice List Response: ${response.data}');

    if (response.statusCode == 200) {
      final body = response.data;

      if (body is Map<String, dynamic> && body.containsKey('invoices')) {
        final invoices = body['invoices'];
        if (invoices is List) {
          return invoices.cast<Map<String, dynamic>>().toList();
        } else {
          throw Exception('Unexpected response: "invoices" is not a list.');
        }
      } else {
        throw Exception(
          'Unexpected response: "invoices" key missing or invalid format.',
        );
      }
    } else {
      throw Exception(
        'API error ${response.statusCode}: ${response.statusMessage}',
      );
    }
  }

  Future<Map<String, dynamic>?> reprocessInvoice({
    required String id,
    List<String>? uploadedFileIds,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) {
      throw Exception('Authentication token not found');
    }

    try {
      print('🔄 Reprocessing invoice with ID: $id');
      if (uploadedFileIds != null && uploadedFileIds.isNotEmpty) {
        print('📎 Uploaded File IDs: $uploadedFileIds');
      }

      // Build request body — send uploaded_file_ids if available
      final Map<String, dynamic> body = {};
      if (uploadedFileIds != null && uploadedFileIds.isNotEmpty) {
        body['uploaded_file_ids'] = uploadedFileIds;
      }

      final response = await _dio.post(
        'https://invoice-staging-api.mindrops.com/api/v1/invoices/$id/reapply-ai',
        data: body.isNotEmpty ? body : null,
        options: Options(
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      print('🔽 Reprocess API Response Status: ${response.statusCode}');
      print('🔽 Reprocess API Response Data: ${response.data}');

      // Handle different status codes
      switch (response.statusCode) {
        case 200:
        case 201:
          // Success case - invoice reprocessed successfully
          print('✅ Invoice reprocessed successfully');

          // Return the response data if available
          if (response.data != null && response.data is Map<String, dynamic>) {
            return response.data as Map<String, dynamic>;
          }
          return {
            'success': true,
            'message': 'Reprocessing started successfully',
          };

        case 401:
          throw Exception('Unauthorized: Invalid or expired token');
        case 404:
          throw Exception('Invoice not found');
        case 409:
          throw Exception('Invoice is already being processed');
        case 429:
          throw Exception('Rate limit exceeded. Please try again later');
        case 500:
          throw Exception('Server error occurred. Please try again later');
        default:
          final errorMessage = response.data?.toString() ?? 'Unknown error';
          throw Exception(
            'Failed to reprocess invoice (${response.statusCode}): $errorMessage',
          );
      }
    } on DioException catch (e) {
      print('❌ Dio Exception during reprocess: ${e.type} - ${e.message}');

      // Handle Dio specific errors
      if (e.type == DioExceptionType.connectionTimeout) {
        throw Exception(
          'Connection timeout. Please check your internet connection',
        );
      } else if (e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Response timeout. Please try again');
      } else if (e.type == DioExceptionType.connectionError) {
        throw Exception(
          'Network connection error. Please check your internet connection',
        );
      } else if (e.response != null) {
        final statusCode = e.response!.statusCode;
        final errorData = e.response!.data;

        print('❌ HTTP Error Response: $statusCode - $errorData');

        // Handle specific HTTP error responses
        switch (statusCode) {
          case 401:
            throw Exception('Authentication failed. Please login again');
          case 403:
            throw Exception(
              'Access forbidden. You don\'t have permission to reprocess this invoice',
            );
          case 404:
            throw Exception('Invoice not found');
          case 409:
            throw Exception('Invoice is already being processed');
          case 422:
            throw Exception(
              'Invalid request. This invoice cannot be reprocessed',
            );
          case 429:
            throw Exception(
              'Too many requests. Please wait before trying again',
            );
          case 500:
          case 502:
          case 503:
            throw Exception('Server error. Please try again later');
          default:
            throw Exception(
              'Request failed with status $statusCode: ${errorData?.toString() ?? "Unknown error"}',
            );
        }
      }

      throw Exception('Network error: ${e.message ?? "Connection failed"}');
    } catch (e) {
      print('❌ Generic Exception during reprocess: $e');
      // Generic error handling
      if (e is Exception) {
        rethrow; // Re-throw our custom exceptions
      }
      throw Exception('Failed to reprocess invoice: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("token");
    if (token == null) {
      throw Exception('Authentication token not found');
    }
    final String url =
        'https://invoice-staging-api.mindrops.com/api/v1/categories/list';

    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final data = {
      "filters": {"is_active": true, "is_deleted": false},
      "limit": 1000,
      "offset": 0,
      "sortBy": "name",
      "sortOrder": "asc",
    };

    try {
      final response = await _dio.post(
        url,
        data: data,
        options: Options(headers: headers),
      );
      // EXTRACT THE CATEGORY LIST FROM RESPONSE
      final List categories = response.data['categories'] ?? [];
      // RETURN ONLY id AND name
      return categories
          .map<Map<String, dynamic>>(
            (item) => {"id": item["id"], "name": item["name"]},
          )
          .toList();
    } on DioException catch (e) {
      throw Exception('Failed to load categories: ${e.message}');
    }
  }
}
