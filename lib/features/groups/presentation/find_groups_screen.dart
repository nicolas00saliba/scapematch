import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';

class FindGroupsScreen extends ConsumerWidget {
  const FindGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cityId = ref.watch(selectedCityIdProvider);
    final almostFull = ref.watch(almostFullOnlyProvider);
    final groups = ref.watch(findGroupsViewModelProvider);
    final cityName = _cityName(ref, cityId);

    return AppScaffold(
      appBar: AppBar(title: const Text('Encontrar grupo')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: CitySelector(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 6),
                Text(
                  'Quase cheios: ainda dá para entrar e faltam 1 ou ${GroupRules.almostFullMaxOpenSeats} vagas.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _body(context, ref, cityId, cityName, almostFull, groups),
          ),
        ],
      ),
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

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    String? cityId,
    String? cityName,
    bool almostFull,
    AsyncValue<List<Group>> groups,
  ) {
    if (cityId == null) {
      return const EmptyView(
        title: 'Escolha uma cidade',
        message: 'A cidade é o filtro principal. Selecione uma acima para ver os grupos.',
        icon: Icons.location_city_outlined,
      );
    }

    return groups.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(message: 'Carregando grupos...'),
      error: (error, stackTrace) => ErrorView(
        message: 'Não foi possível carregar os grupos.',
        onRetry: () => ref.invalidate(findGroupsViewModelProvider),
      ),
      data: (items) {
        if (items.isEmpty) {
          final place = cityName ?? 'esta cidade';
          return EmptyView(
            title: almostFull ? 'Nenhum grupo quase cheio' : 'Nenhum grupo',
            message: almostFull
                ? 'Ninguém está a 1 ou ${GroupRules.almostFullMaxOpenSeats} vagas de fechar em $place. Veja todos os grupos.'
                : 'Ainda não há grupos de exemplo em $place.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: items.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const ExampleDataBanner();
            }
            final group = items[index - 1];
            return GroupCard(
              group: group,
              onTap: () => context.push('/groups/${group.id}'),
            );
          },
        );
      },
    );
  }
}
