import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/imaging/room_framer.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/room_frame.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch_parceiro/features/partner/data/photo_picker.dart';
import 'package:scapematch_parceiro/features/partner/data/scene_expansion.dart';
import 'package:scapematch_parceiro/features/partner/domain/partner_snapshot.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_palette.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_messages.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_money.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_room_photos.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

/// Abre o formulário de sala. Devolve verdadeiro quando a sala foi gravada.
Future<bool?> showPartnerRoomForm(
  BuildContext context, {
  required PartnerSnapshot snapshot,
  EscapeRoom? room,
}) {
  final wide = isScapeDesktop(context);
  final height = MediaQuery.sizeOf(context).height;
  if (wide) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          child: SizedBox(
            width: 480,
            height: height > 760 ? 640 : height * 0.86,
            child: PartnerRoomForm(snapshot: snapshot, room: room),
          ),
        );
      },
    );
  }
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final inset = MediaQuery.viewInsetsOf(context).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: height * 0.92,
          child: PartnerRoomForm(snapshot: snapshot, room: room),
        ),
      );
    },
  );
}

class PartnerRoomForm extends ConsumerStatefulWidget {
  const PartnerRoomForm({super.key, required this.snapshot, this.room});

  final PartnerSnapshot snapshot;
  final EscapeRoom? room;

  @override
  ConsumerState<PartnerRoomForm> createState() => _PartnerRoomFormState();
}

