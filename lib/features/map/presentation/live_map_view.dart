import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_listing.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/presentation/find_groups_view_model.dart';
import 'package:scapematch/features/groups/presentation/game_type_selector.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
import 'package:scapematch/features/groups/presentation/group_card.dart';
import 'package:scapematch/features/map/data/sample_live_presence.dart';
import 'package:scapematch/features/map/domain/house_pin.dart';
import 'package:scapematch/features/map/domain/live_seat.dart';
import 'package:scapematch/features/map/domain/pin_cluster.dart';
import 'package:scapematch/features/map/presentation/home_surface.dart';
import 'package:scapematch/features/map/presentation/live_map_messages.dart';
import 'package:scapematch/features/map/presentation/map_pin.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/providers/repositories.dart';

final _cityHousesProvider = FutureProvider.autoDispose<List<EscapeHouse>>((
  ref,
) {
  final cityId = ref.watch(selectedCityIdProvider);
  return ref.watch(catalogRepositoryProvider).listHousesByCity(cityId);
});

final _cityRoomsProvider = FutureProvider.autoDispose<List<RoomListing>>((ref) {
  final cityId = ref.watch(selectedCityIdProvider);
  return ref.watch(catalogRepositoryProvider).listRoomsByCity(cityId);
});

/// Mapa da cidade com gaveta de grupos, no lugar da lista.
class LiveMapView extends ConsumerStatefulWidget {
  const LiveMapView({super.key});

  @override
  ConsumerState<LiveMapView> createState() => _LiveMapViewState();
}

class _LiveMapViewState extends ConsumerState<LiveMapView> {
  final _mapController = MapController();
  final _cardKeys = <String, GlobalKey>{};
  Timer? _seatTimer;
  LiveSeat? _lastSeat;
  String? _selectedHouseId;
  var _zoom = 13.0;
  List<HousePin> _pins = const [];

  @override
  void initState() {
    super.initState();
    _seatTimer = Timer.periodic(livePresenceInterval, (_) => _tick());
  }

