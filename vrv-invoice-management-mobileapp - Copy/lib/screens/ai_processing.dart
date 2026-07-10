import 'package:flutter/material.dart';
import 'dart:math' as math;

class InvoiceCard extends StatefulWidget {
  const InvoiceCard({super.key});

  @override
  _InvoiceCardState createState() => _InvoiceCardState();
}

class _InvoiceCardState extends State<InvoiceCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _spinAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _spinAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Stack(
          children: [
            // Subtle background animation
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.blue.withOpacity(0.1),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                );
              },
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated AI Brain Icon
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Main icon with pulse
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.blue, Colors.indigo],
                          ),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                    // Orbiting dots
                    AnimatedBuilder(
                      animation: _spinAnimation,
                      builder: (context, child) {
                        return Stack(
                          children: [
                            // Top dot
                            Transform.translate(
                              offset: Offset(0, -40 * math.cos(_spinAnimation.value)),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.blueAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            // Bottom dot
                            Transform.translate(
                              offset: Offset(0, 40 * math.cos(_spinAnimation.value)),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.indigoAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            // Left dot
                            Transform.translate(
                              offset: Offset(-40 * math.sin(_spinAnimation.value), 0),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.purpleAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            // Right dot
                            Transform.translate(
                              offset: Offset(40 * math.sin(_spinAnimation.value), 0),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.cyanAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Main text with gradient
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.blue, Colors.indigo],
                  ).createShader(bounds),
                  child: const Text(
                    'AI Processing Invoices',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // Base color for gradient
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Our AI is analyzing and extracting data from your invoices. This process ensures accurate data extraction and validation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),
                // Progress indicator
                Container(
                  width: 256,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return FractionallySizedBox(
                        widthFactor: 0.7, // 70% width
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.blue, Colors.indigo, Colors.purple],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Status dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBouncingDot(Colors.blue, 0),
                    const SizedBox(width: 8),
                    _buildBouncingDot(Colors.indigo, 0.2),
                    const SizedBox(width: 8),
                    _buildBouncingDot(Colors.purple, 0.4),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBouncingDot(Color color, double delay) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -8 * (math.sin(_controller.value * 2 * math.pi + delay * math.pi).abs())),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}