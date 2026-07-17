import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class UploadBottomSheet extends StatelessWidget {
  final VoidCallback onCameraTap;
  final VoidCallback onFilesTap;

  const UploadBottomSheet({
    super.key,
    required this.onCameraTap,
    required this.onFilesTap,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onCameraTap,
    required VoidCallback onFilesTap,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (bottomSheetContext) => UploadBottomSheet(
            onCameraTap: () {
              Navigator.pop(bottomSheetContext);
              onCameraTap();
            },
            onFilesTap: () {
              Navigator.pop(bottomSheetContext);
              onFilesTap();
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraStatus = Permission.camera.status;
    final storageStatus = Permission.storage.status;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white],
          stops: [0.0, 0.35],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Upload Invoices',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color.fromARGB(255, 7, 13, 57),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose how you\'d like to add your invoice',
                style: TextStyle(
                  fontSize: 13,
                  color: Color.fromARGB(255, 54, 54, 54),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _UploadOptionCard(
                      icon: Icons.camera_alt_rounded,
                      gradientColors: const [
                        Color(0xFF6C8DFA),
                        Color(0xFF7C5CFA),
                      ],
                      title: 'Camera',
                      subtitle: 'Snap a photo of\nyour invoice.',
                      onTap: () async {
                        final status = await cameraStatus;
                        if (!status.isGranted) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Camera permission is required.',
                              ),
                              backgroundColor: Colors.red.shade400,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                          return;
                        }
                        onCameraTap();
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _UploadOptionCard(
                      icon: Icons.folder_rounded,
                      gradientColors: const [
                        Color(0xFFFFA751),
                        Color(0xFFE8722A),
                      ],
                      title: 'Files',
                      subtitle: 'Select documents\nfrom your device.',
                      onTap: () async {
                        // Android 11 and below: storage permission works.
                        // Android 13+ (like Android 14): use photos/videos instead of legacy storage.
                        // We try photos first (if available) and fallback to storage.

                        PermissionStatus status = await storageStatus;

                        if (Permission.photos != null) {
                          final photoStatus = await Permission.photos.status;
                          if (!photoStatus.isGranted) {
                            status = await Permission.photos.request();
                          } else {
                            status = photoStatus;
                          }
                        } else {
                          if (!status.isGranted) {
                            status = await Permission.storage.request();
                          }
                        }

                        if (!status.isGranted) {
                          // Final attempt: storage permission (covers Android 11)
                          if (!status.isGranted) {
                            status = await Permission.storage.request();
                          }
                        }

                        if (!status.isGranted) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Permission is required to pick documents/files.',
                              ),
                              backgroundColor: Colors.red.shade400,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                          return;
                        }

                        onFilesTap();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    'Cancel',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
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

class _UploadOptionCard extends StatelessWidget {
  final IconData icon;
  final List<Color> gradientColors;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _UploadOptionCard({
    required this.icon,
    required this.gradientColors,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
}
