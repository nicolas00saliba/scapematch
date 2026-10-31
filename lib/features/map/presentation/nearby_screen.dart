import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:scapematch/core/formatting/session_format.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/sharing/external_url.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/status_views.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/presentation/cities_provider.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/map/data/sample_live_presence.dart';
import 'package:scapematch/features/map/data/user_location.dart';
import 'package:scapematch/features/map/domain/nearby_group.dart';
import 'package:scapematch/features/map/presentation/group_pin_sheet.dart';
import 'package:scapematch/features/map/presentation/live_map_messages.dart';
import 'package:scapematch/features/map/presentation/map_pin.dart';
import 'package:scapematch/features/map/presentation/map_tiles.dart';
import 'package:scapematch/features/map/presentation/radius_circle.dart';
import 'package:scapematch/features/map/presentation/user_dot.dart';
import 'package:scapematch/providers/repositories.dart';

const nearbyRadiiKm = <int>[2, 5, 10, 20];

/// A partir daqui a lista vai para um painel à esquerda, no jeito de um mapa.
const nearbyWideWidth = 960.0;

const _panelWidth = 380.0;

final nearbyCatalogProvider =
    FutureProvider.autoDispose<
      ({List<EscapeHouse> houses, List<Group> groups})
    >((ref) async {
      final cities = await ref.watch(cityRepositoryProvider).listCities();
      final catalog = ref.watch(catalogRepositoryProvider);
      final groupsRepo = ref.watch(groupRepositoryProvider);
      final houses = <EscapeHouse>[];
      final groups = <Group>[];
      await Future.wait([
        for (final city in cities)
          () async {
            houses.addAll(await catalog.listHousesByCity(city.id));
            groups.addAll(await groupsRepo.listByCity(city.id));
          }(),
      ]);
      return (houses: houses, groups: groups);
    });

