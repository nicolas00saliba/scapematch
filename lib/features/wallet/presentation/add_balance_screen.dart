import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/formatting/money_format.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/core/ui/example_data_banner.dart';

/// Valores sugeridos, em centavos. Nada disso é cobrado.
const topUpSuggestions = <int>[2000, 5000, 10000];

/// Preparativos da recarga. O confirmar fica desligado.
class AddBalanceScreen extends StatefulWidget {
  const AddBalanceScreen({super.key});

  @override
  State<AddBalanceScreen> createState() => _AddBalanceScreenState();
}

class _AddBalanceScreenState extends State<AddBalanceScreen> {
  int? _cents;
  bool _other = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppScaffold(
      appBar: AppBar(title: const Text('Adicionar saldo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const ExampleDataBanner(),
          const SizedBox(height: 16),
          Text(
            'Escolha um valor. O saldo não muda nesta versão.',
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cents in topUpSuggestions)
                ChoiceChip(
                  key: AppKeys.topUpAmount(cents),
                  label: Text(formatPrice(cents)),
                  selected: _cents == cents && !_other,
                  onSelected: (selected) {
                    setState(() {
                      _other = false;
                      _cents = selected ? cents : null;
                    });
                  },
                ),
              ChoiceChip(
                key: AppKeys.topUpOtherAmount,
                label: const Text('Outro valor'),
                selected: _other,
                onSelected: (selected) {
                  setState(() {
                    _other = selected;
                    if (selected) {
                      _cents = null;
                    }
                  });
                },
              ),
            ],
          ),
          if (_other) ...[
            const SizedBox(height: 12),
            TextField(
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Outro valor (R\$)',
                helperText: 'Só o valor em reais. Não é um dado de cartão.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Forma de pagamento',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const _SoonOption(
            optionKey: AppKeys.payWithCard,
            icon: Icons.credit_card_outlined,
            title: 'Cartão cadastrado',
          ),
          const SizedBox(height: 8),
          const _SoonOption(
            optionKey: AppKeys.payWithPix,
            icon: Icons.pix,
            title: 'Pix',
          ),
          const SizedBox(height: 20),
          const FilledButton(
            key: AppKeys.addBalanceConfirm,
            onPressed: null,
            child: Text('Confirmar'),
          ),
          const SizedBox(height: 8),
          Text(
            'Em breve. Nada é cobrado e o saldo não muda.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoonOption extends StatelessWidget {
  const _SoonOption({
    required this.optionKey,
    required this.icon,
    required this.title,
  });

  final Key optionKey;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
      child: ListTile(
        key: optionKey,
        enabled: false,
        leading: Icon(icon),
        title: Text(title),
        subtitle: const Text('Em breve'),
        titleTextStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
