import 'package:flutter/material.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/domain/city_search.dart';

/// Dropdown curto quando a lista é pequena; busca quando ela cresce.
class SearchableCityFormField extends StatelessWidget {
  const SearchableCityFormField({
    super.key,
    required this.cities,
    required this.cityId,
    required this.onChanged,
    this.enabled = true,
    this.labelText = 'Cidade',
    this.fieldKey,
  });

  final List<City> cities;
  final String? cityId;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String labelText;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    if (cities.length <= citySearchThreshold) {
      return DropdownButtonFormField<String>(
        key: fieldKey,
        initialValue: cities.any((city) => city.id == cityId) ? cityId : null,
        decoration: InputDecoration(
          labelText: labelText,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final city in cities)
            DropdownMenuItem(value: city.id, child: Text(city.name)),
        ],
        onChanged: enabled ? onChanged : null,
      );
    }
    return _LongCityFormField(
      fieldKey: fieldKey,
      cities: cities,
      cityId: cityId,
      onChanged: onChanged,
      enabled: enabled,
      labelText: labelText,
    );
  }
}

class _LongCityFormField extends StatefulWidget {
  const _LongCityFormField({
    required this.cities,
    required this.cityId,
    required this.onChanged,
    required this.enabled,
    required this.labelText,
    this.fieldKey,
  });

  final List<City> cities;
  final String? cityId;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final String labelText;
  final Key? fieldKey;

  @override
  State<_LongCityFormField> createState() => _LongCityFormFieldState();
}

class _LongCityFormFieldState extends State<_LongCityFormField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  String? _stateCode;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LongCityFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cityId != widget.cityId ||
        oldWidget.cities != widget.cities) {
      _sync();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _sync() {
    City? selected;
    for (final city in widget.cities) {
      if (city.id == widget.cityId) {
        selected = city;
        break;
      }
    }
    _stateCode = selected?.stateCode ?? _stateCode;
    final next = selected?.name ?? _text.text;
    if (selected != null && _text.text != next) {
      _text.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = <String>{
      for (final city in widget.cities) city.stateCode,
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: states.contains(_stateCode) ? _stateCode : null,
          decoration: const InputDecoration(
            labelText: 'Estado',
            border: OutlineInputBorder(),
          ),
          isExpanded: true,
          items: [
            for (final code in states)
              DropdownMenuItem(value: code, child: Text(code)),
          ],
          onChanged: widget.enabled
              ? (value) => setState(() => _stateCode = value)
              : null,
        ),
        const SizedBox(height: 12),
        RawAutocomplete<City>(
          textEditingController: _text,
          focusNode: _focus,
          displayStringForOption: (city) => city.name,
          optionsBuilder: (value) {
            return searchCities(
              cities: widget.cities,
              stateCode: _stateCode,
              query: value.text,
            );
          },
          onSelected: (city) {
            setState(() => _stateCode = city.stateCode);
            widget.onChanged(city.id);
            _focus.unfocus();
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              key: widget.fieldKey,
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              textCapitalization: TextCapitalization.words,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.labelText,
                hintText: 'Busque pelo nome da cidade',
                border: const OutlineInputBorder(),
                suffixIcon: const Icon(Icons.search),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList(growable: false);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 280,
                    minWidth: 280,
                  ),
                  child: list.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Nenhuma cidade encontrada.'),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final city = list[index];
                            return ListTile(
                              dense: true,
                              title: Text(city.name),
                              subtitle: Text(
                                '${city.stateName} · ${city.stateCode}',
                              ),
                              onTap: () => onSelected(city),
                            );
                          },
                        ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