/// Aba Perto de você: o mapa, o ponto azul e os grupos no raio.
class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({super.key});

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  final _mapController = MapController();
  Timer? _seatTimer;
  var _radiusKm = 5;
  UserFix? _fix;
  GeoPoint? _centerOverride;
  String? _selectedGroupId;
  var _lockCamera = false;
  var _mapReady = false;
  var _tabVisible = false;
  var _wide = false;
  var _fitQueued = false;
  Size? _mapSize;
  String? _fitKey;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (!identical(_router, router)) {
      _router?.routerDelegate.removeListener(_onRoute);
      _router = router;
      router.routerDelegate.addListener(_onRoute);
    }
    _onRoute();
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRoute);
    _seatTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onRoute() {
    final path = GoRouter.of(context)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    final visible = path == '/perto';
    if (_tabVisible != visible) {
      _tabVisible = visible;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
    if (visible && _seatTimer == null) {
      _seatTimer = Timer.periodic(livePresenceInterval, (_) => _tick());
    } else if (!visible) {
      _seatTimer?.cancel();
      _seatTimer = null;
    }
  }

  Future<void> _loadLocation() async {
    final cityId = ref.read(selectedCityIdProvider);
    final fallback = cityCenters[cityId] ?? cityCenters['curitiba']!;
    final fix = await ref
        .read(userLocationSourceProvider)
        .current(fallback: fallback);
    if (!mounted) {
      return;
    }
    setState(() {
      _fix = fix;
      _centerOverride = null;
      _lockCamera = false;
      _fitKey = null;
    });
  }

  void _tick() {
    final cityId = ref.read(selectedCityIdProvider);
    final seat = ref.read(sampleLivePresenceProvider).takeSeat(cityId);
    if (!mounted || seat == null) {
      return;
    }
    ref.invalidate(nearbyCatalogProvider);
  }

  GeoPoint get _origin {
    return _centerOverride ?? _fix?.point ?? cityCenters['curitiba']!;
  }

  String _fitSignature(GeoPoint origin, Size size) {
    return '${origin.latitude.toStringAsFixed(5)},'
        '${origin.longitude.toStringAsFixed(5)},'
        '$_radiusKm,${size.width.round()}x${size.height.round()},$_wide';
  }

  /// Enquadra o círculo no mapa, não na janela inteira.
  ///
  /// O tamanho vale o do painel do mapa. No celular a gaveta come a base,
  /// então o círculo sobe. Na largura o mapa está livre e o círculo cabe
  /// com uma margem só.
  void _scheduleFit() {
    if (_fitQueued || _lockCamera || !_mapReady) {
      return;
    }
    final size = _mapSize;
    if (size == null || size.width < 48 || size.height < 48) {
      return;
    }
    final origin = _origin;
    final signature = _fitSignature(origin, size);
    if (_fitKey == signature) {
      return;
    }
    _fitQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitQueued = false;
      if (!mounted || _lockCamera || !_mapReady) {
        return;
      }
      final current = _mapSize;
      if (current == null || current.width < 48 || current.height < 48) {
        return;
      }
      final point = _origin;
      final next = _fitSignature(point, current);
      if (_fitKey == next) {
        return;
      }
      _fitKey = next;
      final dLat = _radiusKm / 111.0;
      final dLng =
          _radiusKm / (111.0 * math.cos(point.latitude * math.pi / 180));
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(
            LatLng(point.latitude - dLat, point.longitude - dLng),
            LatLng(point.latitude + dLat, point.longitude + dLng),
          ),
          padding: _fitPadding(current),
          maxZoom: 14,
        ),
      );
    });
  }

  EdgeInsets _fitPadding(Size size) {
    final desired = _wide
        ? const EdgeInsets.all(56)
        : EdgeInsets.fromLTRB(28, 120, 28, size.height * 0.40);
    if (desired.horizontal < size.width - 80 &&
        desired.vertical < size.height - 80) {
      return desired;
    }
    return const EdgeInsets.all(24);
  }

  Future<void> _openSheet(NearbyGroup item) async {
    setState(() {
      _selectedGroupId = item.group.id;
      _lockCamera = true;
    });
    _mapController.move(LatLng(item.point.latitude, item.point.longitude), 15);
    if (!mounted) {
      return;
    }
    final now = ref.read(clockProvider).now();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.42,
            maxChildSize: 0.96,
            snap: true,
            snapSizes: const [0.55, 0.96],
            builder: (context, scroll) {
              return GroupPinSheet(
                item: item,
                now: now,
                scrollController: scroll,
                onOpen: () {
                  Navigator.of(context).pop();
                  this.context.push('/groups/${item.group.id}');
                },
              );
            },
          ),
        );
      },
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _lockCamera = false;
      _fitKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(nearbyCatalogProvider);
    final cities = ref.watch(citiesProvider).asData?.value ?? const <City>[];
    final now = ref.watch(clockProvider).now();
    final fix = _fix;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: fix == null || catalog.isLoading
          ? const LoadingView(message: LiveMapMessages.loading)
          : catalog.hasError
          ? ErrorView(
              message: LiveMapMessages.loadError,
              onRetry: () => ref.invalidate(nearbyCatalogProvider),
            )
          : _ready(
              context,
              houses: catalog.requireValue.houses,
              groups: catalog.requireValue.groups,
              cities: cities,
              now: now,
            ),
    );
  }

  Widget _ready(
    BuildContext context, {
    required List<EscapeHouse> houses,
    required List<Group> groups,
    required List<City> cities,
    required DateTime now,
  }) {
    final origin = _origin;
    final nearby = formingWithinRadius(
      groups: groups,
      houses: houses,
      origin: origin,
      radiusKm: _radiusKm.toDouble(),
      now: now,
    );
    final cityName = _cityName(cities, ref.read(selectedCityIdProvider));
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= nearbyWideWidth;
        _wide = wide;
        final map = _mapPane(context, origin, nearby);
        if (!wide) {
          return Stack(
            children: [
              Positioned.fill(child: map),
              Positioned(
                left: 12,
                right: 12,
                top: 0,
                child: SafeArea(bottom: false, child: _top(context, cityName)),
              ),
              Positioned(
                right: 10,
                bottom: constraints.maxHeight * 0.34,
                child: const _OsmCredit(),
              ),
              _drawer(context, nearby, now),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _panelWidth,
              child: _panel(context, nearby, now, cityName),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: map),
                  const Positioned(right: 10, bottom: 12, child: _OsmCredit()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mapPane(
    BuildContext context,
    GeoPoint origin,
    List<NearbyGroup> nearby,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _mapSize = constraints.biggest;
        _scheduleFit();
        return RepaintBoundary(child: _map(context, origin, nearby));
      },
    );
  }

  Widget _map(BuildContext context, GeoPoint origin, List<NearbyGroup> nearby) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final center = LatLng(origin.latitude, origin.longitude);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _mapReady = true;
          _fitKey = null;
          _scheduleFit();
        },
      ),
      children: [
        ColorFiltered(
          colorFilter: dark ? _darkTiles : _warmTiles,
          child: TileLayer(
            urlTemplate: liveMapTileUrl(dark: dark),
            userAgentPackageName: 'dev.scapematch.app',
            tileProvider: ref.watch(mapTileProvider),
            tileDisplay: const TileDisplay.instantaneous(),
          ),
        ),
        Positioned.fill(
          child: RadiusCircleLayer(
            key: AppKeys.radiusCircle,
            center: center,
            radiusMeters: _radiusKm * 1000,
          ),
        ),
        MarkerLayer(
          markers: [
            for (final item in nearby)
              Marker(
                point: LatLng(item.point.latitude, item.point.longitude),
                width: 176,
                height: 176,
                alignment: Alignment.center,
                child: _ClearOfUser(
                  point: LatLng(item.point.latitude, item.point.longitude),
                  user: center,
                  child: RoomPhotoPin(
                    markerId: item.group.id,
                    roomName: item.group.roomName,
                    coverAsset: item.group.coverAsset,
                    filled: item.group.filledSpots,
                    total: item.group.totalSpots,
                    selected: _selectedGroupId == item.group.id,
                    onTap: () => _openSheet(item),
                  ),
                ),
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: center,
              width: 132,
              height: 132,
              alignment: Alignment.center,
              child: UserDot(key: AppKeys.userDot, animate: _tabVisible),
            ),
          ],
        ),
      ],
    );
  }

  Widget _top(BuildContext context, String cityName) {
    final scheme = Theme.of(context).colorScheme;
    final fix = _fix!;
    final notice = switch (fix.read) {
      LocationRead.device => null,
      LocationRead.denied => LiveMapMessages.locationDenied(cityName),
      LocationRead.unavailable => LiveMapMessages.locationUnavailable(cityName),
    };
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      elevation: 3,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final km in nearbyRadiiKm)
                  ChoiceChip(
                    key: AppKeys.radiusChip(km),
                    label: Text(LiveMapMessages.radiusLabel(km)),
                    selected: _radiusKm == km,
                    onSelected: (_) {
                      setState(() {
                        _radiusKm = km;
                        _lockCamera = false;
                        _fitKey = null;
                      });
                    },
                  ),
              ],
            ),
            if (notice != null) ...[
              const SizedBox(height: 8),
              Text(notice, key: AppKeys.nearNotice),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: AppKeys.nearRetry,
                  onPressed: _loadLocation,
                  child: const Text(LiveMapMessages.tryAgain),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context,
    List<NearbyGroup> nearby,
    DateTime now,
    String cityName,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: AppKeys.mapSheet,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LiveMapMessages.nearTab,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  _top(context, cityName),
                  const SizedBox(height: 12),
                  _heading(context, nearby, now),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [for (final item in nearby) _row(context, item, now)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(
    BuildContext context,
    List<NearbyGroup> nearby,
    DateTime now,
  ) {
    final cities = ref.watch(citiesProvider).asData?.value ?? const <City>[];
    final nearestId = nearestCityWithFormingGroups(
      origin: _origin,
      centers: cityCenters,
      groups: ref.watch(nearbyCatalogProvider).asData?.value.groups ?? const [],
      now: now,
    );
    final nearest = _cityName(cities, nearestId ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          nearby.isEmpty
              ? LiveMapMessages.emptyRadius
              : '${nearby.length} ${nearby.length == 1 ? 'grupo se formando' : 'grupos se formando'}',
          key: nearby.isEmpty ? AppKeys.nearEmpty : null,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (nearby.isEmpty && nearestId != null) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: AppKeys.nearEmptyCity,
            onPressed: () => _jumpToCity(nearestId),
            child: Text(LiveMapMessages.seeCity(nearest)),
          ),
        ],
      ],
    );
  }

  Widget _drawer(BuildContext context, List<NearbyGroup> nearby, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.18,
      maxChildSize: 0.7,
      builder: (context, scroll) {
        return Material(
          key: AppKeys.mapSheet,
          color: scheme.surface,
          elevation: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
              const SizedBox(height: 10),
              _heading(context, nearby, now),
              for (final item in nearby) _row(context, item, now),
            ],
          ),
        );
      },
    );
  }

  void _jumpToCity(String cityId) {
    final center = cityCenters[cityId];
    if (center == null) {
      return;
    }
    ref.read(selectedCityIdProvider.notifier).select(cityId);
    setState(() {
      _centerOverride = center;
      _lockCamera = false;
      _fitKey = null;
      _selectedGroupId = null;
    });
  }

  Widget _row(BuildContext context, NearbyGroup item, DateTime now) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedGroupId == item.group.id;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: AppKeys.nearbyCard(item.group.id),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openSheet(item),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                if (selected)
                  const SizedBox(
                    key: AppKeys.mapPinSelected,
                    width: 0,
                    height: 0,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.group.roomName,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${item.group.houseName} · ${formatSession(item.group.startsAt)}',
                      ),
                    ],
                  ),
                ),
                Text(
                  formatDistanceKm(item.distanceKm),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _cityName(List<City> cities, String cityId) {
    for (final city in cities) {
      if (city.id == cityId) {
        return city.name;
      }
    }
    return '';
  }
}

