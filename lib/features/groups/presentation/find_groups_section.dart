import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';

/// Busca de grupo comprimida, no topo da Home.
class FindGroupsSection extends ConsumerStatefulWidget {
  const FindGroupsSection({super.key});

  @override
  ConsumerState<FindGroupsSection> createState() => _FindGroupsSectionState();
}

class _FindGroupsSectionState extends ConsumerState<FindGroupsSection> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cityId = ref.watch(selectedCityIdProvider);
    final almostFull = ref.watch(almostFullOnlyProvider);
    final query = ref.watch(groupSearchQueryProvider);
    final groups = ref.watch(filteredGroupsProvider);
    final cityName = _cityName(ref, cityId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Encontrar grupo',
          key: AppKeys.findGroup,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: AppKeys.groupSearch,
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            ref.read(groupSearchQueryProvider.notifier).setQuery(value);
          },
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar sala ou casa',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.line),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              identifier: 'almost-full-filter',
              button: true,
              label: almostFull
                  ? 'Filtro Quase cheios ativado'
                  : 'Filtro Quase cheios',
              child: FilterChip(
                key: AppKeys.almostFullFilter,
                label: const Text('Quase cheios'),
                selected: almostFull,
                onSelected: cityId == null
                    ? null
                    : (value) {
                        ref
                            .read(almostFullOnlyProvider.notifier)
                            .setEnabled(value);
                      },
              ),
            ),
            FilledButton.tonalIcon(
              key: AppKeys.createGroup,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => context.push('/groups/new'),
              icon: const Icon(Icons.add),
              label: const Text('Criar grupo'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Quase cheios: ainda dá para entrar e faltam 1 ou ${GroupRules.almostFullMaxOpenSeats} vagas.',
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 8),
        _list(context, ref, cityId, cityName, almostFull, query, groups),
      ],
    );
  }

  String? _cityName(WidgetRef ref, String? cityId) {
    if (cityId == null) {
      return null;
    }
    final cities = ref.watch(citiesProvider).value;
    if (cities == null) {
      return null;
    }
    for (final city in cities) {
      if (city.id == cityId) {
        return city.name;
      }
    }
    return null;
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    String? cityId,
    String? cityName,
    bool almostFull,
    String query,
    AsyncValue<List<Group>> groups,
  ) {
    if (cityId == null) {
      return const InlineNotice(
        message: 'Escolha a cidade acima para ver os grupos.',
      );
    }

    return groups.when(
      skipLoadingOnReload: true,
      loading: () =>
          const InlineNotice(message: 'Carregando grupos...', loading: true),
      error: (error, stackTrace) => InlineNotice(
        message: 'Não foi possível carregar os grupos.',
        actionKey: AppKeys.retry,
        onAction: () => ref.invalidate(findGroupsViewModelProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          return InlineNotice(
            message: _emptyMessage(cityName, almostFull, query),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              GroupCard(
                group: items[index],
                onTap: () => context.push('/groups/${items[index].id}'),
              ),
            ],
          ],
        );
      },
    );
  }

  String _emptyMessage(String? cityName, bool almostFull, String query) {
    final place = cityName ?? 'esta cidade';
    final text = query.trim();
    if (text.isNotEmpty) {
      return 'Nenhum grupo com “$text” em $place.';
    }
    if (almostFull) {
      return 'Ninguém está a 1 ou ${GroupRules.almostFullMaxOpenSeats} vagas de fechar em $place. Veja todos os grupos.';
    }
    return 'Ainda não há grupos de exemplo em $place.';
  }
}
