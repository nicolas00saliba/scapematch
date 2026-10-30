import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/auth/presentation/auth_controller.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/features/groups/presentation/invite_sheet.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
import 'package:scapematch/providers/repositories.dart';

/// Busca de grupo comprimida, no topo da Home.
class FindGroupsSection extends ConsumerStatefulWidget {
  const FindGroupsSection({super.key});

  @override
  ConsumerState<FindGroupsSection> createState() => _FindGroupsSectionState();
}

const _searchPrefixSlot = 28.0;
const _searchEndPad = 4.0;

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
    final cityId = ref.watch(selectedCityIdProvider);
    final query = ref.watch(groupSearchQueryProvider);
    final gameTypeId = ref.watch(selectedGameTypeIdProvider);
    final groups = ref.watch(filteredGroupsProvider);
    final cityName = _cityName(ref, cityId);

    return Column(
      key: AppKeys.findGroup,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return _searchBar(context, constraints.maxWidth);
          },
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: AppKeys.groupResults,
          child: _list(context, ref, cityName, query, gameTypeId, groups),
        ),
      ],
    );
  }

  Widget _searchBar(BuildContext context, double width) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final hintStyle =
        theme.textTheme.bodyLarge ?? const TextStyle(fontSize: 16);
    final buttonStyle =
        theme.filledButtonTheme.style?.textStyle?.resolve({}) ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    final hintWidth = _textWidth('Buscar sala ou casa', hintStyle, scaler);
    final labelWidth = _textWidth('Criar grupo', buttonStyle, scaler);
    // O ícone de busca fica estreito de propósito: o hint precisa caber
    // inteiro numa tela de 390px, e o prefixo padrão come essa largura.
    const fieldChrome = _searchPrefixSlot + _searchEndPad + 4;
    const gap = 8.0;
    const labeledChrome = 18.0 + 8.0 + 24.0;
    const iconButton = 48.0;
    final withLabel =
        fieldChrome + hintWidth + gap + labeledChrome + labelWidth;
    final withIcon = fieldChrome + hintWidth + gap + iconButton;
    final field = _searchField();
    if (withLabel <= width) {
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: gap),
          _labeledCreate(context),
        ],
      );
    }
    if (withIcon <= width) {
      return Row(
        children: [
          Expanded(child: field),
          const SizedBox(width: gap),
          _iconCreate(context),
        ],
      );
    }
    final create = labelWidth + labeledChrome <= width
        ? _labeledCreate(context)
        : _iconCreate(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: create),
      ],
    );
  }

  Widget _searchField() {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      key: AppKeys.groupSearch,
      controller: _search,
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        ref.read(groupSearchQueryProvider.notifier).setQuery(value);
      },
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar sala ou casa',
        prefixIcon: const Icon(Icons.search, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: _searchPrefixSlot,
          minHeight: 40,
        ),
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.fromLTRB(0, 10, _searchEndPad, 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
    );
  }

  Widget _labeledCreate(BuildContext context) {
    return FilledButton.tonalIcon(
      key: AppKeys.createGroup,
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: () => context.push('/groups/new'),
      icon: const Icon(Icons.add, size: 18),
      label: const Text(
        'Criar grupo',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _iconCreate(BuildContext context) {
    return IconButton.filledTonal(
      key: AppKeys.createGroup,
      tooltip: 'Criar grupo',
      onPressed: () => context.push('/groups/new'),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        fixedSize: const Size(48, 48),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.add),
    );
  }

  double _textWidth(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  String? _cityName(WidgetRef ref, String cityId) {
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
    String? cityName,
    String query,
    String gameTypeId,
    AsyncValue<List<Group>> groups,
  ) {
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
        final viewer = ref.watch(authSessionProvider);
        ref.watch(communityTickProvider);
        final board = ref.watch(communityBoardProvider);
        final visible = [
          for (final group in items)
            if (viewer == null || !board.hiddenFromHome(viewer.id, group))
              group,
        ];
        if (visible.isEmpty) {
          return InlineNotice(
            message: _emptyMessage(cityName, query, gameTypeId),
          );
        }
        return _GroupWindow(
          groups: visible,
          now: ref.watch(clockProvider).now(),
          maxHeight: groupWindowHeightFor(visible.length),
          onOpen: (group) => context.push('/groups/${group.id}'),
          onInvite: (group) => showInviteSheet(context, group),
        );
      },
    );
  }

  String _emptyMessage(String? cityName, String query, String gameTypeId) {
    final place = cityName ?? 'esta cidade';
    final text = query.trim();
    final kind = gameTypeId == GameTypes.all
        ? ''
        : ' de ${GameTypes.labelOf(gameTypeId)}';
    if (text.isNotEmpty) {
      return 'Nenhum grupo$kind com “$text” em $place.';
    }
    return 'Ainda não há grupos de exemplo$kind em $place.';
  }
}

