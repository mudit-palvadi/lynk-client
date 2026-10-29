import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// One control the home walkthrough points at.
class HomeCoachMarkStep {
  /// The widget to highlight. Its render box supplies the spotlight.
  final GlobalKey targetKey;

  final String title;
  final String description;

  const HomeCoachMarkStep({
    required this.targetKey,
    required this.title,
    required this.description,
  });
}

/// A one-time guided tour of the home screen.
///
/// The rest of the screen is dimmed, a hole is cut over the target, and a card
/// explains it. The home screen stays untouched underneath, so the highlight
/// follows the real widget instead of a picture of it.
class HomeCoachMarks extends StatefulWidget {
  final List<HomeCoachMarkStep> steps;
  final VoidCallback onFinished;

  const HomeCoachMarks({
    super.key,
    required this.steps,
    required this.onFinished,
  });

  @override
  State<HomeCoachMarks> createState() => _HomeCoachMarksState();
}

class _HomeCoachMarksState extends State<HomeCoachMarks> {
  int _index = 0;
  Rect? _hole;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(_index));
  }

  /// Scrolls the target into view, then measures where it sits on screen.
  Future<void> _reveal(int index) async {
    if (index >= widget.steps.length) return;
    final targetContext = widget.steps[index].targetKey.currentContext;
    if (targetContext == null) return;

    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
    if (!mounted || _index != index) return;

    final overlayBox = context.findRenderObject() as RenderBox?;
    final targetBox =
        widget.steps[index].targetKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (overlayBox == null || targetBox == null || !targetBox.hasSize) return;

    final topLeft = overlayBox.globalToLocal(
      targetBox.localToGlobal(Offset.zero),
    );
    setState(() {
      _hole = Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        targetBox.size.width,
        targetBox.size.height,
      ).inflate(4);
    });
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  void _next() {
    if (_index >= widget.steps.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _index++;
      _hole = null;
    });
    _reveal(_index);
  }

  void _back() {
    if (_index == 0) return;
    setState(() {
      _index--;
      _hole = null;
    });
    _reveal(_index);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) return const SizedBox.shrink();

    final step = widget.steps[_index];
    final hole = _hole;
    final media = MediaQuery.of(context);
    final cardAtTop = hole != null && hole.center.dy > media.size.height / 2;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Stack(
        children: [
          // Swallows taps so the screen below cannot be used mid-tour.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(
                painter: _SpotlightPainter(
                  hole: hole,
                  color: AppTheme.of(context).primary,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: cardAtTop ? media.padding.top + 16 : null,
            bottom: cardAtTop ? null : media.padding.bottom + 16,
            child: _buildCard(step),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(HomeCoachMarkStep step) {
    final isLast = _index == widget.steps.length - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(
        color: AppTheme.of(context).cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.of(context).primary.withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 16,
                color: AppTheme.of(context).primary,
              ),
              const SizedBox(width: 6),
              Text(
                '${_index + 1} of ${widget.steps.length}',
                style: TextStyle(
                  color: AppTheme.of(context).textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            step.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.of(context).textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step.description,
            style: TextStyle(
              color: AppTheme.of(context).textSecondary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: _finish,
                child: Text(
                  'Skip',
                  style: TextStyle(color: AppTheme.of(context).textSecondary),
                ),
              ),
              const Spacer(),
              if (_index > 0)
                TextButton(onPressed: _back, child: const Text('Back')),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: _next,
                // The app theme makes buttons full-width, which a Row cannot
                // give a child; this one sizes to its label instead.
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(96, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: Text(isLast ? 'Got it' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paints the dimmed screen with a rounded hole over the target.
class _SpotlightPainter extends CustomPainter {
  final Rect? hole;

  const _SpotlightPainter({this.hole, required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final hole = this.hole;
    Path? cut;
    if (hole != null) {
      cut = Path()
        ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(18)));
    }

    canvas.drawPath(
      cut == null ? outer : Path.combine(PathOperation.difference, outer, cut),
      Paint()..color = Colors.black.withValues(alpha: 0.78),
    );

    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole, const Radius.circular(18)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.color != color;
}
