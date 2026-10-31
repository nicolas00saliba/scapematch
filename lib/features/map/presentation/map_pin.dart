import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/features/map/domain/house_pin.dart';
import 'package:scapematch/features/map/presentation/live_map_messages.dart';

/// Pino da casa. Grupo se formando pulsa, salvo com reduzir movimento.
class MapPinButton extends StatefulWidget {
  const MapPinButton({
    super.key,
    required this.pin,
    required this.selected,
    required this.onTap,
    this.markerId,
  });

  final HousePin pin;
  final bool selected;
  final VoidCallback onTap;

  /// Id do pino. Sem isto, usa a casa.
  final String? markerId;

  @override
  State<MapPinButton> createState() => _MapPinButtonState();
}

class _MapPinButtonState extends State<MapPinButton> {
  Timer? _timer;
  var _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final pulse = widget.pin.isForming && scapeAnimationsEnabled(context);
    if (pulse && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
        if (mounted) {
          setState(() => _generation += 1);
        }
      });
    } else if (!pulse) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void didUpdateWidget(MapPinButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pin.isForming != widget.pin.isForming) {
      didChangeDependencies();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pulse = widget.pin.isForming && scapeAnimationsEnabled(context);
    if (!pulse) {
      return _face(context, scale: 1, ring: 0);
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(_generation),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return _face(
          context,
          scale: pinPulseScale(t: t, enabled: true),
          ring: (1 - t) * 0.55,
        );
      },
    );
  }

  Widget _face(
    BuildContext context, {
    required double scale,
    required double ring,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pin = widget.pin;
    final label = pin.isForming
        ? '${pin.formingCount}'
        : pin.priceCents == null
        ? pin.house.name.characters.first
        : LiveMapMessages.pinPrice(pin.priceCents!);
    final border = pin.isForming ? scheme.tertiary : scheme.secondary;
    return RepaintBoundary(
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: LiveMapMessages.pinSemantics(
          house: pin.house.name,
          formingCount: pin.formingCount,
          priceCents: pin.priceCents,
        ),
        child: Transform.scale(
          scale: widget.selected ? scale * 1.08 : scale,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (ring > 0)
                Container(
                  width: 46 + (18 * ring),
                  height: 46 + (18 * ring),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.tertiary.withValues(alpha: ring),
                  ),
                ),
              Material(
                color: scheme.surface,
                elevation: widget.selected ? 4 : 2,
                shadowColor: scheme.shadow.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  key: AppKeys.mapPin(widget.markerId ?? pin.house.id),
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: border,
                        width: widget.selected ? 3 : 1.5,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (widget.selected)
                          const SizedBox(
                            key: AppKeys.mapPinSelected,
                            width: 0,
                            height: 0,
                          ),
                        Text(
                          label,
                          maxLines: 1,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapClusterButton extends StatelessWidget {
  const MapClusterButton({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Semantics(
        button: true,
        label: '$count casas',
        child: Material(
          color: scheme.primary,
          elevation: 3,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 46,
              height: 46,
              child: Center(
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