class _PartnerRoomFormState extends ConsumerState<PartnerRoomForm> {
  late final TextEditingController _name;
  late final TextEditingController _story;
  late final TextEditingController _duration;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _price;
  late Difficulty _difficulty;
  late RoomCategory _category;
  late int _accent;
  final List<RoomPhotoDraft> _photos = [];
  int? _selectedPhoto;
  var _frame = RoomFrame.card;
  String? _error;
  var _busy = false;
  var _expanding = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _name = TextEditingController(text: room?.name ?? '');
    _story = TextEditingController(text: room?.theme ?? '');
    _category = room?.category ?? RoomCategory.mystery;
    _duration = TextEditingController(text: '${room?.durationMinutes ?? 60}');
    _minimum = TextEditingController(text: '${room?.minimumPlayers ?? 2}');
    _maximum = TextEditingController(text: '${room?.capacity ?? 6}');
    _price = TextEditingController(text: reaisField(room?.priceCents ?? 10900));
    _difficulty = room?.difficulty ?? Difficulty.medium;
    final index = room == null
        ? widget.snapshot.rooms.length
        : widget.snapshot.rooms.indexWhere((item) => item.id == room.id);
    final paletteIndex = index < 0 ? widget.snapshot.rooms.length : index;
    _accent = room == null || room.accent == 0
        ? agendaPalette[paletteIndex % agendaPalette.length]
        : room.accent;
    _loadPictures();
  }

  Future<void> _loadPictures() async {
    final pictures = widget.room?.pictures ?? const [];
    for (final picture in pictures) {
      try {
        final image = await decodePhoto(picture.source);
        if (!mounted) {
          image.dispose();
          return;
        }
        _photos.add(
          RoomPhotoDraft(
            id: picture.id,
            source: picture.source,
            image: image,
            ready: picture.frames,
          ),
        );
      } on Object {
        // Foto antiga ilegível fica de fora. A casa pode enviar outra.
      }
    }
    if (mounted && _photos.isNotEmpty) {
      setState(() => _selectedPhoto = 0);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _story.dispose();
    _duration.dispose();
    _minimum.dispose();
    _maximum.dispose();
    _price.dispose();
    for (final photo in _photos) {
      photo.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final files = await ref.read(photoPickerProvider).pick();
    if (!mounted || files.isEmpty) {
      return;
    }
    for (var index = 0; index < files.length; index++) {
      try {
        final image = await decodePhoto(files[index]);
        _photos.add(
          RoomPhotoDraft(
            id: 'pic-${DateTime.now().microsecondsSinceEpoch}-$index',
            source: files[index],
            image: image,
          ),
        );
      } on Object {
        if (mounted) {
          setState(() => _error = PartnerMessages.roomPhotoUnread);
        }
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedPhoto ??= _photos.isEmpty ? null : 0;
    });
  }

  Future<void> _expand() async {
    final index = _selectedPhoto;
    if (index == null) {
      return;
    }
    final draft = _photos[index];
    setState(() {
      _expanding = true;
      _error = null;
    });
    try {
      final provider = ref.read(sceneExpansionProvider);
      final bytes = await provider.expand(
        source: draft.image,
        frame: _frame,
      );
      final painted = await decodePhoto(bytes);
      if (!mounted) {
        painted.dispose();
        return;
      }
      setState(() {
        draft.rememberExpansion(
          _frame,
          bytes,
          painted,
          simulatedFill: provider.isSimulation,
        );
      });
    } on SceneExpansionException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Não foi possível expandir o cenário.');
      }
    } finally {
      if (mounted) {
        setState(() => _expanding = false);
      }
    }
  }

  Future<void> _save() async {
    final price = parseReais(_price.text);
    if (price == null) {
      setState(() => _error = 'Informe o preço em reais.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final pictures = [
      for (final photo in _photos) await photo.toPicture(),
    ];
    if (!mounted) {
      return;
    }
    final error = ref.read(partnerRepositoryProvider).saveRoom(
      houseId: widget.snapshot.house.id,
      roomId: widget.room?.id,
      name: _name.text,
      theme: _story.text,
      category: _category,
      difficulty: _difficulty,
      durationMinutes: int.tryParse(_duration.text.trim()) ?? 0,
      minimumPlayers: int.tryParse(_minimum.text.trim()) ?? 0,
      capacity: int.tryParse(_maximum.text.trim()) ?? 0,
      priceCents: price,
      accent: _accent,
      pictures: pictures,
    );
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    ref.read(partnerRevisionProvider.notifier).bump();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.room == null;
    return SingleChildScrollView(
      key: PartnerKeys.roomForm,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Text(
          creating ? PartnerMessages.newRoom : PartnerMessages.editRoom,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          key: PartnerKeys.agendaRoomName,
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: PartnerMessages.roomName,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: PartnerKeys.roomStory,
          controller: _story,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: PartnerMessages.roomStory,
            hintText: PartnerMessages.roomStoryHint,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          PartnerMessages.roomCategory,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in RoomCategory.values)
              ChoiceChip(
                key: PartnerKeys.roomCategory(category.name),
                label: Text(roomCategoryLabel(category)),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Dificuldade',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final level in Difficulty.values)
              ChoiceChip(
                label: Text(level.labelPt),
                selected: _difficulty == level,
                onSelected: (_) => setState(() => _difficulty = level),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _duration,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: PartnerMessages.roomDuration,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          PartnerMessages.roomPlayers,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _minimum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: PartnerMessages.roomMinimum,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _maximum,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: PartnerMessages.roomMaximum,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: PartnerMessages.priceLabel,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          PartnerMessages.roomColor,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in agendaPalette)
              Tooltip(
                message: PartnerMessages.roomColor,
                child: InkWell(
                  onTap: () => setState(() => _accent = value),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _accent == value
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        RoomPhotoStudio(
          photos: _photos,
          selected: _selectedPhoto,
          frame: _frame,
          expanding: _expanding,
          error: null,
          onAdd: _addPhotos,
          onSelect: (index) => setState(() => _selectedPhoto = index),
          onFrame: (frame) => setState(() => _frame = frame),
          onExpand: _expand,
          onRemove: (index) {
            setState(() {
              _photos.removeAt(index).dispose();
              if (_photos.isEmpty) {
                _selectedPhoto = null;
              } else if (_selectedPhoto != null && _selectedPhoto! >= _photos.length) {
                _selectedPhoto = _photos.length - 1;
              }
            });
          },
          onMove: (index, delta) {
            setState(() {
              final next = index + delta;
              final photo = _photos.removeAt(index);
              _photos.insert(next, photo);
              _selectedPhoto = next;
            });
          },
          onCover: (index) {
            setState(() {
              final photo = _photos.removeAt(index);
              _photos.insert(0, photo);
              _selectedPhoto = 0;
            });
          },
          onPlace: (frame, placement) {
            final index = _selectedPhoto;
            if (index == null) {
              return;
            }
            setState(() => _photos[index].place(frame, placement));
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: PartnerKeys.agendaSaveRoom,
          onPressed: _busy ? null : _save,
          child: const Text(PartnerMessages.saveRoom),
        ),
        ],
      ),
    );
  }
}
