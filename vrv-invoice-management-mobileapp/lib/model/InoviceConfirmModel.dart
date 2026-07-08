class InvoiceConfirmUploadResponse {
  final String message;
  final List<UploadedFile> uploadedFiles;
  final AiData aiData;

  InvoiceConfirmUploadResponse({
    required this.message,
    required this.uploadedFiles,
    required this.aiData,
  });

  factory InvoiceConfirmUploadResponse.fromJson(Map<String, dynamic> json) {
    return InvoiceConfirmUploadResponse(
      message: json['message'] as String,
      uploadedFiles:
          (json['uploaded_files'] as List<dynamic>)
              .map(
                (file) => UploadedFile.fromJson(file as Map<String, dynamic>),
              )
              .toList(),
      aiData: AiData.fromJson(json['ai_data'] as Map<String, dynamic>),
    );
  }
}

class UploadedFile {
  final String id;
  final String url;

  UploadedFile({required this.id, required this.url});

  factory UploadedFile.fromJson(Map<String, dynamic> json) {
    return UploadedFile(id: json['id'] as String, url: json['url'] as String);
  }
}

class AiData {
  final String invoiceNumber;
  final String companyName;
  final String invoiceDate;
  final double amount;
  final String dueDate;
  final List<LineItem> lineItems;

  AiData({
    required this.invoiceNumber,
    required this.companyName,
    required this.invoiceDate,
    required this.amount,
    required this.dueDate,
    required this.lineItems,
  });

  factory AiData.fromJson(Map<String, dynamic> json) {
    return AiData(
      invoiceNumber: json['invoice_number'] as String,
      companyName: json['company_name'] as String,
      invoiceDate: json['invoice_date'] as String,
      amount: (json['amount'] as num).toDouble(),
      dueDate: json['due_date'] as String,
      lineItems:
          (json['line_items'] as List<dynamic>)
              .map((item) => LineItem.fromJson(item as Map<String, dynamic>))
              .toList(),
    );
  }
}

class LineItem {
  final String description;
  final int? quantity;
  final double? price;
  final double total;

  LineItem({
    required this.description,
    this.quantity,
    this.price,
    required this.total,
  });

  factory LineItem.fromJson(Map<String, dynamic> json) {
    return LineItem(
      description: json['description'] as String,
      quantity: json['quantity'] != null ? json['quantity'] as int : null,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      total: (json['total'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'quantity': quantity,
      'price': price,
      'total': total,
    };
  }
}
