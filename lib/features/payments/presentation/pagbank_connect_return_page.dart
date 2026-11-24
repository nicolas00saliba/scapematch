import 'package:flutter/material.dart';
import 'package:scapematch/features/payments/data/pagbank_connect_return.dart';

/// Troca `code` e `state` na função `pagbank-connect` e mostra o resultado.
class PagbankConnectReturnPage extends StatefulWidget {
  const PagbankConnectReturnPage({
    super.key,
    required this.hit,
    required this.complete,
    required this.onDone,
  });

  final PagbankConnectReturn hit;
  final Future<bool> Function(PagbankConnectReturn hit) complete;
  final VoidCallback onDone;

  @override
  State<PagbankConnectReturnPage> createState() =>
      _PagbankConnectReturnPageState();
}

class _PagbankConnectReturnPageState extends State<PagbankConnectReturnPage> {
  bool _busy = true;
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    var linked = false;
    try {
      linked = await widget.complete(widget.hit);
    } on Object {
      linked = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _linked = linked;
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = _busy
        ? 'Ligando a casa à PagBank.'
        : _linked
        ? 'A casa está ligada à PagBank.'
        : 'Não foi possível ligar a casa. Peça um link novo.';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (!_busy) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.onDone,
                  child: const Text('Continuar'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
