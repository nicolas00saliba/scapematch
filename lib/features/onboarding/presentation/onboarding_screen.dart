import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_logo.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/core/ui/window_class.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/cities/presentation/selected_city_controller.dart';
import 'package:scapematch/features/onboarding/presentation/city_landmarks.dart';
import 'package:scapematch/features/groups/presentation/game_type_chips.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_messages.dart';

/// Introdução da primeira abertura. Não pede conta.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.asset,
    required this.title,
    required this.body,
    this.showPreferences = false,
    this.landmark = false,
    this.alignment = Alignment.center,
  });

  final String asset;
  final String title;
  final String body;
  final bool showPreferences;

  /// A foto troca com a cidade escolhida.
  final bool landmark;

  /// Sobe um pouco o enquadramento quando a foto é alta, para os rostos
  /// não sumirem na faixa larga da web.
  final Alignment alignment;
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    asset: 'assets/images/onboarding/encontrar.jpg',
    title: OnboardingMessages.findTitle,
    body: OnboardingMessages.findBody,
    alignment: Alignment.center,
  ),
  _OnboardingPage(
    asset: 'assets/images/landmarks/curitiba.jpg',
    title: OnboardingMessages.nearTitle,
    body: OnboardingMessages.nearBody,
    showPreferences: true,
    landmark: true,
  ),
  _OnboardingPage(
    asset: 'assets/images/onboarding/convidar.jpg',
    title: OnboardingMessages.inviteTitle,
    body: OnboardingMessages.inviteBody,
  ),
  _OnboardingPage(
    asset: 'assets/images/onboarding/reservar.jpg',
    title: OnboardingMessages.payTitle,
    body: OnboardingMessages.payBody,
    // A maquininha fica no centro, um pouco acima. O y negativo segura
    // ela e as mãos quando a tela é mais larga que a foto.
    alignment: Alignment(0, -0.35),
  ),
];