/// Afasta o desenho do pino quando ele cairia em cima do ponto azul.
///
/// O lugar da casa não muda. Só o círculo anda na tela, o bastante para
/// o ponto e a foto aparecerem juntos. Com o zoom da ficha, 250 m já
/// separam os dois e o pino volta para o ponto.
class _ClearOfUser extends StatelessWidget {
  const _ClearOfUser({
    required this.point,
    required this.user,
    required this.child,
  });

  final LatLng point;
  final LatLng user;
  final Widget child;

  static const _gap = 46.0;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final delta =
        camera.latLngToScreenOffset(point) - camera.latLngToScreenOffset(user);
    final distance = delta.distance;
    if (!distance.isFinite || distance >= _gap) {
      return child;
    }
    final nudge = distance < 1
        ? const Offset(0, -_gap)
        : delta / distance * (_gap - distance);
    return Transform.translate(offset: nudge, child: child);
  }
}

class _OsmCredit extends StatelessWidget {
  const _OsmCredit();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: AppKeys.mapAttribution,
      color: scheme.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => openExternalUrl(Uri.parse(LiveMapMessages.osmCopyright)),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            LiveMapMessages.attribution,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

const _warmTiles = ColorFilter.matrix(<double>[
  1.02,
  0,
  0,
  0,
  6,
  0,
  1,
  0,
  0,
  2,
  0,
  0,
  0.96,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
]);

const _darkTiles = ColorFilter.matrix(<double>[
  -0.85,
  0,
  0,
  0,
  230,
  0,
  -0.8,
  0,
  0,
  220,
  0,
  0,
  -0.7,
  0,
  210,
  0,
  0,
  0,
  1,
  0,
]);
