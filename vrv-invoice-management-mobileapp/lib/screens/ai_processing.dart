import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Modern, professional "AI is processing your invoice" screen.
/// Light theme, inspired by the reference design but adapted to a
/// bright UI. Drop this widget into your existing route/screen —
/// no navigation, auth, or login logic is touched here.
class AiProcessingScreen extends StatefulWidget {
  const AiProcessingScreen({super.key});

  @override
  State<AiProcessingScreen> createState() => _AiProcessingScreenState();
}

class _AiProcessingScreenState extends State<AiProcessingScreen>
    with TickerProviderStateMixin {
  // Continuous ambient motion (float, scan line, pulse dot)
  late final AnimationController _loopController;
  // One-shot entrance for chips + progress bar
  late final AnimationController _introController;

  late final Animation<double> _floatAnimation;
  late final Animation<double> _scanAnimation;
  late final Animation<double> _progressAnimation;

  static const Color kIndigo = Color(0xFF4F46E5);
  static const Color kPurple = Color(0xFF7C3AED);
  static const Color kBlue = Color(0xFF3B82F6);
  static const Color kSuccess = Color(0xFF16A34A);
  static const Color kBg = Color(0xFFF6F7FB);
  static const Color kCardBorder = Color(0xFFE7E8F1);
  static const Color kMuted = Color(0xFF6B7280);

  final List<_ExtractedField> _fields = const [
    _ExtractedField(label: 'Vendor', icon: Icons.check_circle, done: true),
    _ExtractedField(label: 'GSTIN', icon: Icons.check_circle, done: true),
    _ExtractedField(
        label: 'Amount', icon: Icons.hourglass_top, done: false),
    _ExtractedField(label: 'Due date', icon: Icons.remove, done: false),
  ];

  @override
  void initState() {
    super.initState();

    _loopController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _floatAnimation = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _loopController, curve: Curves.easeInOut),
    );

    _scanAnimation = CurvedAnimation(
      parent: _loopController,
      curve: Curves.easeInOut,
    );

    _introController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..forward();

    _progressAnimation = Tween<double>(begin: 0, end: 0.64).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(0.15, 1.0, curve: Curves.easeOutCubic),
      ),
    );
  }

  @override
  void dispose() {
    _loopController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wrapped in `Material` so text/icons always render correctly
    // even if this widget is used inside an overlay/dialog/stack
    // that doesn't already sit under a Scaffold.
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Container(
            color: kBg,
            width: double.infinity,
            height: constraints.maxHeight,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatusPill(),
                    _buildDocumentStage(),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [kIndigo, kPurple],
                          ).createShader(bounds),
                          child: const Text(
                            'Extracting invoice details',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Our AI is reading vendor, tax and amount fields\n'
                          'from your invoice and validating them.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: kMuted,
                          ),
                        ),
                      ],
                    ),
                    _buildProgressBar(),
                    _buildSteps(),
                    _buildSecurityNote(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Top pill ─────────────────────────────────────────────
  Widget _buildStatusPill() {
    return AnimatedBuilder(
      animation: _loopController,
      builder: (context, child) {
        final glow = 0.4 + 0.6 * (0.5 + 0.5 * math.sin(_loopController.value * 2 * math.pi));
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: kIndigo.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: kIndigo.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kIndigo.withOpacity(glow),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'AI PROCESSING',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: kIndigo,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Document + floating chips ───────────────────────────
  Widget _buildDocumentStage() {
    // Fixed-width stage (not full screen width) so the chips can be
    // positioned relative to the document card instead of the edges
    // of whatever screen this is placed on.
    return Center(
      child: SizedBox(
        width: 260,
        height: 250,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Document mock-up
            AnimatedBuilder(
              animation: _floatAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _floatAnimation.value),
                  child: child,
                );
              },
              child: _buildDocumentMock(),
            ),
            // Floating field chips, staggered fade + slide in.
            // Positioned relative to the 260x250 stage, hugging the
            // corners of the 160x190 card that sits centered in it.
            Positioned(top: 2, left: 0, child: _animatedChip(0, _fields[0], _chipColor(true))),
            Positioned(top: 26, right: 0, child: _animatedChip(1, _fields[1], _chipColor(true))),
            Positioned(bottom: 48, left: 0, child: _animatedChip(2, _fields[2], _chipColor(false))),
            Positioned(bottom: 2, right: 6, child: _animatedChip(3, _fields[3], _chipColor(false))),
          ],
        ),
      ),
    );
  }

  Color _chipColor(bool done) => done ? kSuccess : kMuted;

  Widget _animatedChip(int index, _ExtractedField field, Color color) {
    final start = 0.1 * index;
    final anim = CurvedAnimation(
      parent: _introController,
      curve: Interval(start.clamp(0, 1), (start + 0.5).clamp(0, 1),
          curve: Curves.easeOutBack),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        return Opacity(
          opacity: anim.value.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - anim.value.clamp(0, 1))),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: kCardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(field.icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              field.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: field.done ? const Color(0xFF1F2937) : kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentMock() {
    return Container(
      width: 160,
      height: 190,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCardBorder),
        boxShadow: [
          BoxShadow(
            color: kIndigo.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kIndigo, kPurple]),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const Spacer(),
                    const Text('INV-08214',
                        style: TextStyle(fontSize: 8.5, color: kMuted, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                ..._buildSkeletonLines(const [0.9, 0.6, 0.75, 0.5, 0.65]),
                const Spacer(),
                Row(
                  children: [
                    Expanded(child: _skeletonLine(0.4)),
                    const SizedBox(width: 6),
                    Expanded(child: _skeletonLine(0.4)),
                  ],
                ),
              ],
            ),
          ),
          // sweeping scan line
          AnimatedBuilder(
            animation: _scanAnimation,
            builder: (context, child) {
              final t = _scanAnimation.value;
              final top = 14 + t * 160;
              return Positioned(
                top: top,
                left: 0,
                right: 0,
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        kIndigo.withOpacity(0),
                        kPurple.withOpacity(0.22),
                        kIndigo.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSkeletonLines(List<double> widths) {
    return [
      for (final w in widths) ...[
        _skeletonLine(w),
        const SizedBox(height: 7),
      ],
    ];
  }

  Widget _skeletonLine(double widthFactor) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: const Color(0xFFEEF0F6),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ── Progress bar ─────────────────────────────────────────
  Widget _buildProgressBar() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'PROCESSING',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: kMuted,
              ),
            ),
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) => Text(
                '${(_progressAnimation.value * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: kIndigo,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 9,
            color: const Color(0xFFE9EBF3),
            child: AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progressAnimation.value.clamp(0, 1),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [kBlue, kIndigo, kPurple]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ── Step indicator ──────────────────────────────────────
  Widget _buildSteps() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _stepDot(number: '1', label: 'Upload', state: _StepState.done),
        _stepConnector(),
        _stepDot(number: '2', label: 'Extract', state: _StepState.active),
        _stepConnector(),
        _stepDot(number: '3', label: 'Validate', state: _StepState.pending),
      ],
    );
  }

  Widget _stepConnector() {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 22),
        color: kCardBorder,
      ),
    );
  }

  Widget _stepDot({required String number, required String label, required _StepState state}) {
    Widget circle;
    switch (state) {
      case _StepState.done:
        circle = Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: kSuccess),
          child: const Icon(Icons.check, size: 15, color: Colors.white),
        );
        break;
      case _StepState.active:
        circle = AnimatedBuilder(
          animation: _loopController,
          builder: (context, child) {
            final scale = 1 + 0.08 * (0.5 + 0.5 * math.sin(_loopController.value * 2 * math.pi));
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [kIndigo, kPurple]),
                  boxShadow: [
                    BoxShadow(color: kIndigo.withOpacity(0.35), blurRadius: 10, spreadRadius: 1),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(number,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            );
          },
        );
        break;
      case _StepState.pending:
        circle = Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: kCardBorder, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(number,
              style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700, fontSize: 13)),
        );
        break;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        circle,
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: state == _StepState.pending ? kMuted : const Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  // ── Footer note ──────────────────────────────────────────
  Widget _buildSecurityNote() {
    // Flexible + centered text-align so this never overflows on
    // narrow screens — it wraps to a second line instead.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Padding(
          padding: EdgeInsets.only(top: 1.5),
          child: Icon(Icons.lock_outline, size: 13, color: kMuted),
        ),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Your invoice data stays encrypted end-to-end',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: kMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

enum _StepState { done, active, pending }

class _ExtractedField {
  final String label;
  final IconData icon;
  final bool done;
  const _ExtractedField({required this.label, required this.icon, required this.done});
}