const _pageTurn = Duration(milliseconds: 320);

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  var _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  bool get _last => _index == _pages.length - 1;

  Future<void> _back() async {
    if (_index == 0) {
      return;
    }
    await _page.previousPage(
      duration: scapeDuration(context, _pageTurn),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _next() async {
    if (_last) {
      await _finish();
      return;
    }
    await _page.nextPage(
      duration: scapeDuration(context, _pageTurn),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    if (!mounted) {
      return;
    }
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    if (isScapeDesktop(context)) {
      return _buildDesktop(context);
    }
    return _buildPhone(context);
  }

  /// O celular continua a foto em tela cheia, com o texto sobre o degradê.
  Widget _buildPhone(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _page,
            itemCount: _pages.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              return _PageBody(page: _pages[index]);
            },
          ),
          if (_index > 0) _introBack(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    TextButton(
                      key: AppKeys.onboardingSkip,
                      onPressed: _finish,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text(OnboardingMessages.skip),
                    ),
                    const Spacer(),
                    _dots(),
                    const Spacer(),
                    FilledButton(
                      key: _last
                          ? AppKeys.onboardingStart
                          : AppKeys.onboardingNext,
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(132, 48),
                      ),
                      child: Text(
                        _last
                            ? OnboardingMessages.start
                            : OnboardingMessages.next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _introBack() {
    return Positioned(
      left: 16,
      top: 8,
      child: SafeArea(bottom: false, child: _IntroBackButton(onPressed: _back)),
    );
  }

  Widget _dots({Color? active, Color? inactive}) {
    final on = active ?? Colors.white;
    final off = inactive ?? Colors.white.withValues(alpha: 0.45);
    return Semantics(
      label: 'Página ${_index + 1} de ${_pages.length}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < _pages.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            AnimatedContainer(
              duration: _pageTurn,
              curve: Curves.easeOutCubic,
              width: index == _index ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: index == _index ? on : off,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Site: foto à esquerda, no tamanho real, e o texto numa coluna à direita.
  Widget _buildDesktop(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final well = dark ? const Color(0xFF081110) : const Color(0xFF102422);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = (constraints.maxWidth * 0.46)
              .clamp(420.0, 560.0)
              .toDouble();
          final gutter = contentWidth >= 520 ? 48.0 : 32.0;
          return Stack(
            children: [
              PageView.builder(
                controller: _page,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  return Row(
                    children: [
                      Expanded(
                        child: ClipRect(
                          child: ColoredBox(
                            color: well,
                            child: _DesktopPhoto(page: _pages[index]),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: contentWidth,
                        child: _DesktopCopy(
                          page: _pages[index],
                          gutter: gutter,
                        ),
                      ),
                    ],
                  );
                },
              ),
              if (_index > 0) _introBack(),
              Positioned(
                right: 0,
                bottom: 0,
                width: contentWidth,
                child: _desktopFooter(context, gutter),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _desktopFooter(BuildContext context, double gutter) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final page = theme.scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            page.withValues(alpha: 0),
            page.withValues(alpha: 0.94),
            page,
          ],
          stops: const [0, 0.22, 1],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 24),
        child: Row(
          children: [
            TextButton(
              key: AppKeys.onboardingSkip,
              onPressed: _finish,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurface,
                minimumSize: const Size(64, 52),
              ),
              child: const Text(OnboardingMessages.skip),
            ),
            const Spacer(),
            _dots(
              active: scheme.primary,
              inactive: scheme.primary.withValues(alpha: 0.35),
            ),
            const Spacer(),
            FilledButton(
              key: _last ? AppKeys.onboardingStart : AppKeys.onboardingNext,
              onPressed: _next,
              style: FilledButton.styleFrom(minimumSize: const Size(148, 52)),
              child: Text(
                _last ? OnboardingMessages.start : OnboardingMessages.next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _PagePhoto(page: page),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x330E1716),
                Color(0x000E1716),
                Color(0xCC0E1716),
                Color(0xF20E1716),
              ],
              stops: [0, 0.28, 0.62, 1],
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 88),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 116).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScapeLogo(
                        height: constraints.maxWidth >= scapeWideLogoWidth
                            ? 52
                            : 40,
                        onDark: true,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        page.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        page.body,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.35,
                        ),
                      ),
                      if (page.showPreferences) ...[
                        const SizedBox(height: 18),
                        const _Preferences(),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PagePhoto extends ConsumerWidget {
  const _PagePhoto({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landmark = page.landmark
        ? landmarkFor(ref.watch(selectedCityIdProvider))
        : null;
    final asset = landmark?.asset ?? page.asset;
    final label = landmark == null ? page.title : landmark.name;
    final alignment = landmark?.alignment ?? page.alignment;
    return AnimatedSwitcher(
      duration: scapeDuration(context, const Duration(milliseconds: 420)),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        );
      },
      child: ScapePhoto(
        key: ValueKey(asset),
        asset: asset,
        semanticLabel: label,
        alignment: alignment,
      ),
    );
  }
}

class _Preferences extends StatelessWidget {
  const _Preferences();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
    );
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(OnboardingMessages.cityHeading, style: label),
            const SizedBox(height: 8),
            const CitySelector(prominent: false),
            const SizedBox(height: 16),
            Text(OnboardingMessages.gameTypeHeading, style: label),
            const SizedBox(height: 8),
            const GameTypeChips(),
          ],
        ),
      ),
    );
  }
}

/// Pixels do arquivo. [visibleHeight] corta só a faixa escura que o celular
/// usa debaixo do título. No site essa faixa não entra no painel, para a
/// foto não esticar além do que está nítido.
class _PhotoPixels {
  const _PhotoPixels(this.width, this.height, {double? visibleHeight})
    : visibleHeight = visibleHeight ?? height;

  final double width;
  final double height;
  final double visibleHeight;
}

const _photoPixels = <String, _PhotoPixels>{
  'assets/images/onboarding/encontrar.jpg': _PhotoPixels(1152, 864),
  'assets/images/onboarding/convidar.jpg': _PhotoPixels(1200, 1598),
  'assets/images/onboarding/reservar.jpg': _PhotoPixels(720, 1280),
  'assets/images/landmarks/curitiba.jpg': _PhotoPixels(
    824,
    1830,
    visibleHeight: 1040,
  ),
  'assets/images/landmarks/sao-paulo.jpg': _PhotoPixels(
    824,
    1830,
    visibleHeight: 1040,
  ),
  'assets/images/landmarks/rio.jpg': _PhotoPixels(
    824,
    1830,
    visibleHeight: 1080,
  ),
  'assets/images/landmarks/belo-horizonte.jpg': _PhotoPixels(
    824,
    1830,
    visibleHeight: 1280,
  ),
  'assets/images/landmarks/porto-alegre.jpg': _PhotoPixels(824, 1830),
};

/// Maior retângulo com a proporção da foto que cabe em [maxWidth] x [maxHeight]
/// sem passar da resolução original. [devicePixelRatio] 2 pede o dobro de
/// pixels, então o painel em CSS fica na metade.
Size fitOnboardingPhoto({
  required double maxWidth,
  required double maxHeight,
  required double pixelWidth,
  required double visibleHeight,
  required double devicePixelRatio,
}) {
  if (maxWidth <= 0 ||
      maxHeight <= 0 ||
      pixelWidth <= 0 ||
      visibleHeight <= 0) {
    return Size.zero;
  }
  final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
  final aspect = pixelWidth / visibleHeight;
  var width = math.min(maxWidth, pixelWidth / dpr);
  var height = width / aspect;
  final heightCap = math.min(maxHeight, visibleHeight / dpr);
  if (height > heightCap) {
    height = heightCap;
    width = height * aspect;
  }
  return Size(width, height);
}

/// Seta da introdução. Some na primeira página.
class _IntroBackButton extends StatelessWidget {
  const _IntroBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1A1A1A);
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x4D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        key: AppKeys.onboardingBack,
        tooltip: OnboardingMessages.back,
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.92),
          foregroundColor: ink,
          fixedSize: const Size(44, 44),
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
      ),
    );
  }
}

