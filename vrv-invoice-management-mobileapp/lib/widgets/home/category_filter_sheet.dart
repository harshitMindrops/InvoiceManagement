import 'package:flutter/material.dart';

import '../../utils/invoice_display_utils.dart';

class CategoryFilterSheet extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final Map<String, dynamic>? selectedCategory;
  final ValueChanged<Map<String, dynamic>> onCategorySelected;

  const CategoryFilterSheet({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  static Future<void> show(
    BuildContext context, {
    required List<Map<String, dynamic>> categories,
    required Map<String, dynamic>? selectedCategory,
    required ValueChanged<Map<String, dynamic>> onCategorySelected,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.45),
      builder:
          (context) => CategoryFilterSheet(
            categories: categories,
            selectedCategory: selectedCategory,
            onCategorySelected: onCategorySelected,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
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
                            '${categories.length} categories available',
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
              Flexible(
                child:
                    categories.isEmpty
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
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 3),
                          itemBuilder: (context, index) {
                            final category = categories[index];
                            final bool isSelected =
                                selectedCategory?['id'] == category['id'];
                            final Color accent = getCategoryAccentColor(
                              category['name'],
                            );
                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  onCategorySelected(category);
                                  Navigator.pop(context);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
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
                                    borderRadius: BorderRadius.circular(14),
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
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          getCategoryIcon(category['name']),
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
                                                    ? const Color(0xFF192155)
                                                    : Colors.grey.shade800,
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
                                                  ? const Color(0xFF192155)
                                                  : Colors.transparent,
                                          border: Border.all(
                                            color:
                                                isSelected
                                                    ? const Color(0xFF192155)
                                                    : Colors.grey.shade300,
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
  }
}
