import 'package:flutter/material.dart';

class InvoiceSearchBar extends StatefulWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final Map<String, dynamic>? selectedCategory;
  final VoidCallback onFilterPressed;

  const InvoiceSearchBar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.selectedCategory,
    required this.onFilterPressed,
  });

  @override
  State<InvoiceSearchBar> createState() => _InvoiceSearchBarState();
}

class _InvoiceSearchBarState extends State<InvoiceSearchBar> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_onSearchTextChanged);
    super.dispose();
  }

  void _onSearchTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
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
                      widget.searchController.text.isNotEmpty
                          ? IconButton(
                            icon: Icon(
                              Icons.clear_rounded,
                              color: Colors.grey.shade400,
                            ),
                            onPressed: () {
                              widget.searchController.clear();
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
                  widget.selectedCategory?['id'] == null
                      ? null
                      : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF192155), Color(0xFF2A3577)],
                      ),
              color:
                  widget.selectedCategory?['id'] == null ? Colors.white : null,
              borderRadius: BorderRadius.circular(16),
              border:
                  widget.selectedCategory?['id'] == null
                      ? Border.all(color: Colors.grey.shade100)
                      : null,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF192155).withOpacity(
                    widget.selectedCategory?['id'] == null ? 0.08 : 0.28,
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
                    widget.selectedCategory?['id'] == null
                        ? Colors.grey.shade500
                        : Colors.white,
                size: 22,
              ),
              tooltip: 'Filter by Category',
              onPressed: widget.onFilterPressed,
            ),
          ),
        ],
      ),
    );
  }
}
