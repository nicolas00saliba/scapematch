import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final adminApiProvider = Provider<AdminApi>((ref) {
  if (!scapeUsesLiveBackend) {
    throw StateError('O Admin real ainda não ligou o Supabase.');
  }
  return SupabaseAdminApi(scapeSupabase);
});

abstract class AdminApi {
  Future<AdminWho> whoami();
  Future<VenueBoard> venues({String? status, String? query});
  Future<VenueProfile> venue(String id);
  Future<ReviewResult> reviewVenue(String id, String decision);
  Future<void> suspendVenue(String id, bool suspended);
  Future<VenueProfile> updateVenue(String id, Map<String, Object?> patch);
  Future<void> setCommission({String? venueId, required int bps});
  Future<List<PlayerRow>> players(String? query);
  Future<PlayerProfile> player(String id);
  Future<void> suspendPlayer(String id, bool suspended);
  Future<List<ReviewRow>> referralQueue();
  Future<void> decideReferral({
    String? userId,
    String? venueId,
    required String decision,
  });
  Future<Map<String, Object?>> rewardSettings();
  Future<Map<String, Object?>> saveRewardSettings(Map<String, Object?> patch);
  Future<List<Map<String, Object?>>> rewardHistory();
  Future<EarningsReport> earnings({
    DateTime? from,
    DateTime? to,
    String? venueId,
  });
  Future<ScapeLiability> scapeLiability();
  Future<HighlightsBoard> highlights();
  Future<void> setHighlight(String kind, String id, int? rank);
  Future<List<AuditRow>> audit();
  Future<String?> provisionWallet(String venueId);
}

/// O banco recusou o pedido. A mensagem é a do `raise` (SQLSTATE 22023).
class AdminRejected implements Exception {
  const AdminRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

class AdminWho {
  const AdminWho({required this.name, required this.email});
  final String name;
  final String email;
}

class VenueBoard {
  const VenueBoard({
    required this.platformBps,
    required this.houses,
  });
  final int platformBps;
  final List<VenueRow> houses;
}

class VenueRow {
  const VenueRow({
    required this.id,
    required this.name,
    required this.cityId,
    required this.status,
    required this.suspended,
    required this.hasWallet,
    required this.commissionBps,
    required this.commissionOverride,
  });
  final String id;
  final String name;
  final String cityId;
  final String status;
  final bool suspended;
  final bool hasWallet;
  final int commissionBps;
  final bool commissionOverride;
}

class VenueProfile {
  const VenueProfile({
    required this.id,
    required this.name,
    required this.cityId,
    required this.neighborhood,
    required this.streetAddress,
    required this.addressNumber,
    required this.postalCode,
    required this.phone,
    required this.category,
    required this.badge,
    required this.status,
    required this.suspended,
    required this.hasWallet,
    required this.documentKind,
    required this.documentLast4,
    required this.ownerName,
    required this.ownerEmail,
    required this.platformBps,
    required this.commissionBps,
    required this.commissionOverride,
    required this.rooms,
    required this.snapshots,
  });
  final String id;
  final String name;
  final String cityId;
  final String neighborhood;
  final String streetAddress;
  final String addressNumber;
  final String postalCode;
  final String phone;
  final String category;
  final String badge;
  final String status;
  final bool suspended;
  final bool hasWallet;
  final String documentKind;
  final String documentLast4;
  final String ownerName;
  final String ownerEmail;
  final int platformBps;
  final int commissionBps;
  final bool commissionOverride;
  final List<NamedRank> rooms;
  final List<ChargeSnapshot> snapshots;
}

class ChargeSnapshot {
  const ChargeSnapshot({
    required this.id,
    required this.commissionBps,
    required this.status,
  });
  final String id;
  final int commissionBps;
  final String status;
}

class NamedRank {
  const NamedRank({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.rank,
  });
  final String id;
  final String name;
  final String subtitle;
  final int? rank;
}

class ReviewResult {
  const ReviewResult({required this.status, required this.needsSubaccount});
  final String status;
  final bool needsSubaccount;
}

class PlayerRow {
  const PlayerRow({
    required this.id,
    required this.name,
    required this.email,
    required this.suspended,
  });
  final String id;
  final String name;
  final String email;
  final bool suspended;
}

class PlayerProfile {
  const PlayerProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.username,
    required this.suspended,
    required this.referralCode,
    required this.availablePoints,
    required this.pendingPoints,
    required this.pointValueCents,
    required this.tier,
    required this.tierBonusBps,
    required this.activeReferrals,
    required this.referredBy,
    required this.referralsMade,
    required this.reservations,
    required this.entries,
  });
  final String id;
  final String name;
  final String email;
  final String phone;
  final String username;
  final bool suspended;
  final String referralCode;
  final int availablePoints;
  final int pendingPoints;
  final int pointValueCents;
  final String tier;
  final int tierBonusBps;
  final int activeReferrals;
  final String referredBy;
  final List<String> referralsMade;
  final List<String> reservations;
  final List<String> entries;
}

