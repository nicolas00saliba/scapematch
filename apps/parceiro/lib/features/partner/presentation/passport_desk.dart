import 'package:flutter/material.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_parceiro/partner_keys.dart';

class PassportRoomChoice {
  const PassportRoomChoice({required this.id, required this.name});

  final String id;
  final String name;
}

class PassportGiftRow {
  const PassportGiftRow({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.triggerKind,
    required this.title,
    required this.details,
    required this.active,
  });

  final String id;
  final String? roomId;
  final String? roomName;
  final String triggerKind;
  final String title;
  final String details;
  final bool active;

  PassportGiftRow copyWith({bool? active, String? title, String? details}) {
    return PassportGiftRow(
      id: id,
      roomId: roomId,
      roomName: roomName,
      triggerKind: triggerKind,
      title: title ?? this.title,
      details: details ?? this.details,
      active: active ?? this.active,
    );
  }

  factory PassportGiftRow.fromJson(Map<String, dynamic> json) {
    final roomId = json['room_id']?.toString();
    final roomName = json['room_name']?.toString();
    return PassportGiftRow(
      id: json['id']?.toString() ?? '',
      roomId: roomId == null || roomId.isEmpty ? null : roomId,
      roomName: roomName == null || roomName.isEmpty ? null : roomName,
      triggerKind: json['trigger_kind']?.toString() ?? 'stamp',
      title: json['title']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      active: json['active'] == true,
    );
  }
}

class PassportClaimRow {
  const PassportClaimRow({
    required this.id,
    required this.code,
    required this.status,
    required this.title,
    this.roomName,
    this.playerName,
  });

  final String id;
  final String code;
  final String status;
  final String title;
  final String? roomName;
  final String? playerName;

  bool get delivered => status == 'delivered';

  PassportClaimRow copyWith({String? status}) {
    return PassportClaimRow(
      id: id,
      code: code,
      status: status ?? this.status,
      title: title,
      roomName: roomName,
      playerName: playerName,
    );
  }

  factory PassportClaimRow.fromJson(Map<String, dynamic> json) {
    final room = json['room_name']?.toString();
    final player = json['player_name']?.toString();
    return PassportClaimRow(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      status: json['status']?.toString() ?? 'available',
      title: json['title']?.toString() ?? 'Mimo',
      roomName: room == null || room.isEmpty ? null : room,
      playerName: player == null || player.isEmpty ? null : player,
    );
  }
}

class PassportDeskData {
  const PassportDeskData({
    required this.enabled,
    required this.gifts,
    required this.claims,
  });

  final bool enabled;
  final List<PassportGiftRow> gifts;
  final List<PassportClaimRow> claims;

  static const sample = PassportDeskData(
    enabled: true,
    gifts: [
      PassportGiftRow(
        id: 'mimo-foto',
        roomId: 'sala-cofre',
        roomName: 'O Cofre',
        triggerKind: 'stamp',
        title: 'Foto da sala',
        details: 'Uma foto exclusiva depois do jogo.',
        active: true,
      ),
      PassportGiftRow(
        id: 'mimo-chaveiro',
        roomId: null,
        roomName: null,
        triggerKind: 'house_complete',
        title: 'Chaveiro da casa',
        details: 'Quando fechar as salas.',
        active: true,
      ),
    ],
    claims: [
      PassportClaimRow(
        id: 'pedido-foto',
        code: 'FOTO7A2C',
        status: 'available',
        title: 'Foto da sala',
        roomName: 'O Cofre',
        playerName: 'Ana',
      ),
    ],
  );

  factory PassportDeskData.fromJson(Map<String, dynamic> json) {
    return PassportDeskData(
      enabled: json['enabled'] == true,
      gifts: _maps(json['gifts']).map(PassportGiftRow.fromJson).toList(),
      claims: _maps(json['claims']).map(PassportClaimRow.fromJson).toList(),
    );
  }

  PassportDeskData copyWith({
    List<PassportGiftRow>? gifts,
    List<PassportClaimRow>? claims,
  }) {
    return PassportDeskData(
      enabled: enabled,
      gifts: gifts ?? this.gifts,
      claims: claims ?? this.claims,
    );
  }
}

/// Balcão de mimos. O custo é da casa. Nada aqui é obrigatório.
class PassportDesk extends StatefulWidget {
  const PassportDesk({
    super.key,
    required this.venueId,
    required this.rooms,
    this.preview,
  });

