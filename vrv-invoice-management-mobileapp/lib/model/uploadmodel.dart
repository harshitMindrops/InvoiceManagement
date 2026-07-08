class InvoiceUploadResponse {
  final String? id;
  final String? uploadedFileId; // Make nullable
  final String? invoiceNumber;
  final String? vendorName;
  final String? date;
  final double? amount;
  final String? dueDate;
  final String? aiStatus;
  final String? invoiceStatus;
  final String? createdAt; // Make nullable
  final String? updatedAt; // Make nullable
  final String? deletedAt;
  final List<LineItem>? lineItems;

  InvoiceUploadResponse({
    this.id,
    this.uploadedFileId,
    this.invoiceNumber,
    this.vendorName,
    this.date,
    this.amount,
    this.dueDate,
    this.aiStatus,
    this.invoiceStatus,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.lineItems,
  });

  factory InvoiceUploadResponse.fromJson(Map<String, dynamic> json) {
    // Helper to safely convert to String
    String? safeToString(dynamic value) {
      return value?.toString(); // Return null if value is null
    }

    // Helper to safely convert to double
    double? safeToDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null; // Return null for invalid types
    }

    return InvoiceUploadResponse(
      id: safeToString(json['id']),
      uploadedFileId: safeToString(json['uploaded_file_id']),
      invoiceNumber: safeToString(json['invoice_number']),
      vendorName: safeToString(json['company_name']),
      date: safeToString(json['date'] ?? json['invoice_date']),
      amount: safeToDouble(json['amount']),
      dueDate: safeToString(json['due_date']),
      aiStatus: safeToString(json['ai_status']),
      invoiceStatus: safeToString(json['invoice_status']),
      createdAt: safeToString(json['created_at']),
      updatedAt: safeToString(json['updated_at']),
      deletedAt: safeToString(json['deleted_at']),
    );
  }
}

class LineItem {
  final String description;
  final int quantity;
  final double price;
  final double total;

  LineItem({
    required this.description,
    required this.quantity,
    required this.price,
    required this.total,
  });
}