class ReviewRow {
  const ReviewRow({
    required this.kind,
    required this.userId,
    required this.venueId,
    required this.label,
    required this.entryCount,
    required this.amountCents,
  });
  final String kind;
  final String? userId;
  final String? venueId;
  final String label;
  final int entryCount;
  final int amountCents;
}

class EarningsReport {
  const EarningsReport({
    required this.grossCommissionCents,
    required this.rewardsRedeemedCents,
    required this.cashbackIssuedCents,
    required this.cashbackPlatformCents,
    required this.openPoints,
    required this.openPointsCents,
    required this.pendingPoints,
    required this.asaasFeeCents,
    required this.asaasFeeRows,
    required this.byVenue,
    required this.openComponents,
  });
  final int grossCommissionCents;
  final int rewardsRedeemedCents;
  final int cashbackIssuedCents;
  final int cashbackPlatformCents;
  final int openPoints;
  final int openPointsCents;
  final int pendingPoints;
  final int? asaasFeeCents;
  final int asaasFeeRows;
  final List<VenueEarnings> byVenue;
  final List<OpenComponent> openComponents;
}

class VenueEarnings {
  const VenueEarnings({
    required this.venueId,
    required this.name,
    required this.grossCommissionCents,
    required this.rewardsRedeemedCents,
    required this.cashbackIssuedCents,
    required this.openDebtCents,
  });
  final String venueId;
  final String name;
  final int grossCommissionCents;
  final int rewardsRedeemedCents;
  final int cashbackIssuedCents;
  final int openDebtCents;
}

class OpenComponent {
  const OpenComponent({
    required this.venueName,
    required this.kind,
    required this.direction,
    required this.openCents,
    required this.allOrNothing,
  });
  final String venueName;
  final String kind;
  final String direction;
  final int openCents;
  final bool allOrNothing;
}

class HighlightsBoard {
  const HighlightsBoard({
    required this.venues,
    required this.rooms,
    required this.news,
  });
  final List<NamedRank> venues;
  final List<NamedRank> rooms;
  final List<NamedRank> news;
}

class AuditRow {
  const AuditRow({
    required this.action,
    required this.targetTable,
    required this.targetId,
    required this.createdAt,
    required this.before,
    required this.after,
  });
  final String action;
  final String targetTable;
  final String targetId;
  final DateTime? createdAt;
  final String before;
  final String after;
}

class SupabaseAdminApi implements AdminApi {
  SupabaseAdminApi(this._client);
  final SupabaseClient _client;

  Future<dynamic> _rpc(String name, [Map<String, dynamic>? params]) {
    return _client.rpc(name, params: params);
  }

  @override
  Future<AdminWho> whoami() async {
    final row = _map(await _rpc('admin_whoami'));
    return AdminWho(
      name: _text(row['display_name'], 'Admin'),
      email: _text(row['email']),
    );
  }

