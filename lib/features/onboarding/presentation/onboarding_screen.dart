import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/motion.dart';
import 'package:scapematch/core/ui/scape_photo.dart';
import 'package:scapematch/features/cities/presentation/city_selector.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/presentation/selected_game_type_controller.dart';
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
  });

  final String asset;
  final String title;
  final String body;
  final bool showPreferences;
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    asset: 'assets/images/onboarding/encontrar.jpg',
    title: OnboardingMessages.findTitle,
    body: OnboardingMessages.findBody,
  ),
  _OnboardingPage(
    asset: 'assets/images/onboarding/cidade.jpg',
    title: OnboardingMessages.nearTitle,
    body: OnboardingMessages.nearBody,
    showPreferences: true,
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

  Widget _dots() {
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
                color: index == _index
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ],
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
        ScapePhoto(asset: page.asset, semanticLabel: page.title),
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

class _Preferences extends ConsumerWidget {
  const _Preferences();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = ref.watch(selectedGameTypeIdProvider);
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in GameTypes.choices)
                  ChoiceChip(
                    key: AppKeys.gameTypeOption(choice.id),
                    label: Text(choice.shortLabel),
                    selected: selected == choice.id,
                    onSelected: (_) {
                      ref
                          .read(selectedGameTypeIdProvider.notifier)
                          .select(choice.id);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
