import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scapematch/core/imaging/room_framer.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';
import 'package:scapematch/features/catalog/domain/room_picture.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Foto ainda no formulário. A primeira da lista é a capa.
class RoomPhotoDraft {
  RoomPhotoDraft({
    required this.id,
    required this.source,
    required this.image,
    Map<RoomFrame, Uint8List>? ready,
  }) {
    if (ready != null) {
      expanded.addAll(ready);
    }
  }

  final String id;
  final Uint8List source;
  final ui.Image image;
  final placements = <RoomFrame, FramePlacement>{
    for (final frame in RoomFrame.values) frame: const FramePlacement(),
  };
  final expanded = <RoomFrame, Uint8List>{};
  final expandedImage = <RoomFrame, ui.Image>{};
  final simulated = <RoomFrame>{};

  void dispose() {
    image.dispose();
    for (final frame in expandedImage.values) {
      frame.dispose();
    }
  }

  void place(RoomFrame frame, FramePlacement placement) {
    placements[frame] = placement;
    expanded.remove(frame);
    expandedImage.remove(frame)?.dispose();
    simulated.remove(frame);
  }

  void rememberExpansion(
    RoomFrame frame,
    Uint8List bytes,
    ui.Image painted, {
    required bool simulatedFill,
  }) {
    expanded[frame] = bytes;
    expandedImage.remove(frame)?.dispose();
    expandedImage[frame] = painted;
    if (simulatedFill) {
      simulated.add(frame);
    } else {
      simulated.remove(frame);
    }
  }

  Future<RoomPicture> toPicture() async {
    final frames = <RoomFrame, Uint8List>{};
    for (final frame in RoomFrame.values) {
      final ready = expanded[frame];
      if (ready != null) {
        frames[frame] = ready;
        continue;
      }
      frames[frame] = await renderRoomFrame(
        source: image,
        frame: frame,
        placement: placements[frame] ?? const FramePlacement(),
      );
    }
    return RoomPicture(id: id, source: source, frames: frames);
  }
}

class RoomPhotoStudio extends StatelessWidget {
  const RoomPhotoStudio({
    super.key,
    required this.photos,
    required this.selected,
    required this.frame,
    required this.expanding,
    required this.onAdd,
    required this.onSelect,
    required this.onFrame,
    required this.onExpand,
    required this.onRemove,
    required this.onMove,
    required this.onCover,
    required this.onPlace,
    this.error,
  });