  @override
  Future<VenueBoard> venues({String? status, String? query}) async {
    final row = _map(
      await _rpc('admin_list_venues', {
        'p_status': status,
        'p_query': query,
      }),
    );
    return VenueBoard(
      platformBps: _int(row['platform_bps']),
      houses: [
        for (final item in _list(row['houses']))
          VenueRow(
            id: _text(item['id']),
            name: _text(item['name']),
            cityId: _text(item['city_id']),
            status: _text(item['status']),
            suspended: item['suspended'] == true,
            hasWallet: item['has_wallet'] == true,
            commissionBps: _int(item['commission_bps']),
            commissionOverride: item['commission_override'] == true,
          ),
      ],
    );
  }

  @override
  Future<VenueProfile> venue(String id) async {
    return _venue(_map(await _rpc('admin_venue', {'p_venue_id': id})));
  }

  VenueProfile _venue(Map<String, dynamic> row) {
    return VenueProfile(
      id: _text(row['id']),
      name: _text(row['name']),
      cityId: _text(row['city_id']),
      neighborhood: _text(row['neighborhood']),
      streetAddress: _text(row['street_address']),
      addressNumber: _text(row['address_number']),
      postalCode: _text(row['postal_code']),
      phone: _text(row['phone']),
      category: _text(row['category']),
      badge: _text(row['badge']),
      status: _text(row['status']),
      suspended: row['suspended'] == true,
      hasWallet: row['has_wallet'] == true,
      documentKind: _text(row['document_kind']),
      documentLast4: _text(row['document_last4']),
      ownerName: _text(row['owner_name']),
      ownerEmail: _text(row['owner_email']),
      platformBps: _int(row['platform_bps']),
      commissionBps: _int(row['commission_bps']),
      commissionOverride: row['commission_override'] == true,
      rooms: [
        for (final item in _list(row['rooms']))
          NamedRank(
            id: _text(item['id']),
            name: _text(item['name']),
            subtitle: '',
            rank: _intOrNull(item['featured_rank']),
          ),
      ],
      snapshots: [
        for (final item in _list(row['snapshots']))
          ChargeSnapshot(
            id: _text(item['id']),
            commissionBps: _int(item['commission_bps']),
            status: _text(item['status']),
          ),
      ],
    );
  }

  @override
  Future<ReviewResult> reviewVenue(String id, String decision) async {
    final row = _map(
      await _rpc('admin_review_venue', {
        'p_venue_id': id,
        'p_decision': decision,
      }),
    );
    return ReviewResult(
      status: _text(row['status']),
      needsSubaccount: row['needs_subaccount'] == true,
    );
  }

  @override
  Future<void> suspendVenue(String id, bool suspended) async {
    await _rpc('admin_suspend_venue', {
      'p_venue_id': id,
      'p_suspended': suspended,
    });
  }

  @override
  Future<VenueProfile> updateVenue(String id, Map<String, Object?> patch) async {
    return _venue(
      _map(
        await _rpc('admin_update_venue', {
          'p_venue_id': id,
          'p_patch': patch,
        }),
      ),
    );
  }

  @override
  Future<void> setCommission({String? venueId, required int bps}) async {
    try {
      await _rpc('admin_set_commission', {
        'p_venue_id': venueId,
        'p_commission_bps': bps,
      });
    } on PostgrestException catch (error) {
      throw AdminRejected(error.message);
    }
  }

  @override
  Future<List<PlayerRow>> players(String? query) async {
    final rows = _list(await _rpc('admin_list_players', {'p_query': query}));
    return [
      for (final item in rows)
        PlayerRow(
          id: _text(item['id']),
          name: _text(item['display_name']),
          email: _text(item['email']),
          suspended: item['suspended'] == true,
        ),
    ];
  }

