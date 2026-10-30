import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_phase.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

enum NoticeKind {
  reminder24h,
  reminder2h,
  paymentDeadline,
  waitlistOffer,
  groupClosed,
  noShowWarning,
}

enum ReportReason { harassment, spam, noShow, other }

class AppNotice {
  const AppNotice({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    this.groupId,
  });

  final String id;
  final String userId;
  final NoticeKind kind;
  final String title;
  final String body;
  final DateTime at;
  final String? groupId;
}

class WaitlistEntry {
  WaitlistEntry({
    required this.groupId,
    required this.userId,
    required this.displayName,
    required this.joinedAt,
    this.offerExpiresAt,
  });

  final String groupId;
  final String userId;
  final String displayName;
  final DateTime joinedAt;
  DateTime? offerExpiresAt;

  bool hasOpenOfferAt(DateTime now) {
    final expires = offerExpiresAt;
    return expires != null && now.isBefore(expires);
  }
}

class UserReport {
  const UserReport({
    required this.byUserId,
    required this.targetKey,
    required this.reason,
    required this.at,
  });

  final String byUserId;
  final String targetKey;
  final ReportReason reason;
  final DateTime at;
}

class NoShowMark {
  const NoShowMark({
    required this.userId,
    required this.groupId,
    required this.at,
  });

  final String userId;
  final String groupId;
  final DateTime at;
}

/// Memória do protótipo: bloqueio, denúncia, falta, fila e avisos.
///
/// O push de verdade entra no lugar de [record], sem a tela mudar de contrato.
class CommunityBoard {
  final blocks = <String, Set<String>>{};
  final reports = <UserReport>[];
  final noShows = <NoShowMark>[];
  final waitlist = <WaitlistEntry>[];
  final notices = <AppNotice>[];
  final _prefs = <String, Map<NoticeKind, bool>>{};
  final deletionRequests = <String>[];

  bool deletionRequested(String userId) => deletionRequests.contains(userId);

  bool prefOn(String userId, NoticeKind kind) => _prefs[userId]?[kind] ?? true;

  void setPref(String userId, NoticeKind kind, bool enabled) {
    _prefs.putIfAbsent(userId, () => {})[kind] = enabled;
  }

  /// A pessoa bloqueada some do cartão da Home de quem bloqueou.
  bool hiddenFromHome(String viewerId, Group group) {
    for (final person in group.participants) {
      if (!person.occupiesSeat) {
        continue;
      }
      final key = personKey(userId: person.userId, seatId: person.id);
      if (isBlocked(viewerId, key)) {
        return true;
      }
    }
    return false;
  }

  static String personKey({String? userId, required String seatId}) {
    if (userId != null && userId.isNotEmpty) {
      return userId;
    }
    return 'seat:$seatId';
  }

  bool isBlocked(String byUserId, String targetKey) {
    return blocks[byUserId]?.contains(targetKey) ?? false;
  }

  void block(String byUserId, String targetKey) {
    blocks.putIfAbsent(byUserId, () => {}).add(targetKey);
  }

  void report({
    required String byUserId,
    required String targetKey,
    required ReportReason reason,
    required DateTime at,
  }) {
    reports.add(
      UserReport(
        byUserId: byUserId,
        targetKey: targetKey,
        reason: reason,
        at: at,
      ),
    );
  }

  void markNoShow({
    required String userId,
    required String groupId,
    required DateTime at,
  }) {
    final exists = noShows.any(
      (mark) => mark.userId == userId && mark.groupId == groupId,
    );
    if (exists) {
      return;
    }
    noShows.add(NoShowMark(userId: userId, groupId: groupId, at: at));
    final dates = [
      for (final mark in noShows)
        if (mark.userId == userId) mark.at,
    ];
    final recent = GroupRules.noShowsInWindow(dates, at);
    if (recent.length == GroupRules.noShowLimit - 1) {
      _putNotice(
        userId: userId,
        kind: NoticeKind.noShowWarning,
        title: 'Falta sem aviso',
        body:
            'Mais uma falta em ${GroupRules.noShowWindow.inDays} dias pausa a conta por ${GroupRules.noShowRestriction.inDays} dias.',
        at: at,
        groupId: groupId,
      );
    }
  }

  bool restricted(String userId, DateTime now) {
    final dates = [
      for (final mark in noShows)
        if (mark.userId == userId) mark.at,
    ];
    return GroupRules.joinRestricted(dates, now);
  }

  WaitlistEntry? entryFor(String groupId, String userId) {
    for (final entry in waitlist) {
      if (entry.groupId == groupId && entry.userId == userId) {
        return entry;
      }
    }
    return null;
  }

  String? joinWaitlist({
    required String groupId,
    required String userId,
    required String displayName,
    required DateTime now,
  }) {
    if (entryFor(groupId, userId) != null) {
      return 'Você já está na lista de espera.';
    }
    waitlist.add(
      WaitlistEntry(
        groupId: groupId,
        userId: userId,
        displayName: displayName,
        joinedAt: now,
      ),
    );
    return null;
  }

