import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:scapematch_admin/admin_place.dart';
import 'package:scapematch_admin/admin_session.dart';
import 'package:scapematch_admin/admin_theme.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kAppMode == AppMode.demo) {
      return MaterialApp(
        title: 'EscapeMatch Admin',
        theme: adminTheme(),
        home: const Scaffold(
          body: Center(
            child: Text('O Admin não tem versão de demonstração.'),
          ),
        ),
      );
    }
    final session = ref.watch(adminSessionProvider);
    return MaterialApp(
      title: 'EscapeMatch Admin',
      debugShowCheckedModeBanner: false,
      theme: adminTheme(),
      home: session.phase == AdminPhase.ready
          ? const AdminShell()
          : const AdminLoginPage(),
    );
  }
}

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  static const destinations = <(AdminSection, String, IconData)>[
    (AdminSection.casas, 'Casas', Icons.storefront_outlined),
    (AdminSection.jogadores, 'Jogadores', Icons.people_outline),
    (AdminSection.regras, 'Regras', Icons.tune),
    (AdminSection.ganhos, 'Ganhos', Icons.payments_outlined),
    (AdminSection.destaques, 'Destaques', Icons.star_outline),
    (AdminSection.auditoria, 'Auditoria', Icons.history),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final place = ref.watch(adminPlaceProvider);
    final selected = destinations.indexWhere(
      (item) => item.$1 == place.section,
    );
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final session = ref.watch(adminSessionProvider);
    final page = switch (place.section) {
      AdminSection.casas => place.id == null
          ? const CasasPage()
          : CasaPage(id: place.id!),
      AdminSection.jogadores => place.id == null
          ? const JogadoresPage()
          : JogadorPage(id: place.id!),
      AdminSection.regras => const RegrasPage(),
      AdminSection.ganhos => const GanhosPage(),
      AdminSection.destaques => const DestaquesPage(),
      AdminSection.auditoria => const AuditoriaPage(),
    };

    void go(int next) =>
        ref.read(adminPlaceProvider.notifier).go(destinations[next].$1);

    final body = SafeArea(child: page);
    if (!wide) {
      return Scaffold(
        key: const Key('admin-shell'),
        appBar: AppBar(
          title: Text(destinations[selected].$2),
          actions: [
            IconButton(
              tooltip: 'Sair',
              onPressed: () => ref.read(adminSessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        drawer: Drawer(
          child: _RailList(
            selected: selected,
            onSelected: (next) {
              Navigator.pop(context);
              go(next);
            },
            name: session.name,
          ),
        ),
        body: body,
      );
    }
    return Scaffold(
      key: const Key('admin-shell'),
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.sizeOf(context).width >= 1200,
            selectedIndex: selected,
            onDestinationSelected: go,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: AdminMark(onDark: true),
            ),
            trailing: IconButton(
              tooltip: 'Sair',
              color: Colors.white,
              onPressed: () =>
                  ref.read(adminSessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
            ),
            destinations: [
              for (final item in destinations)
                NavigationRailDestination(
                  icon: Icon(item.$3),
                  label: Text(item.$2),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _RailList extends StatelessWidget {
  const _RailList({
    required this.selected,
    required this.onSelected,
    required this.name,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 24),
        const Center(child: AdminMark()),
        if (name != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(name!, textAlign: TextAlign.center),
          ),
        for (var i = 0; i < AdminShell.destinations.length; i++)
          ListTile(
            selected: i == selected,
            leading: Icon(AdminShell.destinations[i].$3),
            title: Text(AdminShell.destinations[i].$2),
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});

  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(adminSessionProvider);
    final busy = session.phase == AdminPhase.loading;
    return Scaffold(
      key: const Key('admin-login'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: AdminMark(height: 48)),
                  const SizedBox(height: 12),
                  Text(
                    'EscapeMatch Admin',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Só entra quem está em admins. A autorização continua no servidor.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const Key('admin-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('admin-password'),
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (session.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      session.error!,
                      key: const Key('admin-login-error'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('admin-enter'),
                    onPressed: busy ? null : _submit,
                    child: Text(busy ? 'Entrando…' : 'Entrar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    ref.read(adminSessionProvider.notifier).signIn(_email.text, _password.text);
  }
}