  @override
  Future<PlayerProfile> player(String id) async {
    final row = _map(await _rpc('admin_player', {'p_user_id': id}));
    final referred = row['referred_by'];
    return PlayerProfile(
      id: _text(row['id']),
      name: _text(row['display_name']),
      email: _text(row['email']),
      phone: _text(row['phone']),
      username: _text(row['username']),
      suspended: row['suspended'] == true,
      referralCode: _text(row['referral_code']),
      availablePoints: _int(row['available_points']),
      pendingPoints: _int(row['pending_points']),
      pointValueCents: _int(row['point_value_cents'], fallback: 1),
      tier: _text(row['tier'], 'inicial'),
      tierBonusBps: _int(row['tier_bonus_bps']),
      activeReferrals: _int(row['active_referrals']),
      referredBy: referred is Map
          ? _text(referred['code'], _text(referred['status']))
          : '',
      referralsMade: [
        for (final item in _list(row['referrals_made']))
          '${_text(item['status'])} · ${_text(item['subject_kind'])}',
      ],
      reservations: [
        for (final item in _list(row['reservations']))
          '${_text(item['room_name'])} · ${_text(item['venue_name'])} · ${_text(item['payment_status'])}',
      ],
      entries: [
        for (final item in _list(row['entries']))
          '${_text(item['kind'])} ${_int(item['points'])} pts · ${_text(item['program'])} · ${_text(item['review_status'], 'livre')}',
      ],
    );
  }

  @override
  Future<void> suspendPlayer(String id, bool suspended) async {
    await _rpc('admin_suspend_player', {
      'p_user_id': id,
      'p_suspended': suspended,
    });
  }

  @override
  Future<List<ReviewRow>> referralQueue() async {
    return [
      for (final item in _list(await _rpc('admin_referral_queue')))
        ReviewRow(
          kind: _text(item['subject_kind']),
          userId: _text(item['subject_user_id']).isEmpty
              ? null
              : _text(item['subject_user_id']),
          venueId: _text(item['subject_venue_id']).isEmpty
              ? null
              : _text(item['subject_venue_id']),
          label: _text(item['label']),
          entryCount: _int(item['entry_count']),
          amountCents: _int(item['amount_cents']),
        ),
    ];
  }

  @override
  Future<void> decideReferral({
    String? userId,
    String? venueId,
    required String decision,
  }) async {
    await _rpc('admin_decide_referral_account', {
      'p_subject_user_id': userId,
      'p_subject_venue_id': venueId,
      'p_decision': decision,
    });
  }

  @override
  Future<Map<String, Object?>> rewardSettings() async {
    return _map(await _rpc('admin_reward_settings'));
  }

  @override
  Future<Map<String, Object?>> saveRewardSettings(
    Map<String, Object?> patch,
  ) async {
    try {
      return _map(
        await _rpc('admin_save_reward_settings', {'p_patch': patch}),
      );
    } on PostgrestException catch (error) {
      throw AdminRejected(error.message);
    }
  }

  @override
  Future<List<Map<String, Object?>>> rewardHistory() async {
    return _list(await _rpc('admin_reward_history'));
  }

  @override
  Future<EarningsReport> earnings({
    DateTime? from,
    DateTime? to,
    String? venueId,
  }) async {
    final row = _map(
      await _rpc('admin_earnings', {
        'p_from': from?.toUtc().toIso8601String(),
        'p_to': to?.toUtc().toIso8601String(),
        'p_venue_id': venueId,
      }),
    );
    return _earnings(row);
  }

  @override
  Future<ScapeLiability> scapeLiability() async {
    return ScapeLiability.fromJson(_map(await _rpc('admin_scape_liability')));
  }

