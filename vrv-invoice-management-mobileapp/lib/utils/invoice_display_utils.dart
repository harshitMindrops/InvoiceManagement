import 'dart:io';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Color getCategoryAccentColor(String? categoryName) {
  final String name = (categoryName ?? 'Uncategorized').toLowerCase();
  if (name == 'all') return const Color(0xFF192155);
  const List<Color> palette = [
    Color(0xFF7C5CFA),
    Color(0xFF3CBD6B),
    Color(0xFF1E88E5),
    Color(0xFFE8A33D),
    Color(0xFFE0577B),
    Color(0xFF19A7A0),
    Color(0xFF6C63FF),
    Color(0xFFEF6C4D),
  ];
  final int hash = name.codeUnits.fold(0, (sum, code) => sum + code);
  return palette[hash % palette.length];
}

IconData getCategoryIcon(String? categoryName) {
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

Color getStatusAccentColor(String? status) {
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

Widget buildStatusChip(String? status) {
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

String formatInvoiceDate(String? date) {
  if (date == null) return 'No date Found';
  try {
    final DateTime parsedDate = DateTime.parse(date);
    return DateFormat('dd/MM/yyyy').format(parsedDate);
  } catch (e) {
    return 'No date Found';
  }
}

Color getColorForCategory(String? categoryName) {
  final String name = categoryName ?? 'Uncategorized';
  final int hash = name.codeUnits.fold(0, (sum, code) => sum + code);
  final Random random = Random(hash);
  return Color((random.nextDouble() * 0xFFFFFF).toInt()).withOpacity(0.3);
}

String formatFileSizeMb(int bytes) {
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}

Future<Map<String, String>> computeFileSizeLabels(Iterable<File> files) async {
  final labels = <String, String>{};
  for (final file in files) {
    final bytes = await file.length();
    labels[file.path] = formatFileSizeMb(bytes);
  }
  return labels;
}
