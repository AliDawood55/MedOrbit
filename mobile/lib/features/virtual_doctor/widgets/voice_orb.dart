import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/virtual_doctor_provider.dart';

/// Responsive voice-state indicator driven exclusively by [ConsultState].
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.state,
    required this.semanticLabel,
  });

  final ConsultState state;
  final String semanticLabel;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _stateDuration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureMotion();
  }

  @override
  void didUpdateWidget(covariant VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _configureMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration get _stateDuration => switch (widget.state) {
        ConsultState.recording => const Duration(milliseconds: 1100),
        ConsultState.speaking => const Duration(milliseconds: 1400),
        ConsultState.thinking || ConsultState.transcribing =>
          const Duration(milliseconds: 1500),
        ConsultState.listening => const Duration(milliseconds: 2600),
        _ => const Duration(seconds: 3),
      };

  void _configureMotion() {
    final duration = AppTheme.motionDuration(context, _stateDuration);
    _reducedMotion = duration == Duration.zero;
    if (_reducedMotion) {
      _controller
        ..stop()
        ..value = 0.5;
      return;
    }
    _controller
      ..duration = duration
      ..repeat();
  }

  Color _color(BuildContext context) => switch (widget.state) {
        ConsultState.recording => AppTheme.danger,
        ConsultState.transcribing => AppTheme.accent,
        ConsultState.thinking => AppTheme.warning,
        ConsultState.speaking => Theme.of(context).colorScheme.primary,
        ConsultState.listening => AppTheme.success,
        ConsultState.complete => AppTheme.success,
        ConsultState.error => Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.primary,
      };

  double get _intensity => switch (widget.state) {
        ConsultState.recording => 1,
        ConsultState.speaking => 0.85,
        ConsultState.thinking || ConsultState.transcribing => 0.6,
        ConsultState.idle => 0.22,
        _ => 0.4,
      };

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final desiredSize = screenWidth < AppTheme.compactBreakpoint
        ? 124.0
        : screenWidth < AppTheme.wideBreakpoint
            ? 148.0
            : 176.0;
    final color = _color(context);

    return Semantics(
      container: true,
      image: true,
      liveRegion: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            var dimension = desiredSize;
            if (constraints.maxWidth.isFinite) {
              dimension = math.min(dimension, constraints.maxWidth);
            }
            if (constraints.maxHeight.isFinite) {
              dimension = math.min(dimension, constraints.maxHeight);
            }
            dimension = math.max(0, dimension);

            return RepaintBoundary(
              child: SizedBox.square(
                dimension: dimension,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = _controller.value * 2 * math.pi;
                    final pulse = _reducedMotion
                        ? 0.5
                        : (math.sin(t) + 1) / 2;
                    final slowPulse = _reducedMotion
                        ? 0.5
                        : (math.sin(t * 0.6) + 1) / 2;
                    final spread =
                        0.6 + (pulse * _intensity * 0.4);

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        _ring(
                          color,
                          dimension *
                              (0.85 + slowPulse * 0.15 * _intensity),
                          0.08 * _intensity,
                        ),
                        _ring(
                          color,
                          dimension *
                              (0.7 + pulse * 0.1 * _intensity),
                          0.14 * _intensity,
                        ),
                        Container(
                          width: dimension * 0.56,
                          height: dimension * 0.56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color,
                                Color.lerp(
                                  color,
                                  Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.black
                                      : AppTheme.violet,
                                  0.32,
                                )!,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(
                                  alpha: 0.42 * spread,
                                ),
                                blurRadius: dimension * 0.2 * spread,
                                spreadRadius: dimension * 0.03 * spread,
                              ),
                            ],
                          ),
                          child: Icon(
                            _icon,
                            size: dimension * 0.23,
                            color: Colors.white.withValues(alpha: 0.94),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData get _icon => switch (widget.state) {
        ConsultState.recording => Icons.mic_rounded,
        ConsultState.transcribing => Icons.graphic_eq_rounded,
        ConsultState.thinking => Icons.psychology_outlined,
        ConsultState.speaking => Icons.volume_up_rounded,
        ConsultState.complete => Icons.check_rounded,
        ConsultState.error => Icons.priority_high_rounded,
        _ => Icons.medical_services_outlined,
      };

  Widget _ring(Color color, double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(
          alpha: alpha.clamp(0.0, 1.0).toDouble(),
        ),
      ),
    );
  }
}
