import 'package:flutter/material.dart';

/// Reports its child as "meaningfully viewed" once at least
/// [visibleFraction] of it has been on screen.
///
/// The web feed uses an `IntersectionObserver` with `threshold: 0.5` and
/// unobserves each card as soon as it fires. There is no visibility package
/// among this app's dependencies, and adding one just for telemetry is not
/// worth the footprint — so this measures the child's own render box
/// against the enclosing [Scrollable]'s viewport, which is the same
/// geometry an observer would use, and subscribes to that scrollable's
/// [ScrollPosition] to re-measure while the user scrolls.
///
/// Deliberate limitations, in preference to a heavier dependency:
///  * exposure is sampled once per frame, so a post flung past in under a
///    frame may not register;
///  * it measures the scroll viewport only — it does not know about a route
///    pushed on top, the app being backgrounded, or an obscuring overlay,
///    so a card left visible behind a modal sheet still counts.
///
/// Both are acceptable for engagement telemetry, which is advisory input to
/// `recommendation.service.js` ranking and never affects correctness.
class PostViewTracker extends StatefulWidget {
  const PostViewTracker({
    super.key,
    required this.child,
    required this.onViewed,
    this.visibleFraction = 0.5,
  });

  final Widget child;

  /// Called at most once per widget lifetime. The feed controller
  /// deduplicates per session on top of this.
  final VoidCallback onViewed;

  final double visibleFraction;

  @override
  State<PostViewTracker> createState() => _PostViewTrackerState();
}

class _PostViewTrackerState extends State<PostViewTracker> {
  bool _reported = false;
  bool _scheduled = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A list item is a *descendant* of its Scrollable, so scroll
    // notifications never reach it — the position itself is the only
    // signal available from down here.
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_scheduleEvaluation);
      _position = next;
      if (!_reported) _position?.addListener(_scheduleEvaluation);
    }
    _scheduleEvaluation();
  }

  @override
  void didUpdateWidget(PostViewTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleEvaluation();
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleEvaluation);
    super.dispose();
  }

  /// Coalesces layout-time and scroll-time triggers into one check per
  /// frame — a fling otherwise measures the same card many times over.
  void _scheduleEvaluation() {
    if (_reported || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _evaluate();
    });
  }

  void _evaluate() {
    if (_reported || !mounted) return;

    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (box.size.height <= 0) return;

    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    final RenderBox? reference = viewport is RenderBox && viewport.attached
        ? viewport
        : null;

    final double viewportHeight;
    final double top;
    if (reference == null) {
      // Not inside a Scrollable (a single card in a test, or a short
      // non-scrolling feed): fall back to the window, which is what the web
      // observer does when it is given no scrolling root.
      viewportHeight = MediaQuery.sizeOf(context).height;
      top = box.localToGlobal(Offset.zero).dy;
    } else {
      viewportHeight = reference.size.height;
      top = box.localToGlobal(Offset.zero, ancestor: reference).dy;
    }
    if (viewportHeight <= 0) return;

    final bottom = top + box.size.height;
    final visible =
        (bottom < viewportHeight ? bottom : viewportHeight) -
        (top > 0 ? top : 0);
    if (visible <= 0) return;

    // A card taller than the viewport can never reach 50% of its own
    // height, so it qualifies on filling the viewport instead — otherwise a
    // long post would never register a view at any scroll position.
    final fraction = visible / box.size.height;
    final viewportFill = visible / viewportHeight;
    if (fraction < widget.visibleFraction &&
        viewportFill < widget.visibleFraction) {
      return;
    }

    _reported = true;
    _position?.removeListener(_scheduleEvaluation);
    widget.onViewed();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
