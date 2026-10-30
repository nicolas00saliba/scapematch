import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
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

enum _Tone { primary, secondary, tertiary }

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
    this.showPreferences = false,
    this.tone = _Tone.primary,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showPreferences;
  final _Tone tone;
}

const _pages = <_OnboardingPage>[
  _OnboardingPage(
    icon: Icons.groups_outlined,
    title: OnboardingMessages.findTitle,
    body: OnboardingMessages.findBody,
  ),
  _OnboardingPage(
    icon: Icons.explore_outlined,
    title: OnboardingMessages.nearTitle,
    body: OnboardingMessages.nearBody,
    showPreferences: true,
  ),
  _OnboardingPage(
    icon: Icons.ios_share_outlined,
    title: OnboardingMessages.inviteTitle,
    body: OnboardingMessages.inviteBody,
    tone: _Tone.secondary,
  ),
  _OnboardingPage(
    icon: Icons.payments_outlined,
    title: OnboardingMessages.payTitle,
    body: OnboardingMessages.payBody,
    tone: _Tone.tertiary,
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
    await _page.nextPage(duration: _pageTurn, curve: Curves.easeOutCubic);
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppScaffold.maxWidth),
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: _pages.length,
                    onPageChanged: (index) => setState(() => _index = index),
                    itemBuilder: (context, index) {
                      return _PageBody(page: _pages[index]);
                    },
                  ),
                ),
                _dots(theme),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      TextButton(
                        key: AppKeys.onboardingSkip,
                        onPressed: _finish,
                        child: const Text(OnboardingMessages.skip),
                      ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Semantics(
      label: 'Página ${_index + 1} de ${_pages.length}',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < _pages.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              AnimatedContainer(
                duration: _pageTurn,
                curve: Curves.easeOutCubic,
                width: index == _index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == _index ? scheme.primary : scheme.outline,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
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
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 40).clamp(0, double.infinity),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _IconBadge(icon: page.icon, tone: page.tone),
                const SizedBox(height: 28),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                if (page.showPreferences) ...[
                  const SizedBox(height: 28),
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

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tone});

  final IconData icon;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground, border) = switch (tone) {
      _Tone.primary => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
      ),
      _Tone.secondary => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        scheme.secondaryContainer,
      ),
      _Tone.tertiary => (scheme.tertiary, scheme.onTertiary, scheme.onTertiary),
    };
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: border,
          width: tone == _Tone.tertiary ? 2 : 0,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 56, color: foreground),
    );
  }
}

class _Preferences extends ConsumerWidget {
  const _Preferences();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedGameTypeIdProvider);
    final label = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(OnboardingMessages.cityHeading, style: label),
        const SizedBox(height: 8),
        const CitySelector(prominent: false),
        const SizedBox(height: 20),
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
    );
  }
}