/// Teto da janela. Com poucos cartões ela encolhe até o conteúdo.
/// A barra só entra quando o conteúdo passa desse teto.
const groupWindowMaxHeight = 176.0;

/// Um cartão visível encolhe a janela. Dois ou mais usam o teto.
double groupWindowHeightFor(int visibleCount) {
  if (visibleCount <= 1) {
    return double.infinity;
  }
  return groupWindowMaxHeight;
}

/// Controller próprio da janela. A rolagem da página continua sendo a primária.
final class GroupWindowController extends ScrollController {}

class _GroupWindow extends StatefulWidget {
  const _GroupWindow({
    required this.groups,
    required this.now,
    required this.maxHeight,
    required this.onOpen,
    required this.onInvite,
  });

  final List<Group> groups;
  final DateTime now;
  final double maxHeight;
  final ValueChanged<Group> onOpen;
  final ValueChanged<Group> onInvite;

  @override
  State<_GroupWindow> createState() => _GroupWindowState();
}

class _GroupWindowState extends State<_GroupWindow> {
  final _scroll = GroupWindowController();
  var _overflows = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncOverflow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void didUpdateWidget(_GroupWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOverflow());
  }

  @override
  void dispose() {
    _scroll.removeListener(_syncOverflow);
    _scroll.dispose();
    super.dispose();
  }

  void _syncOverflow() {
    if (!mounted || !_scroll.hasClients) {
      return;
    }
    final overflows = _scroll.position.maxScrollExtent > 1;
    if (overflows == _overflows) {
      return;
    }
    setState(() => _overflows = overflows);
  }

  @override
  Widget build(BuildContext context) {
    return _CapHeight(
      key: AppKeys.groupWindow,
      maxHeight: widget.maxHeight,
      child: NotificationListener<OverscrollNotification>(
        onNotification: _chainOverscrollToPage,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: _overflows,
          child: SingleChildScrollView(
            controller: _scroll,
            primary: false,
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < widget.groups.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  GroupCard(
                    now: widget.now,
                    group: widget.groups[index],
                    onTap: () => widget.onOpen(widget.groups[index]),
                    onInvite: () => widget.onInvite(widget.groups[index]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// O arrasto que passa do fim (ou do começo) da janela segue na página.
  /// Sem isso, um toque que começa dentro da janela nunca move o resto da Home.
  bool _chainOverscrollToPage(OverscrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    // O scroll da página esconde o PrimaryScrollController dos filhos.
    // O contexto da janela está fora da rolagem interna, então o ancestral
    // vertical é a página.
    final page = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (page == null || !page.position.hasContentDimensions) {
      return false;
    }
    final position = page.position;
    final target = (position.pixels + notification.overscroll).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (target != position.pixels) {
      position.jumpTo(target);
    }
    return true;
  }
}

/// Fica da altura do conteúdo, até [maxHeight]. Acima disso, o filho rola.
class _CapHeight extends SingleChildRenderObjectWidget {
  const _CapHeight({super.key, required this.maxHeight, required super.child});

  final double maxHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCapHeight(maxHeight);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderCapHeight renderObject) {
    renderObject.maxHeight = maxHeight;
  }
}

class _RenderCapHeight extends RenderProxyBox {
  _RenderCapHeight(this._maxHeight);

  double _maxHeight;

  set maxHeight(double value) {
    if (_maxHeight == value) {
      return;
    }
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = Size(constraints.maxWidth, 0);
      return;
    }
    final width = constraints.maxWidth;
    child.layout(
      BoxConstraints(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );
    final natural = child.size.height;
    final height = math.min(natural, _maxHeight);
    if (natural > _maxHeight) {
      child.layout(BoxConstraints.tightFor(width: width, height: height));
    }
    size = Size(width, height);
  }
}
