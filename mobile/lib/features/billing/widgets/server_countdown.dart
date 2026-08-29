import 'dart:async';

import 'package:flutter/material.dart';

import 'billing_formatters.dart';

class ServerCountdown extends StatefulWidget {
  const ServerCountdown({
    required this.target,
    required this.serverTime,
    required this.isArabic,
    this.onElapsed,
    super.key,
  });

  final DateTime target;
  final DateTime serverTime;
  final bool isArabic;
  final VoidCallback? onElapsed;

  @override
  State<ServerCountdown> createState() => _ServerCountdownState();
}

class _ServerCountdownState extends State<ServerCountdown> {
  late Duration _initialRemaining;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  bool _notified = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(ServerCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target != widget.target ||
        oldWidget.serverTime != widget.serverTime) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    _elapsed
      ..reset()
      ..start();
    _notified = false;
    _initialRemaining = widget.target.difference(widget.serverTime);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final remaining = _remaining;
      if (remaining <= Duration.zero && !_notified) {
        _notified = true;
        widget.onElapsed?.call();
      }
      setState(() {});
    });
  }

  Duration get _remaining {
    final value = _initialRemaining - _elapsed.elapsed;
    return value.isNegative ? Duration.zero : value;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Text(
        formatRemainingDuration(_remaining, isArabic: widget.isArabic),
        textDirection: TextDirection.ltr,
      ),
    );
  }
}