  EarningsReport _earnings(Map<String, dynamic> row) {
    return EarningsReport(
      grossCommissionCents: _int(row['gross_commission_cents']),
      rewardsRedeemedCents: _int(row['rewards_redeemed_cents']),
      cashbackIssuedCents: _int(row['cashback_issued_cents']),
      cashbackPlatformCents: _int(row['cashback_platform_cents']),
      openPoints: _int(row['open_points']),
      openPointsCents: _int(row['open_points_cents']),
      pendingPoints: _int(row['pending_points']),
      asaasFeeCents: _intOrNull(row['asaas_fee_cents']),
      asaasFeeRows: _int(row['asaas_fee_rows']),
      byVenue: [
        for (final item in _list(row['by_venue']))
          VenueEarnings(
            venueId: _text(item['venue_id']),
            name: _text(item['name']),
            grossCommissionCents: _int(item['gross_commission_cents']),
            rewardsRedeemedCents: _int(item['rewards_redeemed_cents']),
            cashbackIssuedCents: _int(item['cashback_issued_cents']),
            openDebtCents: _int(item['open_debt_cents']),
          ),
      ],
      openComponents: [
        for (final item in _list(row['open_components']))
          OpenComponent(
            venueName: _text(item['venue_name']),
            kind: _text(item['kind']),
            direction: _text(item['direction']),
            openCents: _int(item['open_cents']),
            allOrNothing: item['all_or_nothing'] == true,
          ),
      ],
    );
  }

  @override
  Future<HighlightsBoard> highlights() async {
    final row = _map(await _rpc('admin_highlights'));
    List<NamedRank> ranks(String key, String rankKey, String subtitleKey) {
      return [
        for (final item in _list(row[key]))
          NamedRank(
            id: _text(item['id']),
            name: _text(item['name'] ?? item['title']),
            subtitle: _text(item[subtitleKey]),
            rank: _intOrNull(item[rankKey]),
          ),
      ];
    }

    return HighlightsBoard(
      venues: ranks('venues', 'featured_rank', 'city_id'),
      rooms: ranks('rooms', 'featured_rank', 'venue_name'),
      news: ranks('news', 'carousel_rank', 'venue_name'),
    );
  }

  @override
  Future<void> setHighlight(String kind, String id, int? rank) async {
    await _rpc('admin_set_highlight', {
      'p_kind': kind,
      'p_id': id,
      'p_rank': rank,
    });
  }

  @override
  Future<List<AuditRow>> audit() async {
    return [
      for (final item in _list(await _rpc('admin_audit', {'p_limit': 40})))
        AuditRow(
          action: _text(item['action']),
          targetTable: _text(item['target_table']),
          targetId: _text(item['target_id']),
          createdAt: DateTime.tryParse(_text(item['created_at'])),
          before: '${item['before_state'] ?? ''}',
          after: '${item['after_state'] ?? ''}',
        ),
    ];
  }

  @override
  Future<String?> provisionWallet(String venueId) async {
    final response = await _client.functions.invoke(
      'provision-venue-wallet',
      body: {'venue_id': venueId},
    );
    final data = response.data;
    if (data is Map && data['error'] != null) {
      return 'A casa foi aprovada. A subconta Asaas não saiu nesta tentativa.';
    }
    return null;
  }
}

