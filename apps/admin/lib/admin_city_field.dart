import 'package:flutter/material.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/domain/city_search.dart';
import 'package:scapematch_admin/admin_errors.dart';

const adminStateCodes = <String>[
  'AC', 'AL', 'AM', 'AP', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MG', 'MS',
  'MT', 'PA', 'PB', 'PE', 'PI', 'PR', 'RJ', 'RN', 'RO', 'RR', 'RS', 'SC',
  'SE', 'SP', 'TO', //
];

/// Escolha de município por UF e busca, sobre o catálogo do servidor
/// (public.cities, os 5571 municípios do IBGE). O Admin nunca grava texto
/// livre: só devolve uma cidade que existe no catálogo.
class AdminCityField extends StatefulWidget {
  const AdminCityField({
    super.key,
    required this.selectedId,
    required this.selectedLabel,
    required this.initialState,
    required this.load,
    required this.onSelected,
    this.enabled = true,
  });

  /// Id da cidade escolhida agora (a da casa ou a que o Nícolas tocou).
  final String selectedId;

  /// "Arapoti · PR" para a cidade escolhida. Vazio mostra só o id.
  final String selectedLabel;

  /// UF que abre selecionada.
  final String initialState;
  final Future<List<City>> Function(String stateCode) load;
  final ValueChanged<City> onSelected;
  final bool enabled;

  @override
  State<AdminCityField> createState() => _AdminCityFieldState();
}

class _AdminCityFieldState extends State<AdminCityField> {
  static const _shown = 6;
  final _query = TextEditingController();
  late String _state;
  List<City> _all = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _state = adminStateCodes.contains(widget.initialState)
        ? widget.initialState
        : 'PR';
    _fetch();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final wanted = _state;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.load(wanted);
      if (!mounted || wanted != _state) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || wanted != _state) return;
      setState(() {
        _all = const [];
        _loading = false;
        _error = adminErrorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = searchCities(
      cities: _all,
      stateCode: _state,
      query: _query.text,
      limit: 200,
    );
    final visible = matches.take(_shown).toList(growable: false);
    final label = widget.selectedLabel.isEmpty
        ? widget.selectedId
        : widget.selectedLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cidade: $label',
          key: const Key('admin-cidade-escolhida'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                key: const Key('admin-cidade-uf'),
                initialValue: _state,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'UF'),
                items: [
                  for (final code in adminStateCodes)
                    DropdownMenuItem(value: code, child: Text(code)),
                ],
                onChanged: widget.enabled
                    ? (value) {
                        if (value == null || value == _state) return;
                        setState(() {
                          _state = value;
                          _all = const [];
                        });
                        _fetch();
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('admin-cidade-busca'),
                controller: _query,
                enabled: widget.enabled,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Buscar cidade',
                  helperText: 'Sem acento tudo bem. Ex.: arapoti',
                ),
              ),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const Key('admin-cidade-erro'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (!_loading && _error == null && _all.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Nenhuma cidade desta UF no catálogo do servidor ainda.',
              key: Key('admin-cidade-vazio'),
            ),
          ),
        for (final city in visible)
          ListTile(
            key: Key('admin-cidade-opcao-${city.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            enabled: widget.enabled,
            selected: city.id == widget.selectedId,
            title: Text('${city.name} · ${city.stateCode}'),
            trailing: city.id == widget.selectedId
                ? const Icon(Icons.check)
                : null,
            onTap: () => widget.onSelected(city),
          ),
        if (matches.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Mostrando ${visible.length} de ${matches.length}. Digite mais letras para achar a sua.',
            ),
          ),
        if (!_loading &&
            _all.isNotEmpty &&
            _query.text.trim().isNotEmpty &&
            matches.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Nenhuma cidade com esse nome nesta UF.',
              key: Key('admin-cidade-sem-resultado'),
            ),
          ),
      ],
    );
  }
}
