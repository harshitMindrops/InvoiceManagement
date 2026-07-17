import 'package:flutter/material.dart';

/// Reusable, self-contained animation helpers.
///
/// IMPORTANT: Ye widgets sirf VISUAL animations add karte hain.
/// Har widget apna khud ka AnimationController manage karta hai, isliye
/// ye kisi bhi screen ki logic / state management ko touch nahi karte.

/// [child] ko ek baar fade + slide karke screen par laata hai (jab pehli
/// baar build hota hai). List items ko stagger karne ke liye [delay] do.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset beginOffset;
  final Curve curve;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 450),
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 0.08),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.beginOffset,
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// [child] ke around ek subtle scale-down press feedback add karta hai.
/// Ye apna tap handling khud nahi karta — translucent [Listener] use karta
/// hai taaki andar ka InkWell / GestureDetector / onTap waise hi kaam karein.
class AnimatedTapScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;

  const AnimatedTapScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
  });

  @override
  State<AnimatedTapScale> createState() => _AnimatedTapScaleState();
}

class _AnimatedTapScaleState extends State<AnimatedTapScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value && mounted) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Gentle fade + upward slide page transition. [MaterialPageRoute] ka
/// drop-in replacement — navigation behaviour bilkul same rehta hai,
/// sirf transition smooth ho jaata hai.
Route<T> smoothPageRoute<T>(Widget page) {
  return smoothPageRouteBuilder<T>((_) => page);
}

/// Wahi smooth transition, lekin jab page ko lazily build karna ho
/// (jaise jab route ke andar koi logic/computation ho).
Route<T> smoothPageRouteBuilder<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