class MemoryAdminApi implements AdminApi {
  MemoryAdminApi()
    : houses = [
        VenueProfile(
          id: 'casa-ninja',
          name: 'Ninja Escape',
          cityId: 'curitiba',
          neighborhood: 'Batel',
          streetAddress: 'Rua do Pinheiro',
          addressNumber: '20',
          postalCode: '80420010',
          phone: '4199990001',
          category: 'escape-room',
          badge: 'Parceira',
          status: 'approved',
          suspended: false,
          hasWallet: true,
          documentKind: 'cnpj',
          documentLast4: '0181',
          ownerName: 'Dona Ninja',
          ownerEmail: 'dona@ninja.exemplo',
          platformBps: 2500,
          commissionBps: 2000,
          commissionOverride: true,
          rooms: const [
            NamedRank(
              id: 'sala-cofre',
              name: 'O Cofre',
              subtitle: 'Ninja Escape',
              rank: 0,
            ),
          ],
          snapshots: const [
            ChargeSnapshot(
              id: 'cobranca-1',
              commissionBps: 2500,
              status: 'paid',
            ),
          ],
        ),
        VenueProfile(
          id: 'casa-pendente',
          name: 'Casa da Fila',
          cityId: 'curitiba',
          neighborhood: 'Centro',
          streetAddress: 'Rua da Fila',
          addressNumber: '11',
          postalCode: '80010000',
          phone: '4199990002',
          category: 'escape-room',
          badge: '',
          status: 'pending',
          suspended: false,
          hasWallet: false,
          documentKind: 'cnpj',
          documentLast4: '0199',
          ownerName: 'Dono Novo',
          ownerEmail: 'novo@casa.exemplo',
          platformBps: 2500,
          commissionBps: 2500,
          commissionOverride: false,
          rooms: const [],
          snapshots: const [],
        ),
      ],
      people = [
        PlayerProfile(
          id: 'jogador-1',
          name: 'Ana Jogadora',
          email: 'ana@jogador.exemplo',
          phone: '',
          username: 'ana',
          suspended: false,
          referralCode: 'ANA12345',
          availablePoints: 1800,
          pendingPoints: 200,
          pointValueCents: 1,
          tier: 'prata',
          tierBonusBps: 50,
          activeReferrals: 6,
          referredBy: 'NINJA01',
          referralsMade: const ['active · player'],
          reservations: const ['O Cofre · Ninja Escape · paid'],
          entries: const ['accrual 100 pts · c2c · livre'],
        ),
      ],
      queue = [
        const ReviewRow(
          kind: 'player',
          userId: 'jogador-revisao',
          venueId: null,
          label: 'Conta em revisão',
          entryCount: 2,
          amountCents: 450,
        ),
      ],
      settings = {
        'c2c_bps': 250,
        'b2c_bps': 250,
        'c2b_bps': 250,
        'b2b_bps': 500,
        'point_value_cents': 1,
        'cashback_bps': 100,
        'redeem_min_points': 1000,
        'redeem_max_bps': 3000,
        'welcome_points': 100,
        'empty_slot_house_share_bps': 5000,
        'tier_silver_active': 5,
        'tier_silver_bonus_bps': 50,
        'tier_gold_active': 15,
        'tier_gold_bonus_bps': 100,
        'tier_active_days': 90,
        'block_self_payer': true,
        'payer_referred_account_cap': 3,
        'same_device_review_threshold': 2,
        'hold_days': 30,
        'attribution_days': 365,
        'first_booking_discount_bps': 2000,
        'cashback_min_bps': 50,
        'cashback_max_bps': 500,
        'cashback_ev_cap_bps': 100,
      };

  final List<VenueProfile> houses;
  final List<PlayerProfile> people;
  final List<ReviewRow> queue;
  final Map<String, Object?> settings;
  final List<Map<String, Object?>> history = [];
  final List<AuditRow> audits = [];
  int platformBps = 2500;
  int? feeCents = 321;

  VenueRow _row(VenueProfile house) {
    return VenueRow(
      id: house.id,
      name: house.name,
      cityId: house.cityId,
      status: house.status,
      suspended: house.suspended,
      hasWallet: house.hasWallet,
      commissionBps: house.commissionBps,
      commissionOverride: house.commissionOverride,
    );
  }

  VenueProfile _copy(
    VenueProfile house, {
    String? status,
    bool? suspended,
    bool? hasWallet,
    String? neighborhood,
    int? commissionBps,
    bool? commissionOverride,
    List<NamedRank>? rooms,
  }) {
    return VenueProfile(
      id: house.id,
      name: house.name,
      cityId: house.cityId,
      neighborhood: neighborhood ?? house.neighborhood,
      streetAddress: house.streetAddress,
      addressNumber: house.addressNumber,
      postalCode: house.postalCode,
      phone: house.phone,
      category: house.category,
      badge: house.badge,
      status: status ?? house.status,
      suspended: suspended ?? house.suspended,
      hasWallet: hasWallet ?? house.hasWallet,
      documentKind: house.documentKind,
      documentLast4: house.documentLast4,
      ownerName: house.ownerName,
      ownerEmail: house.ownerEmail,
      platformBps: platformBps,
      commissionBps: commissionBps ?? house.commissionBps,
      commissionOverride: commissionOverride ?? house.commissionOverride,
      rooms: rooms ?? house.rooms,
      snapshots: house.snapshots,
    );
  }