  final String venueId;
  final List<PassportRoomChoice> rooms;

  /// Preenchido na demonstração. No ar, a tela lê `my_passport_desk`.
  final PassportDeskData? preview;

  @override
  State<PassportDesk> createState() => _PassportDeskState();
}

class _PassportDeskState extends State<PassportDesk> {
  PassportDeskData? _data;
  var _loading = false;
  String? _message;
  final _title = TextEditingController();
  final _details = TextEditingController();
  String _trigger = 'stamp';
  String? _roomId;
  var _active = true;
  final _code = TextEditingController();

  bool get _demo => widget.preview != null;

  @override
  void initState() {
    super.initState();
    _roomId = widget.rooms.isEmpty ? null : widget.rooms.first.id;
    if (_demo) {
      _data = widget.preview;
      return;
    }
    _loading = true;
    Future<void>(() async {
      await _load();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await scapeSupabase.rpc(
        'my_passport_desk',
        params: {'p_venue_id': widget.venueId},
      );
      if (!mounted) return;
      setState(() {
        _data = data is Map
            ? PassportDeskData.fromJson(Map<String, dynamic>.from(data))
            : null;
        _loading = false;
        if (_data == null) _message = 'Não foi possível ler os mimos.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Não foi possível ler os mimos.';
      });
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final details = _details.text.trim();
    if (title.length < 2 || title.length > 80 || details.length > 400) {
      setState(() => _message = 'Escreva o mimo em até 80 letras.');
      return;
    }
    final roomId = _trigger == 'stamp' ? _roomId : null;
    if (_trigger == 'stamp' && roomId == null) {
      setState(() => _message = 'Escolha a sala do carimbo.');
      return;
    }
    if (_demo) {
      final current = _data ?? PassportDeskData.sample;
      final roomName = roomId == null
          ? null
          : widget.rooms
                .where((room) => room.id == roomId)
                .map((room) => room.name)
                .firstOrNull;
      setState(() {
        _data = current.copyWith(
          gifts: [
            ...current.gifts,
            PassportGiftRow(
              id: 'local-${current.gifts.length + 1}',
              roomId: roomId,
              roomName: roomName,
              triggerKind: _trigger,
              title: title,
              details: details,
              active: _active,
            ),
          ],
        );
        _message = 'Mimo anotado neste exemplo.';
        _title.clear();
        _details.clear();
      });
      return;
    }
    try {
      await scapeSupabase.rpc(
        'save_passport_gift',
        params: {
          'p_venue_id': widget.venueId,
          'p_room_id': roomId,
          'p_trigger': _trigger,
          'p_title': title,
          'p_details': details,
          'p_active': _active,
          'p_gift_id': null,
        },
      );
      if (!mounted) return;
      _title.clear();
      _details.clear();
      setState(() => _message = 'Mimo gravado.');
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = _giftError(error));
    }
  }

  Future<void> _toggle(PassportGiftRow gift, bool active) async {
    if (_demo) {
      final current = _data;
      if (current == null) return;
      setState(() {
        _data = current.copyWith(
          gifts: [
            for (final item in current.gifts)
              if (item.id == gift.id) item.copyWith(active: active) else item,
          ],
        );
      });
      return;
    }
    try {
      await scapeSupabase.rpc(
        'save_passport_gift',
        params: {
          'p_venue_id': widget.venueId,
          'p_room_id': gift.roomId,
          'p_trigger': gift.triggerKind,
          'p_title': gift.title,
          'p_details': gift.details,
          'p_active': active,
          'p_gift_id': gift.id,
        },
      );
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = _giftError(error));
    }
  }