  @override
  void dispose() {
    _seatTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _tick() {
    final cityId = ref.read(selectedCityIdProvider);
    final seat = ref.read(sampleLivePresenceProvider).takeSeat(cityId);
    if (!mounted) {
      return;
    }
    if (seat != null) {
      setState(() => _lastSeat = seat);
    }
    ref.invalidate(findGroupsViewModelProvider);
  }

  void _selectHouse(String houseId) {
    setState(() => _selectedHouseId = houseId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final target = _cardKeys[houseId]?.currentContext;
      if (target == null) {
        return;
      }
      Scrollable.ensureVisible(
        target,
        alignment: 0.04,
        duration: scapeDuration(target, const Duration(milliseconds: 280)),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _rememberZoom(double zoom) {
    if ((_zoom - zoom).abs() < 0.05) {
      return;
    }
    final before = _clusterIds(_zoom);
    _zoom = zoom;
    if (before != _clusterIds(zoom)) {
      setState(() {});
    }
  }

  String _clusterIds(double zoom) {
    return clusterHousePins(
      _pins,
      zoom: zoom,
    ).map((cluster) => cluster.id).join('|');
  }

  void _openCluster(PinCluster cluster) {
    final zoom = (_zoom + 2).clamp(3, 18).toDouble();
    _mapController.move(LatLng(cluster.latitude, cluster.longitude), zoom);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedCityIdProvider, (previous, next) {
      if (previous != next) {
        setState(() => _lastSeat = null);
      }
    });

    final groups = ref.watch(filteredGroupsProvider);
    final houses = ref.watch(_cityHousesProvider);
    final rooms = ref.watch(_cityRoomsProvider);
    final waiting = groups.isLoading || houses.isLoading || rooms.isLoading;
    final failed = groups.hasError || houses.hasError || rooms.hasError;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: waiting
          ? const LoadingView(message: LiveMapMessages.loading)
          : failed
          ? ErrorView(
              message: LiveMapMessages.loadError,
              onRetry: () {
                ref.invalidate(findGroupsViewModelProvider);
                ref.invalidate(_cityHousesProvider);
                ref.invalidate(_cityRoomsProvider);
              },
            )
          : _ready(
              context,
              groups: groups.requireValue,
              houses: houses.requireValue,
              rooms: [for (final listing in rooms.requireValue) listing.room],
            ),
    );
  }

  Widget _ready(
    BuildContext context, {
    required List<Group> groups,
    required List<EscapeHouse> houses,
    required List<EscapeRoom> rooms,
  }) {
    final now = ref.watch(clockProvider).now();
    final gameTypeId = ref.watch(selectedGameTypeIdProvider);
    final visibleRooms = [
      for (final room in rooms)
        if (gameTypeId == GameTypes.all || room.gameType == gameTypeId) room,
    ];
    final pins = buildHousePins(
      houses: houses,
      rooms: visibleRooms,
      groups: groups,
      now: now,
    );
    _pins = pins;
    final cityName = _cityName(ref);
    final forming = formingGroupCount(groups, now);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        final topPad = narrow ? 200.0 : 128.0;
        final bottomPad = constraints.maxHeight * 0.52;
        return Stack(
          children: [
            Positioned.fill(
              child: _map(
                context,
                pins: pins,
                topPad: topPad,
                bottomPad: bottomPad,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: _topBar(
                  context,
                  narrow: narrow,
                  cityName: cityName,
                  forming: forming,
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: bottomPad + 8,
              child: const _MapAttribution(),
            ),
            _sheet(context, groups, now),
          ],
        );
      },
    );
  }

  Widget _map(
    BuildContext context, {
    required List<HousePin> pins,
    required double topPad,
    required double bottomPad,
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final points = [
      for (final pin in pins) LatLng(pin.latitude, pin.longitude),
    ];
    final clusters = clusterHousePins(pins, zoom: _zoom);
    return RepaintBoundary(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: points.isEmpty
              ? const LatLng(-25.4296, -49.2712)
              : points.first,
          initialZoom: 13,
          initialCameraFit: points.isEmpty
              ? null
              : CameraFit.coordinates(
                  coordinates: points,
                  padding: EdgeInsets.fromLTRB(40, topPad, 40, bottomPad),
                  maxZoom: 15,
                  minZoom: 11,
                ),
          minZoom: 3,
          maxZoom: 18,
          backgroundColor: theme.scaffoldBackgroundColor,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _rememberZoom(_mapController.camera.zoom);
              }
            });
          },
          onMapEvent: (event) => _rememberZoom(event.camera.zoom),
        ),
        children: [
          ColorFiltered(
            colorFilter: dark ? _darkTiles : _warmTiles,
            child: TileLayer(
              urlTemplate: liveMapTileUrl(dark: dark),
              userAgentPackageName: 'dev.scapematch.app',
              tileProvider: ref.watch(mapTileProvider),
              tileDisplay: const TileDisplay.instantaneous(),
              evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
            ),
          ),
          MarkerLayer(
            markers: [
              for (final cluster in clusters)
                if (cluster.isCluster)
                  Marker(
                    key: AppKeys.mapCluster(cluster.id),
                    point: LatLng(cluster.latitude, cluster.longitude),
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    rotate: true,
                    child: MapClusterButton(
                      count: cluster.pins.length,
                      onTap: () => _openCluster(cluster),
                    ),
                  )
                else
                  Marker(
                    point: LatLng(
                      cluster.pins.single.latitude,
                      cluster.pins.single.longitude,
                    ),
                    width: 112,
                    height: 56,
                    alignment: Alignment.center,
                    rotate: true,
                    child: MapPinButton(
                      pin: cluster.pins.single,
                      selected:
                          _selectedHouseId == cluster.pins.single.house.id,
                      onTap: () => _selectHouse(cluster.pins.single.house.id),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topBar(
    BuildContext context, {
    required bool narrow,
    required String cityName,
    required int forming,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final controls = narrow
        ? const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HomeSurfaceToggle(),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: CitySelector(compact: true)),
                  SizedBox(width: 8),
                  GameTypeSelector(),
                ],
              ),
            ],
          )
        : const Row(
            children: [
              HomeSurfaceToggle(),
              SizedBox(width: 8),
              Expanded(child: CitySelector(compact: true)),
              SizedBox(width: 8),
              GameTypeSelector(),
            ],
          );
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            controls,
            const SizedBox(height: 8),
            _LiveStrip(
              label: LiveMapMessages.forming(forming, cityName),
              count: forming,
              cityName: cityName,
              seat: _lastSeat,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheet(BuildContext context, List<Group> groups, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final seen = <String>{};
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.86,
      snap: true,
      snapSizes: const [0.2, 0.4, 0.86],
      builder: (context, scrollController) {
        return Material(
          key: AppKeys.mapSheet,
          color: scheme.surface,
          elevation: 10,
          shadowColor: scheme.shadow.withValues(alpha: 0.24),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ExampleDataBanner(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text(
                  LiveMapMessages.sheetTitle,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(LiveMapMessages.emptySheet),
                )
              else
                for (final group in groups)
                  _card(context, group, now, anchor: seen.add(group.houseId)),
            ],
          ),
        );
      },
    );
  }

  Widget _card(
    BuildContext context,
    Group group,
    DateTime now, {
    required bool anchor,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedHouseId == group.houseId;
    return Padding(
      key: anchor ? _keyFor(group.houseId) : null,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: selected ? scheme.secondary : Colors.transparent,
            width: 3,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Stack(
            children: [
              GroupCard(
                group: group,
                now: now,
                onTap: () => context.push('/groups/${group.id}'),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: scheme.surface.withValues(alpha: 0.94),
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: AppKeys.mapFocus(group.id),
                    tooltip: LiveMapMessages.showOnMap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    onPressed: () => _selectHouse(group.houseId),
                    icon: Icon(
                      Icons.location_on_outlined,
                      color: scheme.secondary,
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

  GlobalKey _keyFor(String houseId) {
    return _cardKeys.putIfAbsent(houseId, GlobalKey.new);
  }

  String _cityName(WidgetRef ref) {
    final cityId = ref.watch(selectedCityIdProvider);
    final cities = ref.watch(citiesProvider).asData?.value;
    if (cities == null) {
      return '';
    }
    for (final city in cities) {
      if (city.id == cityId) {
        return city.name;
      }
    }
    return '';
  }
}

class _LiveStrip extends StatelessWidget {
  const _LiveStrip({
    required this.label,
    required this.count,
    required this.cityName,
    required this.seat,
  });

  final String label;
  final int count;
  final String cityName;
  final LiveSeat? seat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
      height: 1.25,
    );
    final seatLine = seat;
    return Semantics(
      key: AppKeys.liveStrip,
      container: true,
      excludeSemantics: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (count == 0)
            Text(label, style: style)
          else
            Text.rich(
              TextSpan(
                style: style,
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: AnimatedCount(
                      value: count,
                      style: style?.copyWith(color: scheme.secondary),
                    ),
                  ),
                  TextSpan(text: _rest(count, cityName)),
                ],
              ),
            ),
          if (seatLine != null) ...[
            const SizedBox(height: 2),
            Text(
              key: AppKeys.liveJoin,
              LiveMapMessages.joined(seatLine.displayName, seatLine.roomName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _rest(int count, String city) {
    if (count == 1) {
      return ' grupo se formando agora em $city';
    }
    return ' grupos se formando agora em $city';
  }
}

class _MapAttribution extends StatefulWidget {
  const _MapAttribution();

  @override
  State<_MapAttribution> createState() => _MapAttributionState();
}

class _MapAttributionState extends State<_MapAttribution> {
  late final TapGestureRecognizer _osm;

  @override
  void initState() {
    super.initState();
    _osm = TapGestureRecognizer()
      ..onTap = () => openExternalUrl(Uri.parse(LiveMapMessages.osmCopyright));
  }

  @override
  void dispose() {
    _osm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700);
    return Material(
      key: AppKeys.mapAttribution,
      color: scheme.surface.withValues(alpha: 0.92),
      elevation: 1,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text.rich(
          TextSpan(
            text: LiveMapMessages.attribution,
            style: style,
            recognizer: _osm,
          ),
        ),
      ),
    );
  }
}

const _warmTiles = ColorFilter.matrix(<double>[
  1.04,
  0.02,
  0,
  0,
  8,
  0,
  1.01,
  0,
  0,
  4,
  0,
  0,
  0.94,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

const _darkTiles = ColorFilter.matrix(<double>[
  0.82,
  0,
  0,
  0,
  0,
  0.05,
  0.92,
  0,
  0,
  6,
  0.05,
  0.06,
  0.9,
  0,
  8,
  0,
  0,
  0,
  1,
  0,
]);