  void _replace(VenueProfile next) {
    final index = houses.indexWhere((house) => house.id == next.id);
    houses[index] = next;
  }

  @override
  Future<AdminWho> whoami() async {
    return const AdminWho(name: 'Nícolas', email: 'admin@scapematch.exemplo');
  }

  @override
  Future<VenueBoard> venues({String? status, String? query}) async {
    final needle = (query ?? '').trim().toLowerCase();
    final rows = [
      for (final house in houses)
        if ((status == null ||
                status.isEmpty ||
                (status == 'suspended' && house.suspended) ||
                (status != 'suspended' && house.status == status)) &&
            (needle.isEmpty || house.name.toLowerCase().contains(needle)))
          _row(house),
    ];
    return VenueBoard(platformBps: platformBps, houses: rows);
  }

  @override
  Future<VenueProfile> venue(String id) async {
    return houses.firstWhere((house) => house.id == id);
  }

  @override
  Future<ReviewResult> reviewVenue(String id, String decision) async {
    final house = await venue(id);
    _replace(_copy(house, status: decision));
    _note('review_venue', id, decision);
    return ReviewResult(
      status: decision,
      needsSubaccount: decision == 'approved' && !house.hasWallet,
    );
  }

  @override
  Future<void> suspendVenue(String id, bool suspended) async {
    final house = await venue(id);
    _replace(_copy(house, suspended: suspended));
    _note('suspend_venue', id, '$suspended');
  }

  @override
  Future<VenueProfile> updateVenue(
    String id,
    Map<String, Object?> patch,
  ) async {
    final house = await venue(id);
    final next = _copy(
      house,
      neighborhood: patch['neighborhood'] as String? ?? house.neighborhood,
    );
    _replace(next);
    _note('update_venue', id, '$patch');
    return next;
  }

  @override
  Future<void> setCommission({String? venueId, required int bps}) async {
    if (bps < 0 || bps > 3000) {
      throw const AdminRejected('A comissão fica entre 0% e 30%.');
    }
    if (venueId == null) {
      platformBps = bps;
    } else {
      final house = await venue(venueId);
      _replace(
        _copy(house, commissionBps: bps, commissionOverride: true),
      );
    }
    _note('set_commission', venueId ?? 'platform', '$bps');
  }

  @override
  Future<List<PlayerRow>> players(String? query) async {
    final needle = (query ?? '').trim().toLowerCase();
    return [
      for (final player in people)
        if (needle.isEmpty ||
            player.name.toLowerCase().contains(needle) ||
            player.email.toLowerCase().contains(needle))
          PlayerRow(
            id: player.id,
            name: player.name,
            email: player.email,
            suspended: player.suspended,
          ),
    ];
  }

  @override
  Future<PlayerProfile> player(String id) async {
    return people.firstWhere((player) => player.id == id);
  }

  @override
  Future<void> suspendPlayer(String id, bool suspended) async {
    final index = people.indexWhere((player) => player.id == id);
    final player = people[index];
    people[index] = PlayerProfile(
      id: player.id,
      name: player.name,
      email: player.email,
      phone: player.phone,
      username: player.username,
      suspended: suspended,
      referralCode: player.referralCode,
      availablePoints: player.availablePoints,
      pendingPoints: player.pendingPoints,
      pointValueCents: player.pointValueCents,
      tier: player.tier,
      tierBonusBps: player.tierBonusBps,
      activeReferrals: player.activeReferrals,
      referredBy: player.referredBy,
      referralsMade: player.referralsMade,
      reservations: player.reservations,
      entries: player.entries,
    );
    _note('suspend_player', id, '$suspended');
  }

