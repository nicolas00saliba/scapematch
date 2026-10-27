import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/app_keys.dart';

/// Opens a simple list and returns the chosen item.
///
/// Used for house, room, and time so every picker feels like the city one.
Future<T?> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T option) idOf,
  required String Function(T option) labelOf,
  String Function(T option)? subtitleOf,
  String? emptyMessage,
}) {
  return showModalBottomSheet<T>(
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
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Text(emptyMessage ?? 'Nenhuma opção disponível.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final option in options)
                      Semantics(
                        button: true,
                        identifier: 'option-${idOf(option)}',
                        label: subtitleOf == null
                            ? labelOf(option)
                            : '${labelOf(option)}. ${subtitleOf(option)}',
                        excludeSemantics: true,
                        child: ListTile(
                          key: AppKeys.option(idOf(option)),
                          title: Text(labelOf(option)),
                          subtitle: subtitleOf == null
                              ? null
                              : Text(subtitleOf(option)),
                          onTap: () => Navigator.pop(context, option),
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
}
