import 'package:flutter/material.dart';

/// A padded column that fills the viewport when its content is short, and
/// scrolls when it is not.
///
/// The QR and code screens put [Spacer]s between their sections so the content
/// sits centred on a tall screen. A bare [Column] has nowhere to go when the
/// content is taller than the body, so the actions at the bottom were clipped
/// with no way to scroll to them.
///
/// A plain [SingleChildScrollView] is not enough either: it gives the column
/// unbounded height, and every [Spacer] collapses to nothing. [IntrinsicHeight]
/// restores a finite height for them - the content's natural height when it
/// overflows, the viewport height when it does not.
///
/// Because of that, every child must be able to report an intrinsic height.
/// Most widgets can, but a [LayoutBuilder] cannot: a widget that builds one
/// (a QR image, for example) needs a fixed-size box around it so the
/// measurement stops before it gets there.
class ScrollableFill extends StatelessWidget {
  final EdgeInsets padding;
  final List<Widget> children;

  const ScrollableFill({
    super.key,
    this.padding = const EdgeInsets.all(24.0),
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight - padding.vertical;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: available > 0 ? available : 0.0,
            ),
            child: IntrinsicHeight(child: Column(children: children)),
          ),
        );
      },
    );
  }
}