  @override
  Future<List<ReviewRow>> referralQueue() async => List.of(queue);

  @override
  Future<void> decideReferral({
    String? userId,
    String? venueId,
    required String decision,
  }) async {
    queue.removeWhere(
      (row) => row.userId == userId && row.venueId == venueId,
    );
    _note('decide_referral_account', userId ?? venueId ?? '', decision);
  }

  @override
  Future<Map<String, Object?>> rewardSettings() async => Map.of(settings);

  @override
  Future<Map<String, Object?>> saveRewardSettings(
    Map<String, Object?> patch,
  ) async {
    final before = Map<String, Object?>.of(settings);
    settings.addAll(patch);
    history.insert(0, {'before': before, 'after': Map.of(settings)});
    _note('save_reward_settings', '1', '$patch');
    return Map.of(settings);
  }

  @override
  Future<List<Map<String, Object?>>> rewardHistory() async => List.of(history);

  @override
  Future<EarningsReport> earnings({
    DateTime? from,
    DateTime? to,
    String? venueId,
  }) async {
    return EarningsReport(
      grossCommissionCents: 25000,
      rewardsRedeemedCents: 1800,
      cashbackIssuedCents: 900,
      cashbackPlatformCents: 400,
      openPoints: 1800,
      openPointsCents: 1800,
      pendingPoints: 200,
      asaasFeeCents: feeCents,
      asaasFeeRows: feeCents == null ? 0 : 4,
      byVenue: [
        for (final house in houses)
          if (house.status == 'approved' &&
              (venueId == null || house.id == venueId))
            VenueEarnings(
              venueId: house.id,
              name: house.name,
              grossCommissionCents: 25000,
              rewardsRedeemedCents: 1800,
              cashbackIssuedCents: 900,
              openDebtCents: house.id == 'casa-ninja' ? 5000 : 0,
            ),
      ],
      openComponents: const [
        OpenComponent(
          venueName: 'Ninja Escape',
          kind: 'clawback',
          direction: 'debt',
          openCents: 5000,
          allOrNothing: true,
        ),
      ],
    );
  }

  @override
  Future<ScapeLiability> scapeLiability() async {
    return const ScapeLiability(
      unusedPoints: 2000,
      unusedCents: 2000,
      pendingPoints: 200,
      availablePoints: 1800,
      venueCreditPendingCents: 4500,
    );
  }

  @override
  Future<HighlightsBoard> highlights() async {
    return HighlightsBoard(
      venues: [
        for (final house in houses)
          if (house.status == 'approved')
            NamedRank(
              id: house.id,
              name: house.name,
              subtitle: house.cityId,
              rank: house.id == 'casa-ninja' ? 0 : null,
            ),
      ],
      rooms: [
        for (final house in houses) ...house.rooms,
      ],
      news: const [
        NamedRank(
          id: 'noticia-1',
          name: 'Noite de estreia',
          subtitle: 'Ninja Escape',
          rank: 0,
        ),
      ],
    );
  }

  @override
  Future<void> setHighlight(String kind, String id, int? rank) async {
    _note('set_highlight', id, '$kind:$rank');
  }

  @override
  Future<List<AuditRow>> audit() async => List.of(audits.reversed);

  @override
  Future<String?> provisionWallet(String venueId) async {
    final house = await venue(venueId);
    _replace(_copy(house, hasWallet: true));
    return null;
  }

  void _note(String action, String id, String after) {
    audits.add(
      AuditRow(
        action: action,
        targetTable: 'admin',
        targetId: id,
        createdAt: DateTime.utc(2026, 11, 9, 12),
        before: '',
        after: after,
      ),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        item
      else if (item is Map)
        Map<String, dynamic>.from(item),
  ];
}

String _text(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value == null) return fallback;
  return int.tryParse(value.toString()) ?? fallback;
}

int? _intOrNull(Object? value) {
  if (value == null) return null;
  return _int(value);
}