  /// Tira da fila quem deixou a oferta vencer.
  int clearExpiredOffers(String groupId, DateTime now) {
    final before = waitlist.length;
    waitlist.removeWhere((entry) {
      if (entry.groupId != groupId) {
        return false;
      }
      final expires = entry.offerExpiresAt;
      return expires != null && !now.isBefore(expires);
    });
    return before - waitlist.length;
  }

  int openOfferCount(String groupId, DateTime now, {String? exceptUserId}) {
    var count = 0;
    for (final entry in waitlist) {
      if (entry.groupId != groupId) {
        continue;
      }
      if (exceptUserId != null && entry.userId == exceptUserId) {
        continue;
      }
      if (entry.hasOpenOfferAt(now)) {
        count += 1;
      }
    }
    return count;
  }

  /// Oferece a vaga à próxima pessoa que ainda não tem oferta aberta.
  ///
  /// Quem já tem oferta aberta é pulado. Oferta vencida sai antes, em
  /// [clearExpiredOffers], para não segurar a fila.
  bool offerNext({required String groupId, required DateTime now}) {
    WaitlistEntry? next;
    for (final entry in waitlist) {
      if (entry.groupId != groupId || entry.hasOpenOfferAt(now)) {
        continue;
      }
      if (entry.offerExpiresAt != null) {
        continue;
      }
      next = entry;
      break;
    }
    if (next == null) {
      return false;
    }
    next.offerExpiresAt = now.add(GroupRules.waitlistAcceptWindow);
    _putNotice(
      userId: next.userId,
      kind: NoticeKind.waitlistOffer,
      title: 'Abriu uma vaga',
      body:
          'Você tem ${GroupRules.waitlistAcceptWindow.inHours} h para aceitar.',
      at: now,
      groupId: groupId,
    );
    return true;
  }

  bool offerStillOpen(WaitlistEntry entry, DateTime now) {
    final expires = entry.offerExpiresAt;
    return expires != null && now.isBefore(expires);
  }

  void removeWaitlist(String groupId, String userId) {
    waitlist.removeWhere(
      (entry) => entry.groupId == groupId && entry.userId == userId,
    );
  }

  void recordClosedGroup(Group group, DateTime now) {
    for (final person in group.participants) {
      final userId = person.userId;
      if (userId == null || !person.occupiesSeat) {
        continue;
      }
      _putNotice(
        userId: userId,
        kind: NoticeKind.groupClosed,
        title: 'Grupo cancelado',
        body: GroupClosedCopy.body,
        at: now,
        groupId: group.id,
      );
    }
  }

  void syncReminders({
    required List<Group> groups,
    required String userId,
    required DateTime now,
  }) {
    for (final group in groups) {
      final member = group.participantForUser(userId);
      if (member == null || !member.occupiesSeat || group.isCancelled) {
        continue;
      }
      final untilStart = group.startsAt.difference(now);
      if (untilStart > GroupRules.reminder2h &&
          untilStart <= GroupRules.reminder24h) {
        _putNotice(
          userId: userId,
          kind: NoticeKind.reminder24h,
          title: 'Jogo em até 24 h',
          body: group.roomName,
          at: now,
          groupId: group.id,
        );
      }
      if (untilStart > Duration.zero && untilStart <= GroupRules.reminder2h) {
        _putNotice(
          userId: userId,
          kind: NoticeKind.reminder2h,
          title: 'Jogo em até 2 h',
          body: group.roomName,
          at: now,
          groupId: group.id,
        );
      }
      final untilClose = group.closesAtResolved.difference(now);
      final phase = group.phaseAt(now);
      final forming =
          phase == GroupPhase.forming || phase == GroupPhase.readyToReserve;
      if (forming &&
          untilClose > Duration.zero &&
          untilClose <= GroupRules.paymentReminderWindow) {
        _putNotice(
          userId: userId,
          kind: NoticeKind.paymentDeadline,
          title: 'Prazo do grupo perto',
          body:
              'O prazo para fechar ${group.roomName} está perto. Nada é cobrado nesta versão.',
          at: now,
          groupId: group.id,
        );
      }
    }
  }

  List<AppNotice> visibleFor(String userId) {
    return [
      for (final notice in notices)
        if (notice.userId == userId && prefOn(userId, notice.kind)) notice,
    ];
  }

  void _putNotice({
    required String userId,
    required NoticeKind kind,
    required String title,
    required String body,
    required DateTime at,
    String? groupId,
  }) {
    final id = '$kind-$userId-${groupId ?? 'conta'}';
    if (notices.any((notice) => notice.id == id)) {
      return;
    }
    notices.add(
      AppNotice(
        id: id,
        userId: userId,
        kind: kind,
        title: title,
        body: body,
        at: at,
        groupId: groupId,
      ),
    );
  }
}

/// Texto do aviso de grupo que não fechou, compartilhado com a tela.
abstract final class GroupClosedCopy {
  static const body =
      'O grupo não atingiu o mínimo no prazo. O reembolso simulado é integral.';
}

final communityBoardProvider = Provider<CommunityBoard>((ref) {
  return CommunityBoard();
});

class CommunityTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final communityTickProvider = NotifierProvider<CommunityTick, int>(
  CommunityTick.new,
);
