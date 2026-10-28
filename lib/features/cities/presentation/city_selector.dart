import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';

/// Large city field, in the spirit of the origin field on a bus-ticket app.
///
/// [onSelected] lets the create-group screen reload houses after the change.
/// Other screens leave it null and only update the shared selection.
class CitySelector extends ConsumerWidget {
  const CitySelector({
    super.key,
    this.prominent = true,
    this.compact = false,
    this.onSelected,
  });

  final bool prominent;

  /// Uma linha baixa, para caber ao lado do título da Home.
  final bool compact;
  final ValueChanged<City>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(citiesProvider);
    final selectedId = ref.watch(selectedCityIdProvider);

    return cities.when(
      loading: () => _CityPlaceholder(
        title: 'Carregando cidades...',
        subtitle: 'Um momento.',
        compact: compact,
      ),
      error: (error, stackTrace) => _CityPlaceholder(
        title: 'Não foi possível carregar',
        subtitle: 'Toque para tentar de novo.',
        showProgress: false,
        compact: compact,
        onTap: () => ref.invalidate(citiesProvider),
      ),
      data: (list) {
        City? selected;
        for (final city in list) {
          if (city.id == selectedId) {
            selected = city;
            break;
          }
        }
        return _CityField(
          prominent: prominent,
          compact: compact,
          city: selected,
          onTap: () => _pick(context, ref, list, selectedId),
        );
      },
    );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    List<City> cities,
    String selectedId,
  ) async {
    final picked = await showModalBottomSheet<City>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Escolha a cidade',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final city in cities)
                      Semantics(
                        button: true,
                        identifier: 'city-option-${city.id}',
                        label: '${city.name}, ${city.stateName}',
                        excludeSemantics: true,
                        child: ListTile(
                          key: AppKeys.cityOption(city.id),
                          title: Text(city.name),
                          subtitle: Text(city.stateName),
                          trailing: city.id == selectedId
                              ? const Icon(Icons.check, color: AppColors.teal)
                              : null,
                          onTap: () => Navigator.pop(context, city),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final callback = onSelected;
    if (callback != null) {
      callback(picked);
    } else {
      ref.read(selectedCityIdProvider.notifier).select(picked.id);
    }
  }
}

class _CityField extends StatelessWidget {
  const _CityField({
    required this.prominent,
    required this.compact,
    required this.city,
    required this.onTap,
  });

  final bool prominent;
  final bool compact;
  final City? city;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = city != null;
    final label = selected
        ? 'Cidade selecionada: ${city!.name}, ${city!.stateName}. Toque para trocar.'
        : 'Cidade. Nenhuma cidade selecionada. Toque para escolher.';

    if (compact) {
      return Semantics(
        button: true,
        identifier: 'city-selector',
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? AppColors.teal : AppColors.line),
          ),
          child: InkWell(
            key: AppKeys.citySelector,
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.route, color: AppColors.teal, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      city?.name ?? 'Cidade',
                      maxLines: 1,
                      softWrap: false,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Icon(
                      Icons.expand_more,
                      color: AppColors.teal,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      identifier: 'city-selector',
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected ? AppColors.teal : AppColors.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          key: AppKeys.citySelector,
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 18,
              vertical: prominent ? 18 : 14,
            ),
            child: Row(
              children: [
                Container(
                  width: prominent ? 48 : 40,
                  height: prominent ? 48 : 40,
                  decoration: BoxDecoration(
                    color: AppColors.tealSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.route, color: AppColors.teal),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CIDADE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: AppColors.teal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        city?.name ?? 'Escolha uma cidade',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          color: selected ? AppColors.ink : AppColors.muted,
                        ),
                      ),
                      Text(
                        city == null
                            ? 'Toque para ver as cidades'
                            : '${city!.stateName} · ${city!.stateCode}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more, color: AppColors.teal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CityPlaceholder extends StatelessWidget {
  const _CityPlaceholder({
    required this.title,
    required this.subtitle,
    this.showProgress = true,
    this.compact = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool showProgress;
  final bool compact;
  final VoidCallback? onTap;

  Widget _placeholderRow(
    bool showProgress,
    String title,
    String subtitle,
    bool expanded,
  ) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: expanded ? TextOverflow.ellipsis : TextOverflow.visible,
          softWrap: false,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        if (expanded) Text(subtitle),
      ],
    );
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        showProgress
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.refresh, color: AppColors.teal),
        const SizedBox(width: 14),
        if (expanded) Expanded(child: text) else text,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      child: InkWell(
        key: AppKeys.citySelector,
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 18),
          child: compact
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _placeholderRow(showProgress, title, subtitle, false),
                )
              : _placeholderRow(showProgress, title, subtitle, true),
        ),
      ),
    );
  }
}