class _DesktopCopy extends StatelessWidget {
  const _DesktopCopy({required this.page, required this.gutter});

  final _OnboardingPage page;
  final double gutter;

  static const _footerClearance = 112.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(gutter, 40, gutter, _footerClearance),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight - 40 - _footerClearance,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ScapeLogo(height: 48),
                const SizedBox(height: 28),
                Text(
                  page.title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.12,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (page.showPreferences) ...[
                  const SizedBox(height: 24),
                  const _Preferences(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopPhoto extends ConsumerWidget {
  const _DesktopPhoto({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landmark = page.landmark
        ? landmarkFor(ref.watch(selectedCityIdProvider))
        : null;
    final asset = landmark?.asset ?? page.asset;
    final spec = _photoPixels[asset] ?? const _PhotoPixels(800, 1200);
    final label = landmark == null ? page.title : landmark.name;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 40.0;
        final size = fitOnboardingPhoto(
          maxWidth: math.max(0, constraints.maxWidth - padding * 2),
          maxHeight: math.max(0, constraints.maxHeight - padding * 2),
          pixelWidth: spec.width,
          visibleHeight: spec.visibleHeight,
          devicePixelRatio: dpr,
        );
        if (size.isEmpty) {
          return const SizedBox.shrink();
        }
        final crop = spec.visibleHeight < spec.height;
        return Padding(
          padding: const EdgeInsets.all(padding),
          child: Center(
            child: AnimatedSwitcher(
              duration: scapeDuration(
                context,
                const Duration(milliseconds: 420),
              ),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: _FramedPhoto(
                key: ValueKey(asset),
                asset: asset,
                label: label,
                width: size.width,
                height: size.height,
                alignment: crop ? Alignment.topCenter : Alignment.center,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FramedPhoto extends StatelessWidget {
  const _FramedPhoto({
    super.key,
    required this.asset,
    required this.label,
    required this.width,
    required this.height,
    required this.alignment,
  });

  final String asset;
  final String label;
  final double width;
  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: width,
          height: height,
          child: ScapePhoto(
            asset: asset,
            semanticLabel: label,
            alignment: alignment,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
