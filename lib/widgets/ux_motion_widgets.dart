import 'package:material_ui/material_ui.dart';

import 'package:depot_telur_36/core/theme/app_theme.dart';

/// Pembungkus micro-interaction tekan & hover berbasis [Listener] dan [MouseRegion].
///
/// Menggunakan [Listener] agar tidak bersaing di GestureArena dengan [InkWell]
/// maupun [Semantics] di dalamnya, sekaligus menghormati Reduce Motion sistem.
class TactilePressScale extends StatefulWidget {
  const TactilePressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.hoverScale = 1.0,
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final double hoverScale;

  @override
  State<TactilePressScale> createState() => _TactilePressScaleState();
}

class _TactilePressScaleState extends State<TactilePressScale> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool next) {
    if (_pressed == next) return;
    setState(() => _pressed = next);
  }

  void _setHovered(bool next) {
    if (_hovered == next) return;
    setState(() => _hovered = next);
  }

  @override
  void didUpdateWidget(covariant TactilePressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final double targetScale;
    if (!widget.enabled || disableMotion) {
      targetScale = 1.0;
    } else if (_pressed) {
      targetScale = widget.pressedScale;
    } else if (_hovered) {
      targetScale = widget.hoverScale;
    } else {
      targetScale = 1.0;
    }

    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (widget.enabled) _setPressed(true);
        },
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          scale: targetScale,
          duration: disableMotion ? Duration.zero : AppTokens.microDuration,
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Transisi buka-tutup panel inline (foto picker, kartu konfirmasi hapus, pesan error)
/// secara halus dengan [SizeTransition] + [FadeTransition] + [SlideTransition]
/// serta hormat pada Reduce Motion, lengkap dengan callback [onRevealed] saat
/// ukuran akhir selesai terbuka agar scroll otomatis akurat.
class SoftAnimatedReveal extends StatefulWidget {
  const SoftAnimatedReveal({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.topCenter,
    this.slideOffset = const Offset(0, -0.04),
    this.onRevealed,
  });

  final bool visible;
  final Widget child;
  final AlignmentGeometry alignment;
  final Offset slideOffset;
  final VoidCallback? onRevealed;

  @override
  State<SoftAnimatedReveal> createState() => _SoftAnimatedRevealState();
}

class _SoftAnimatedRevealState extends State<SoftAnimatedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppTokens.stateDuration,
      value: widget.visible ? 1.0 : 0.0,
    );
    _curved = CurvedAnimation(
      parent: _controller,
      curve: AppTokens.arrivalCurve,
      reverseCurve: Curves.easeIn,
    );
    _controller.addStatusListener(_handleStatus);
  }

  void _handleStatus(AnimationStatus status) {
    if (!mounted) return;
    if (status == AnimationStatus.completed && widget.visible) {
      widget.onRevealed?.call();
    } else if (status == AnimationStatus.dismissed && !widget.visible) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    _controller.duration =
        disableMotion ? Duration.zero : AppTokens.stateDuration;
  }

  @override
  void didUpdateWidget(covariant SoftAnimatedReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    _controller.duration =
        disableMotion ? Duration.zero : AppTokens.stateDuration;

    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        if (disableMotion) {
          _controller.value = 1.0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.visible) {
              widget.onRevealed?.call();
            }
          });
        } else {
          _controller.forward();
        }
      } else {
        if (disableMotion) {
          _controller.value = 0.0;
        } else {
          _controller.reverse();
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _controller.isDismissed) {
      return const SizedBox.shrink();
    }

    final disableMotion = MediaQuery.disableAnimationsOf(context);

    Widget content = widget.child;
    if (!disableMotion && widget.slideOffset != Offset.zero) {
      content = SlideTransition(
        position: Tween<Offset>(
          begin: widget.slideOffset,
          end: Offset.zero,
        ).animate(_curved),
        child: content,
      );
    }

    return ClipRect(
      child: SizeTransition(
        sizeFactor: _curved,
        alignment: widget.alignment,
        child: FadeTransition(
          opacity: _curved,
          child: content,
        ),
      ),
    );
  }
}

/// Transisi pop berhingga untuk lencana notifikasi (`unread badge`) atau penghitung batch.
class AnimatedBadgePop extends StatelessWidget {
  const AnimatedBadgePop({
    super.key,
    required this.visible,
    required this.badgeKey,
    required this.child,
  });

  final bool visible;
  final Key badgeKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final duration = disableMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (widgetChild, animation) {
        if (disableMotion) {
          return widgetChild;
        }
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.55, end: 1.0).animate(animation),
            child: widgetChild,
          ),
        );
      },
      child: visible
          ? KeyedSubtree(key: badgeKey, child: child)
          : const SizedBox.shrink(key: ValueKey('badge_hidden')),
    );
  }
}

/// Ikon sinkronisasi dengan animasi putaran berhingga (one-shot) saat sinkronisasi berjalan.
///
/// Sengaja tidak menggunakan `.repeat()` agar hemat daya dan tidak menahan `pumpAndSettle`.
class RotatingSyncIcon extends StatefulWidget {
  const RotatingSyncIcon({
    super.key,
    required this.isSpinning,
    this.icon = Icons.sync_rounded,
    this.size = 20,
    required this.color,
  });

  final bool isSpinning;
  final IconData icon;
  final double size;
  final Color color;

  @override
  State<RotatingSyncIcon> createState() => _RotatingSyncIconState();
}

class _RotatingSyncIconState extends State<RotatingSyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.isSpinning &&
        !_controller.isAnimating &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant RotatingSyncIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSpinning && !oldWidget.isSpinning) {
      if (!MediaQuery.disableAnimationsOf(context)) {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutCubic,
      ),
      child: Icon(
        widget.icon,
        size: widget.size,
        color: widget.color,
      ),
    );
  }
}
