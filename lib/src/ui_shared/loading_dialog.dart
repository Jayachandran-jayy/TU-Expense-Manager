/// Themed loading dialogs and visual indicators with an animated currency coin
/// and capsule progress bar.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

/// An animated 3D spinning currency coin with a floating bobbing effect.
class AnimatedCoin extends StatefulWidget {
  const AnimatedCoin({
    super.key,
    this.symbol = '₹',
    this.size = 56,
  });

  final String symbol;
  final double size;

  @override
  State<AnimatedCoin> createState() => _AnimatedCoinState();
}

class _AnimatedCoinState extends State<AnimatedCoin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double value = _controller.value;
        final double angle = value * 2 * math.pi;
        final double bob = math.sin(value * 2 * math.pi) * 4;

        // Front vs back face detection to keep symbol legible
        final bool isBackFace = (angle % (2 * math.pi)) > (math.pi / 2) &&
            (angle % (2 * math.pi)) < (3 * math.pi / 2);

        return Transform.translate(
          offset: Offset(0, bob),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015) // perspective
              ..rotateY(angle),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFE066),
                    Color(0xFFFFC72C),
                    Color(0xFFE59400),
                    Color(0xFFB87300),
                  ],
                  stops: <double>[0.0, 0.35, 0.7, 1.0],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFFE59400).withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFFFFF6CC),
                  width: 2.2,
                ),
              ),
              child: Center(
                child: Transform.scale(
                  scaleX: isBackFace ? -1 : 1,
                  child: Container(
                    width: widget.size * 0.72,
                    height: widget.size * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD68A00).withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.symbol,
                        style: TextStyle(
                          fontSize: widget.size * 0.44,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF523300),
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A capsule-shaped progress bar with an animated shimmering gradient sweep,
/// or a filled determinate bar when [value] is provided.
class CoinProgressBar extends StatefulWidget {
  const CoinProgressBar({
    super.key,
    this.height = 10,
    this.width = 200,
    this.value,
  });

  final double height;
  final double width;
  final double? value;

  @override
  State<CoinProgressBar> createState() => _CoinProgressBarState();
}

class _CoinProgressBarState extends State<CoinProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.value == null) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(CoinProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != null && _controller.isAnimating) {
      _controller.stop();
    } else if (widget.value == null && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : const Color(0xFFE8ECEF);

    final double? value = widget.value;
    if (value != null) {
      final double clamped = value.clamp(0.0, 1.0);
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.height / 2),
          child: Container(
            color: backgroundColor,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: clamped),
              builder: (BuildContext context, double factor, Widget? child) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: factor,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            theme.colorScheme.primary,
                            const Color(0xFFFFC72C),
                            theme.colorScheme.primary,
                          ],
                        ),
                        borderRadius:
                            BorderRadius.circular(widget.height / 2),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.height / 2),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) {
            return Container(
              color: backgroundColor,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.45,
                      child: Transform.translate(
                        offset: Offset(
                          (_controller.value * 2.6 - 0.8) * widget.width,
                          0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                theme.colorScheme.primary.withValues(alpha: 0.1),
                                theme.colorScheme.primary,
                                const Color(0xFFFFC72C),
                                theme.colorScheme.primary,
                                theme.colorScheme.primary.withValues(alpha: 0.1),
                              ],
                            ),
                            borderRadius:
                                BorderRadius.circular(widget.height / 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A Material 3 dialog featuring the animated coin and progress bar for modal
/// loading feedback during blocking operations.
class LoadingModal extends StatelessWidget {
  const LoadingModal({
    super.key,
    required this.message,
    this.subtitle,
    this.symbol = '₹',
  });

  final String message;
  final String? subtitle;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedCoin(symbol: symbol, size: 56),
          const SizedBox(height: 20),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 20),
          const CoinProgressBar(height: 8, width: 180),
        ],
      ),
    );
  }
}

/// Executes [task] while displaying a non-dismissible [LoadingModal].
///
/// Guaranteed to dismiss cleanly upon task completion or error.
Future<T> withLoadingModal<T>({
  required BuildContext context,
  required String message,
  String? subtitle,
  String symbol = '₹',
  required Future<T> Function() task,
}) async {
  if (!context.mounted) return await task();

  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (BuildContext dialogContext) => PopScope(
      canPop: false,
      child: LoadingModal(
        message: message,
        subtitle: subtitle,
        symbol: symbol,
      ),
    ),
  ).then((_) {
    dialogOpen = false;
  });

  try {
    return await task();
  } finally {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}

/// Tracks progress for operations with a known or evolving total count.
class ProgressController extends ChangeNotifier {
  ProgressController({
    this.current = 0,
    this.total = 0,
    this.message,
    this.subtitle,
  });

  int current;
  int total;
  String? message;
  String? subtitle;

  double? get progress =>
      total > 0 ? (current / total).clamp(0.0, 1.0) : null;

  void update({
    int? current,
    int? total,
    String? message,
    String? subtitle,
  }) {
    var changed = false;
    if (current != null && current != this.current) {
      this.current = current;
      changed = true;
    }
    if (total != null && total != this.total) {
      this.total = total;
      changed = true;
    }
    if (message != null && message != this.message) {
      this.message = message;
      changed = true;
    }
    if (subtitle != null && subtitle != this.subtitle) {
      this.subtitle = subtitle;
      changed = true;
    }
    if (changed) notifyListeners();
  }
}

/// A modal dialog that listens to a [ProgressController] and displays determinate
/// or indeterminate loading progress alongside an [AnimatedCoin].
class ProgressModal extends StatelessWidget {
  const ProgressModal({
    super.key,
    required this.controller,
    required this.initialMessage,
    this.initialSubtitle,
    this.symbol = '₹',
  });

  final ProgressController controller;
  final String initialMessage;
  final String? initialSubtitle;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final message = controller.message ?? initialMessage;
        final subtitle = controller.subtitle ?? initialSubtitle;
        final total = controller.total;
        final current = controller.current;
        final double? progress = controller.progress;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedCoin(symbol: symbol, size: 56),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              CoinProgressBar(
                height: 8,
                width: 200,
                value: progress,
              ),
              if (total > 0) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  '$current / $total SMS scanned (${((progress ?? 0) * 100).toInt()}%)',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Executes [task] while displaying a non-dismissible [ProgressModal].
///
/// Guaranteed to dismiss cleanly upon task completion or error.
Future<T> withProgressModal<T>({
  required BuildContext context,
  required String message,
  String? subtitle,
  String symbol = '₹',
  required Future<T> Function(ProgressController progress) task,
}) async {
  if (!context.mounted) {
    final controller = ProgressController(message: message, subtitle: subtitle);
    return await task(controller);
  }

  final controller = ProgressController(message: message, subtitle: subtitle);
  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (BuildContext dialogContext) => PopScope(
      canPop: false,
      child: ProgressModal(
        controller: controller,
        initialMessage: message,
        initialSubtitle: subtitle,
        symbol: symbol,
      ),
    ),
  ).then((_) {
    dialogOpen = false;
  });

  try {
    return await task(controller);
  } finally {
    if (dialogOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
