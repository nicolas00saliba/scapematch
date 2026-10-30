import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/option_sheet.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/create_group_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/providers/repositories.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key, this.prefilledRoomId});

  /// Sala já escolhida num cartão. A casa entra junto; o horário continua vazio.
  final String? prefilledRoomId;

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref
          .read(createGroupViewModelProvider.notifier)
          .loadInitial(roomId: widget.prefilledRoomId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createGroupViewModelProvider);
    final now = ref.watch(clockProvider).now();
    final theme = Theme.of(context);
    final capacityMessage = _capacityMessage(state);
    final started = state.slotHasStarted(now);
    final tooClose = state.slotTooClose(now);

    return AppScaffold(
      appBar: AppBar(title: const Text('Criar grupo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          Text(
            'Você entra como a primeira pessoa. As vagas abaixo são as pessoas que ainda faltam.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 16),
          CitySelector(
            onSelected: (city) {
              ref.read(createGroupViewModelProvider.notifier).selectCity(city);
            },
          ),
          if (state.loadingOptions) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          _SelectionField(
            fieldKey: AppKeys.selectionField('house'),
            label: 'Casa de escape',
            value: state.house == null
                ? null
                : '${state.house!.name} · ${state.house!.neighborhood}',
            hint: state.cityId == null
                ? 'Escolha a cidade primeiro'
                : 'Escolha a casa',
            enabled: state.cityId != null && state.houses.isNotEmpty,
            onTap: () => _pickHouse(state),
          ),
          const SizedBox(height: 12),
          _SelectionField(
            fieldKey: AppKeys.selectionField('room'),
            label: 'Sala',
            value: state.room == null
                ? null
                : '${state.room!.name} · até ${state.room!.capacity} pessoas',
            hint: state.houseId == null
                ? 'Escolha a casa primeiro'
                : 'Escolha a sala',
            enabled: state.houseId != null && state.rooms.isNotEmpty,
            onTap: () => _pickRoom(state),
          ),
          const SizedBox(height: 12),
          _SelectionField(
            fieldKey: AppKeys.selectionField('slot'),
            label: 'Horário',
            value: state.slot == null
                ? null
                : formatSession(state.slot!.startsAt),
            hint: state.roomId == null
                ? 'Escolha a sala primeiro'
                : 'Escolha o horário',
            enabled: state.roomId != null && state.slots.isNotEmpty,
            onTap: () => _pickSlot(state),
          ),
          const SizedBox(height: 20),
          Text(
            'Vagas além de você',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pessoas que ainda faltam, sem contar você.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: AppKeys.extraSpotsDecrement,
                onPressed: state.canDecrementExtraSpots
                    ? () => ref
                          .read(createGroupViewModelProvider.notifier)
                          .setExtraSpots(state.extraSpots - 1)
                    : null,
                icon: const Icon(Icons.remove),
                tooltip: 'Diminuir vagas',
              ),
              Text(
                '${state.extraSpots}',
                key: AppKeys.extraSpotsValue,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                key: AppKeys.extraSpotsIncrement,
                onPressed: state.canIncrementExtraSpots
                    ? () => ref
                          .read(createGroupViewModelProvider.notifier)
                          .setExtraSpots(state.extraSpots + 1)
                    : null,
                icon: const Icon(Icons.add),
                tooltip: 'Aumentar vagas',
              ),
            ],
          ),
          if (state.room != null) ...[
            const SizedBox(height: 8),
            Text(
              'O grupo ficaria com ${state.groupSize} pessoas. A sala ${state.room!.name} comporta ${state.room!.capacity}.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ],
          if (capacityMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              capacityMessage,
              key: AppKeys.capacityError,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          if (started) ...[
            const SizedBox(height: 8),
            Text(
              GroupMessages.alreadyStartedHint,
              key: AppKeys.createFailure,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          if (tooClose) ...[
            const SizedBox(height: 8),
            Text(
              GroupMessages.tooCloseToStart,
              key: AppKeys.createFailure,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
          if (state.failure != null) ...[
            const SizedBox(height: 8),
            Text(
              GroupMessages.createFailure(state.failure!),
              key: AppKeys.createFailure,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
      bottomBar: FilledButton(
        key: AppKeys.createSubmit,
        onPressed: state.canSubmitAt(now) ? _submit : null,
        child: state.submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Text('Criar grupo'),
      ),
    );
  }

  String? _capacityMessage(CreateGroupState state) {
    return switch (state.sizeValidation) {
      GroupSizeValidation.valid => null,
      GroupSizeValidation.belowMinimum =>
        'Informe pelo menos 1 vaga além de você.',
      GroupSizeValidation.belowRoomMinimum =>
        'Esta sala pede pelo menos ${state.room!.minimumPlayers} pessoas no grupo.',
      GroupSizeValidation.exceedsRoomCapacity =>
        'Você + ${state.extraSpots} vagas ultrapassa a capacidade da sala (${state.room!.capacity}).',
    };
  }

  Future<void> _pickHouse(CreateGroupState state) async {
    final house = await showOptionSheet<EscapeHouse>(
      context: context,
      title: 'Casa de escape',
      options: state.houses,
      idOf: (house) => house.id,
      labelOf: (house) => house.name,
      subtitleOf: (house) => house.neighborhood,
      emptyMessage: 'Não há casas de exemplo nesta cidade.',
    );
    if (house == null || !mounted) {
      return;
    }
    await ref.read(createGroupViewModelProvider.notifier).selectHouse(house.id);
  }

  Future<void> _pickRoom(CreateGroupState state) async {
    final room = await showOptionSheet<EscapeRoom>(
      context: context,
      title: 'Sala',
      options: state.rooms,
      idOf: (room) => room.id,
      labelOf: (room) => room.name,
      subtitleOf: (room) =>
          'Até ${room.capacity} pessoas · ${room.durationMinutes} min · ${room.difficulty.labelPt} · ${formatPrice(room.priceCents)}',
    );
    if (room == null || !mounted) {
      return;
    }
    await ref.read(createGroupViewModelProvider.notifier).selectRoom(room.id);
  }

  Future<void> _pickSlot(CreateGroupState state) async {
    final slot = await showOptionSheet<TimeSlot>(
      context: context,
      title: 'Horário',
      options: state.slots,
      idOf: (slot) => slot.id,
      labelOf: (slot) => formatSession(slot.startsAt),
    );
    if (slot == null || !mounted) {
      return;
    }
    ref.read(createGroupViewModelProvider.notifier).selectSlot(slot.id);
  }

  Future<void> _submit() async {
    final group = await ref
        .read(createGroupViewModelProvider.notifier)
        .submit();
    if (group == null || !mounted) {
      return;
    }
    // Substitui o formulário. O voltar do detalhe vai para a Home, e o
    // mesmo envio não fica disponível para criar o grupo de novo.
    context.pushReplacement('/groups/${group.id}');
  }
}

class _SelectionField extends StatelessWidget {
  const _SelectionField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.hint,
    required this.enabled,
    required this.onTap,
  });

  final Key fieldKey;
  final String label;
  final String? value;
  final String hint;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = value ?? hint;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label. $shown',
      excludeSemantics: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          key: fieldKey,
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shown,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: value == null
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.expand_more,
                  color: enabled ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