  Future<void> _deliver(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.length != 8) {
      setState(() => _message = 'O código tem 8 caracteres.');
      return;
    }
    if (_demo) {
      final current = _data;
      if (current == null) return;
      final known = current.claims.any((claim) => claim.code == trimmed);
      if (!known) {
        setState(() => _message = 'Código não encontrado neste exemplo.');
        return;
      }
      setState(() {
        _data = current.copyWith(
          claims: [
            for (final claim in current.claims)
              if (claim.code == trimmed)
                claim.copyWith(status: 'delivered')
              else
                claim,
          ],
        );
        _message = 'Mimo marcado como entregue.';
        _code.clear();
      });
      return;
    }
    try {
      await scapeSupabase.rpc(
        'deliver_passport_gift',
        params: {'p_code': trimmed},
      );
      if (!mounted) return;
      _code.clear();
      setState(() => _message = 'Mimo marcado como entregue.');
      await _load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _message = _giftError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _data;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(_message ?? 'Não foi possível ler os mimos.'),
      );
    }
    return ListView(
      key: PartnerKeys.passportDesk,
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Mimos do passaporte',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Opcional. O custo é da casa. O jogador ganha um código ao carimbar a sala ou ao fechar a casa, e mostra o código aqui.',
        ),
        if (!data.enabled) ...[
          const SizedBox(height: 8),
          const Text(
            'O passaporte ainda está desligado no EscapeMatch. Dá para deixar o mimo pronto.',
            key: Key('passport-desk-off'),
          ),
        ],
        if (_demo) ...[
          const SizedBox(height: 8),
          const Text(
            'Exemplo desta casa. Nada aqui foi gravado.',
            key: Key('passport-desk-sample'),
          ),
        ],
        const SizedBox(height: 16),
        if (data.gifts.isEmpty)
          const Text('Nenhum mimo cadastrado.')
        else
          for (final gift in data.gifts)
            SwitchListTile(
              key: Key('passport-gift-active-${gift.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(gift.title),
              subtitle: Text(_giftWhere(gift)),
              value: gift.active,
              onChanged: (value) => _toggle(gift, value),
            ),
        const SizedBox(height: 8),
        Text(
          'Novo mimo',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('passport-gift-title'),
          controller: _title,
          decoration: const InputDecoration(
            labelText: 'Nome do mimo',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('passport-gift-details'),
          controller: _details,
          decoration: const InputDecoration(
            labelText: 'O que a pessoa recebe',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('passport-gift-trigger'),
          initialValue: _trigger,
          decoration: const InputDecoration(
            labelText: 'Quando libera',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'stamp', child: Text('Ao ganhar o carimbo')),
            DropdownMenuItem(
              value: 'house_complete',
              child: Text('Ao fechar a casa'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _trigger = value);
          },
        ),
        if (_trigger == 'stamp') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const Key('passport-gift-room'),
            initialValue: _roomId,
            decoration: const InputDecoration(
              labelText: 'Sala',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final room in widget.rooms)
                DropdownMenuItem(value: room.id, child: Text(room.name)),
            ],
            onChanged: (value) => setState(() => _roomId = value),
          ),
        ],
        SwitchListTile(
          key: const Key('passport-gift-active'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo'),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('passport-gift-save'),
            onPressed: _save,
            child: const Text('Salvar mimo'),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Entregar',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('passport-claim-code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Código de 8 caracteres',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const Key('passport-claim-deliver'),
            onPressed: () => _deliver(_code.text),
            child: const Text('Marcar entregue'),
          ),
        ),
        const SizedBox(height: 12),
        if (data.claims.isEmpty)
          const Text('Nenhum código para entregar.')
        else
          for (final claim in data.claims)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${claim.title} · ${claim.code}'),
              subtitle: Text(
                [
                  if (claim.playerName != null) claim.playerName!,
                  if (claim.roomName != null) claim.roomName!,
                  claim.delivered ? 'Entregue' : 'Aguardando',
                ].join(' · '),
              ),
              trailing: claim.delivered
                  ? null
                  : TextButton(
                      key: Key('passport-deliver-${claim.code}'),
                      onPressed: () => _deliver(claim.code),
                      child: const Text('Entregar'),
                    ),
            ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, key: const Key('passport-desk-message')),
        ],
      ],
    );
  }
}

String _giftWhere(PassportGiftRow gift) {
  final when = gift.triggerKind == 'house_complete'
      ? 'Ao fechar a casa'
      : 'Ao carimbar ${gift.roomName ?? 'a sala'}';
  return gift.active ? when : '$when · desligado';
}

String _giftError(Object error) {
  final text = error.toString();
  if (text.contains('passaporte desligado')) {
    return 'O passaporte ainda está desligado.';
  }
  if (text.contains('not owner')) return 'Esta casa não é sua.';
  if (text.contains('codigo nao encontrado')) return 'Código não encontrado.';
  if (text.contains('mimo ja tratado')) return 'Este mimo já foi tratado.';
  return 'Não foi possível gravar o mimo.';
}

List<Map<String, dynamic>> _maps(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}