  final List<RoomPhotoDraft> photos;
  final int? selected;
  final RoomFrame frame;
  final bool expanding;
  final VoidCallback onAdd;
  final ValueChanged<int> onSelect;
  final ValueChanged<RoomFrame> onFrame;
  final VoidCallback onExpand;
  final ValueChanged<int> onRemove;
  final void Function(int index, int delta) onMove;
  final ValueChanged<int> onCover;
  final void Function(RoomFrame frame, FramePlacement placement) onPlace;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = selected == null ? null : photos[selected!];
    final placement = draft?.placements[frame] ?? const FramePlacement();
    final needsFill = draft == null
        ? false
        : frameNeedsExpansion(
            imageWidth: draft.image.width,
            imageHeight: draft.image.height,
            frame: frame,
          );
    final minScale = draft == null
        ? 1.0
        : containScale(
            imageWidth: draft.image.width,
            imageHeight: draft.image.height,
            frameWidth: frame.width,
            frameHeight: frame.height,
          ).clamp(0.35, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PartnerMessages.roomPhotos,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(PartnerMessages.roomPhotosBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: PartnerKeys.roomAddPhotos,
          onPressed: onAdd,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text(PartnerMessages.roomAddPhotos),
        ),
        if (photos.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final photo = photos[index];
                final chosen = index == selected;
                return InkWell(
                  onTap: () => onSelect(index),
                  child: Stack(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: chosen
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outlineVariant,
                            width: chosen ? 3 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.memory(photo.source, fit: BoxFit.cover),
                      ),
                      if (index == 0)
                        const Positioned(
                          left: 4,
                          top: 4,
                          child: _CoverMark(),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        if (draft != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: selected == 0 ? null : () => onCover(selected!),
                child: const Text(PartnerMessages.roomMakeCover),
              ),
              IconButton(
                tooltip: PartnerMessages.roomMoveBack,
                onPressed: selected == 0 ? null : () => onMove(selected!, -1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: PartnerMessages.roomMoveForward,
                onPressed: selected == photos.length - 1
                    ? null
                    : () => onMove(selected!, 1),
                icon: const Icon(Icons.chevron_right),
              ),
              IconButton(
                tooltip: PartnerMessages.roomRemovePhoto,
                onPressed: () => onRemove(selected!),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            PartnerMessages.roomFrames,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in RoomFrame.values)
                ChoiceChip(
                  key: PartnerKeys.roomFrame(item.name),
                  label: Text(
                    '${item.labelPt} ${item.width}×${item.height}',
                  ),
                  selected: item == frame,
                  onSelected: (_) => onFrame(item),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in RoomFrame.values) ...[
            Text(
              '${item.labelPt} · ${item.width}×${item.height}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            _FramePreview(
              draft: draft,
              frame: item,
              placement: draft.placements[item] ?? const FramePlacement(),
              expandedImage: draft.expandedImage[item],
              simulated: draft.simulated.contains(item),
              selected: item == frame,
              onTap: () => onFrame(item),
              onPlace: (next) => onPlace(item, next),
            ),
            const SizedBox(height: 8),
          ],
          Text(PartnerMessages.roomZoom),
          Slider(
            min: minScale.toDouble(),
            max: 2.5,
            value: placement.scale.clamp(minScale.toDouble(), 2.5),
            onChanged: (value) => onPlace(frame, placement.copyWith(scale: value)),
          ),
          if (needsFill)
            FilledButton.tonalIcon(
              key: PartnerKeys.roomExpand,
              onPressed: expanding ? null : onExpand,
              icon: expanding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: const Text(PartnerMessages.roomExpand),
            ),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }
}

class _CoverMark extends StatelessWidget {
  const _CoverMark();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          PartnerMessages.roomCover,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FramePreview extends StatelessWidget {
  const _FramePreview({
    required this.draft,
    required this.frame,
    required this.placement,
    required this.expandedImage,
    required this.simulated,
    required this.selected,
    required this.onTap,
    required this.onPlace,
  });

  final RoomPhotoDraft draft;
  final RoomFrame frame;
  final FramePlacement placement;
  final ui.Image? expandedImage;
  final bool simulated;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<FramePlacement> onPlace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        var width = constraints.maxWidth;
        var height = width / frame.aspect;
        const maxHeight = 120.0;
        if (height > maxHeight) {
          height = maxHeight;
          width = height * frame.aspect;
        }
        final rect = placedRect(
          imageWidth: draft.image.width,
          imageHeight: draft.image.height,
          frameWidth: frame.width,
          frameHeight: frame.height,
          placement: placement,
        );
        final pixel = width / frame.width;
        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: onTap,
            onPanUpdate: selected
                ? (details) {
                    final slackX = frame.width - rect.width;
                    final slackY = frame.height - rect.height;
                    var panX = placement.panX;
                    var panY = placement.panY;
                    if (slackX.abs() > 1) {
                      panX = (panX + details.delta.dx / (slackX.abs() / 2 * pixel))
                          .clamp(-1.0, 1.0);
                    }
                    if (slackY.abs() > 1) {
                      panY = (panY + details.delta.dy / (slackY.abs() / 2 * pixel))
                          .clamp(-1.0, 1.0);
                    }
                    onPlace(placement.copyWith(panX: panX, panY: panY));
                  }
                : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: ClipRRect(
                key: selected ? PartnerKeys.roomFramePreview : null,
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _PhotoPainter(
                          source: draft.image,
                          expanded: expandedImage,
                          rect: rect,
                          pixel: pixel,
                        ),
                      ),
                      if (simulated)
                        const Positioned(
                          left: 8,
                          top: 8,
                          child: _SimulationBadge(),
                        ),
                    ],
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

class _PhotoPainter extends CustomPainter {
  const _PhotoPainter({
    required this.source,
    required this.expanded,
    required this.rect,
    required this.pixel,
  });

  final ui.Image source;
  final ui.Image? expanded;
  final Rect rect;
  final double pixel;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = expanded;
    if (fill != null) {
      canvas.drawImageRect(
        fill,
        Rect.fromLTWH(0, 0, fill.width.toDouble(), fill.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1C1917));
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      Rect.fromLTWH(
        rect.left * pixel,
        rect.top * pixel,
        rect.width * pixel,
        rect.height * pixel,
      ),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant _PhotoPainter oldDelegate) {
    return oldDelegate.source != source ||
        oldDelegate.expanded != expanded ||
        oldDelegate.rect != rect ||
        oldDelegate.pixel != pixel;
  }
}

class _SimulationBadge extends StatelessWidget {
  const _SimulationBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: PartnerKeys.roomSimulated,
      decoration: BoxDecoration(
        color: const Color(0xE61C1917),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          PartnerMessages.roomSimulated,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
