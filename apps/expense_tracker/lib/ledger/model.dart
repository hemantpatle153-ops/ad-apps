import 'dart:math';

/// Friends ledger: a money log shared by two friends, kept in Firebase.
///
/// Each log has two sides, `a` (who made it) and `b` (the friend). Any
/// number of phones can join a log with its code; each phone says which of
/// the two friends it belongs to, so both friends can use several phones.
///
/// Every entry records who paid ([LedgerEntry.by]); the other side owes that
/// amount. Amounts are whole minor units (paise), so totals never drift.

enum Side {
  a,
  b;

  Side get other => this == a ? b : a;

  static Side? parse(Object? v) => switch (v) {
        'a' => a,
        'b' => b,
        _ => null,
      };
}

/// How long a cleared ledger stays readable before it is deleted from the
/// cloud. Each phone keeps its own copy after that.
const settledKeepDays = 14;
const settledKeep = Duration(days: settledKeepDays);

/// Largest single entry, in minor units (₹1,000 crore). The database keeps
/// numbers as doubles, so this keeps every total an exact integer.
const maxEntryAmount = 100000000000;

const maxNoteLength = 200;
const maxTagLength = 30;
const maxNameLength = 30;

/// Purpose tags offered in the editor. Any other text is allowed too.
const purposeTags = [
  'Loan',
  'Food',
  'Trip',
  'Rent',
  'Shopping',
  'Bills',
  'Fuel',
  'Movie',
  'Gift',
  'Other',
];

/// Letters and digits that can't be mixed up when read out (no 0/O, 1/I/L).
const codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const codeLength = 8;

String newJoinCode([Random? rng]) {
  final r = rng ?? Random.secure();
  return List.generate(
      codeLength, (_) => codeAlphabet[r.nextInt(codeAlphabet.length)]).join();
}

/// "ABCD2345" -> "ABCD-2345", easier to read out.
String prettyCode(String code) => code.length == codeLength
    ? '${code.substring(0, 4)}-${code.substring(4)}'
    : code;

/// Cleans a typed or pasted code: upper case, no spaces or dashes. Null if
/// it can't be a join code.
String? normalizeJoinCode(String raw) {
  final code = raw.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
  if (code.length != codeLength) return null;
  for (var i = 0; i < code.length; i++) {
    if (!codeAlphabet.contains(code[i])) return null;
  }
  return code;
}

/// Pulls a join code out of a forwarded invite message, if it has one.
String? findJoinCode(String text) {
  final m =
      RegExp(r'\b([A-Za-z0-9]{4})[\s-]?([A-Za-z0-9]{4})\b').allMatches(text);
  for (final x in m) {
    final c = normalizeJoinCode('${x[1]}${x[2]}');
    if (c != null) return c;
  }
  return null;
}

String cleanName(String raw) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  return t.length > maxNameLength ? t.substring(0, maxNameLength) : t;
}

String cleanText(String raw, int max) {
  final t = raw.trim();
  return t.length > max ? t.substring(0, max) : t;
}

int? _int(Object? v) => v is int
    ? v
    : v is num
        ? v.toInt()
        : null;

/// One line of the log.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.amount,
    required this.by,
    required this.date,
    this.tag = '',
    this.note = '',
    this.createdAt = 0,
    this.createdBy,
    this.editedAt,
    this.editedBy,
  });

  final String id;

  /// Minor units, > 0.
  final int amount;

  /// Who paid or lent; the other side will give this back.
  final Side by;

  /// The day the money changed hands (editable).
  final DateTime date;

  /// Purpose tag, e.g. "Food".
  final String tag;
  final String note;

  /// Server time the entry was added, ms.
  final int createdAt;
  final Side? createdBy;

  /// Server time of the last edit, ms; null if never edited.
  final int? editedAt;
  final Side? editedBy;

  bool get isEdited => editedAt != null;

  /// Who owes this amount.
  Side get owedBy => by.other;

  Map<String, Object?> toJson() => {
        'amt': amount,
        'by': by.name,
        'date': date.millisecondsSinceEpoch,
        'tag': tag,
        'note': note,
        'at': createdAt,
        if (createdBy != null) 'cs': createdBy!.name,
        if (editedAt != null) 'ea': editedAt,
        if (editedBy != null) 'es': editedBy!.name,
      };

  /// Null for anything malformed, so one bad record can't break the log.
  static LedgerEntry? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final amt = _int(raw['amt']);
    final by = Side.parse(raw['by']);
    final date = _int(raw['date']);
    if (amt == null || amt <= 0 || amt > maxEntryAmount) return null;
    if (by == null || date == null) return null;
    return LedgerEntry(
      id: id,
      amount: amt,
      by: by,
      date: DateTime.fromMillisecondsSinceEpoch(date),
      tag: raw['tag'] is String ? raw['tag'] as String : '',
      note: raw['note'] is String ? raw['note'] as String : '',
      createdAt: _int(raw['at']) ?? 0,
      createdBy: Side.parse(raw['cs']),
      editedAt: _int(raw['ea']),
      editedBy: Side.parse(raw['es']),
    );
  }

  LedgerEntry copyWith({
    int? amount,
    Side? by,
    DateTime? date,
    String? tag,
    String? note,
  }) =>
      LedgerEntry(
        id: id,
        amount: amount ?? this.amount,
        by: by ?? this.by,
        date: date ?? this.date,
        tag: tag ?? this.tag,
        note: note ?? this.note,
        createdAt: createdAt,
        createdBy: createdBy,
        editedAt: editedAt,
        editedBy: editedBy,
      );
}

/// Newest day first; same day: newest added first; then by id so the order
/// is the same on every phone.
int compareEntries(LedgerEntry x, LedgerEntry y) {
  final d = y.date.compareTo(x.date);
  if (d != 0) return d;
  final c = y.createdAt.compareTo(x.createdAt);
  if (c != 0) return c;
  return y.id.compareTo(x.id);
}

/// Totals of a log, from one side's point of view.
class Balance {
  const Balance({
    required this.me,
    required this.theyGiveMe,
    required this.iGiveThem,
    required this.theyGiveMeCount,
    required this.iGiveThemCount,
  });

  factory Balance.of(Iterable<LedgerEntry> entries, Side me) {
    var mine = 0, theirs = 0, nm = 0, nt = 0;
    for (final e in entries) {
      if (e.by == me) {
        mine += e.amount;
        nm++;
      } else {
        theirs += e.amount;
        nt++;
      }
    }
    return Balance(
      me: me,
      theyGiveMe: mine,
      iGiveThem: theirs,
      theyGiveMeCount: nm,
      iGiveThemCount: nt,
    );
  }

  final Side me;

  /// Sum of what I paid or lent: my friend will give this to me.
  final int theyGiveMe;

  /// Sum of what my friend paid or lent: I will give this to them.
  final int iGiveThem;
  final int theyGiveMeCount;
  final int iGiveThemCount;

  /// Positive: friend gives me; negative: I give friend.
  int get net => theyGiveMe - iGiveThem;

  /// The amount that changes hands at the end.
  int get amount => net.abs();

  /// Who pays at the end, or null when it is all clear.
  Side? get payer => net > 0
      ? me.other
      : net < 0
          ? me
          : null;

  Side? get receiver => payer?.other;

  bool get isClear => net == 0;
}

/// A neutral version of the result: side a's net. Same on every phone.
int netForA(Iterable<LedgerEntry> entries) => Balance.of(entries, Side.a).net;

/// FNV-1a, 32 bit; stable across platforms.
int _fnv(String s, [int h = 0x811c9dc5]) {
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// Fingerprint of exactly what is being settled. A confirmation only counts
/// while the log still matches it, so a change after a friend asked to settle
/// means they have to look again.
String fingerprint(Iterable<LedgerEntry> entries) {
  final list = entries.toList()..sort((x, y) => x.id.compareTo(y.id));
  var h = 0x811c9dc5;
  for (final e in list) {
    h = _fnv(
        '${e.id}|${e.amount}|${e.by.name}|${e.date.millisecondsSinceEpoch};',
        h);
  }
  return '${list.length}.${netForA(list)}.${h.toRadixString(16)}';
}

/// One side's "yes, this ledger is right" for one version of the log.
class Approval {
  const Approval({required this.sig, required this.net, this.at = 0});
  final String sig;

  /// Side a's net at the time, to show what was agreed.
  final int net;
  final int at;

  Map<String, Object?> toJson() => {'sig': sig, 'net': net, 'at': at};

  static Approval? fromJson(Object? raw) {
    if (raw is! Map || raw['sig'] is! String) return null;
    return Approval(
      sig: raw['sig'] as String,
      net: _int(raw['net']) ?? 0,
      at: _int(raw['at']) ?? 0,
    );
  }
}

enum SettleStage {
  /// Nobody asked to clear the ledger (or the log changed since).
  open,

  /// I confirmed; waiting for my friend.
  waitingForFriend,

  /// My friend confirmed; waiting for me.
  friendAsked,

  /// Both confirmed: read-only until it is deleted from the cloud.
  settled,
}

/// A whole log as read from the database.
class LedgerLog {
  const LedgerLog({
    required this.id,
    required this.nameA,
    required this.nameB,
    required this.code,
    this.created = 0,
    this.members = const {},
    this.entries = const [],
    this.approvals = const {},
    this.settledAt,
  });

  final String id;
  final String nameA;
  final String nameB;
  final String code;
  final int created;

  /// Phone (anonymous user id) -> which friend it belongs to.
  final Map<String, Side> members;

  /// Sorted with [compareEntries].
  final List<LedgerEntry> entries;
  final Map<Side, Approval> approvals;

  /// Server time both friends confirmed, ms.
  final int? settledAt;

  String nameOf(Side s) => s == Side.a ? nameA : nameB;

  bool get isSettled => settledAt != null;

  /// When the cloud copy goes, ms.
  int? get deleteAt =>
      settledAt == null ? null : settledAt! + settledKeep.inMilliseconds;

  bool isExpired(int nowMs) => deleteAt != null && nowMs >= deleteAt!;

  /// Whole days left before deletion, rounded up; 0 once due.
  int daysLeft(int nowMs) {
    final d = deleteAt;
    if (d == null) return settledKeepDays;
    final ms = d - nowMs;
    if (ms <= 0) return 0;
    return (ms + Duration.millisecondsPerDay - 1) ~/
        Duration.millisecondsPerDay;
  }

  Balance balanceFor(Side me) => Balance.of(entries, me);

  String get sig => fingerprint(entries);

  /// Confirmations that still match the log as it is now.
  bool approvedBy(Side s) => approvals[s]?.sig == sig;

  /// A confirmation made for an older version of the log.
  bool staleApprovalBy(Side s) => approvals[s] != null && !approvedBy(s);

  SettleStage stageFor(Side me) {
    if (isSettled) return SettleStage.settled;
    final mine = approvedBy(me), theirs = approvedBy(me.other);
    if (mine && theirs) return SettleStage.settled;
    if (mine) return SettleStage.waitingForFriend;
    if (theirs) return SettleStage.friendAsked;
    return SettleStage.open;
  }

  /// Entries can be added or changed only while the ledger is open.
  bool get editable => !isSettled;

  int devicesOf(Side s) => members.values.where((v) => v == s).length;

  Map<String, Object?> toJson() => {
        'meta': {'a': nameA, 'b': nameB, 'code': code, 'created': created},
        'members': {
          for (final m in members.entries) m.key: {'s': m.value.name}
        },
        'entries': {for (final e in entries) e.id: e.toJson()},
        'ok': {for (final a in approvals.entries) a.key.name: a.value.toJson()},
        if (settledAt != null) 'done': settledAt,
      };

  /// Null when the data isn't a readable log (deleted, or no access).
  static LedgerLog? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final meta = raw['meta'];
    if (meta is! Map) return null;
    final members = <String, Side>{};
    final rawMembers = raw['members'];
    if (rawMembers is Map) {
      rawMembers.forEach((k, v) {
        final s = Side.parse(v is Map ? v['s'] : v);
        if (s != null) members['$k'] = s;
      });
    }
    final entries = <LedgerEntry>[];
    final rawEntries = raw['entries'];
    if (rawEntries is Map) {
      rawEntries.forEach((k, v) {
        final e = LedgerEntry.fromJson('$k', v);
        if (e != null) entries.add(e);
      });
    }
    entries.sort(compareEntries);
    final approvals = <Side, Approval>{};
    final ok = raw['ok'];
    if (ok is Map) {
      ok.forEach((k, v) {
        final s = Side.parse(k);
        final a = Approval.fromJson(v);
        if (s != null && a != null) approvals[s] = a;
      });
    }
    return LedgerLog(
      id: id,
      nameA: '${meta['a'] ?? 'Friend 1'}',
      nameB: '${meta['b'] ?? 'Friend 2'}',
      code: '${meta['code'] ?? ''}',
      created: _int(meta['created']) ?? 0,
      members: members,
      entries: entries,
      approvals: approvals,
      settledAt: _int(raw['done']),
    );
  }
}

/// What a join code points at: enough to ask "which one are you?".
class CodeInfo {
  const CodeInfo({required this.id, required this.nameA, required this.nameB});
  final String id;
  final String nameA;
  final String nameB;

  String nameOf(Side s) => s == Side.a ? nameA : nameB;

  Map<String, Object?> toJson() => {'id': id, 'a': nameA, 'b': nameB};

  static CodeInfo? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    return CodeInfo(
      id: raw['id'] as String,
      nameA: '${raw['a'] ?? 'Friend 1'}',
      nameB: '${raw['b'] ?? 'Friend 2'}',
    );
  }
}

/// Stands for "the server's clock" in a planned write. Backends swap it for
/// their own timestamp (Firebase: ServerValue.timestamp).
class ServerTime {
  const ServerTime._();
  @override
  String toString() => 'ServerTime';
}

const serverTime = ServerTime._();

/// Every change to the database as one multi-path update, so each write
/// either fully lands or not at all, and the security rules check each part.
/// Paths are from the database root.
abstract final class LedgerWrites {
  static String logPath(String id) => 'ledger/$id';
  static String codePath(String code) => 'ledgerCodes/$code';
  static String gcPath(String id) => 'ledgerGc/$id';

  static Map<String, Object?> create({
    required String id,
    required String code,
    required String uid,
    required String myName,
    required String friendName,
  }) =>
      {
        '${logPath(id)}/meta': {
          'a': myName,
          'b': friendName,
          'code': code,
          'created': serverTime,
        },
        '${logPath(id)}/members/$uid': {'s': 'a'},
        codePath(code): {'id': id, 'a': myName, 'b': friendName},
      };

  /// The code goes in the member record because the rules check it there:
  /// only someone who knows the current code can join.
  static Map<String, Object?> join({
    required CodeInfo info,
    required String code,
    required String uid,
    required Side side,
  }) =>
      {
        '${logPath(info.id)}/members/$uid': {'s': side.name, 'c': code},
      };

  /// Switches which friend this phone is. Only for phones already in.
  static Map<String, Object?> switchSide(String id, String uid, Side side) => {
        '${logPath(id)}/members/$uid/s': side.name,
      };

  static Map<String, Object?> leave(String id, String uid) => {
        '${logPath(id)}/members/$uid': null,
      };

  /// New code for the same log. Members, entries and confirmations stay.
  static Map<String, Object?> resetCode(LedgerLog log, String newCode) => {
        if (log.code.isNotEmpty) codePath(log.code): null,
        codePath(newCode): {'id': log.id, 'a': log.nameA, 'b': log.nameB},
        '${logPath(log.id)}/meta/code': newCode,
      };

  static Map<String, Object?> rename(LedgerLog log, Side side, String name) => {
        '${logPath(log.id)}/meta/${side.name}': name,
        if (log.code.isNotEmpty) '${codePath(log.code)}/${side.name}': name,
      };

  /// Adds or edits an entry. Any change cancels earlier confirmations: the
  /// friends must look at the new total again.
  static Map<String, Object?> saveEntry(LedgerLog log, LedgerEntry e, Side me,
      {required bool isNew}) {
    final base = '${logPath(log.id)}/entries/${e.id}';
    return {
      base: {
        'amt': e.amount,
        'by': e.by.name,
        'date': e.date.millisecondsSinceEpoch,
        'tag': e.tag,
        'note': e.note,
        'at': isNew ? serverTime : e.createdAt,
        'cs': isNew ? me.name : (e.createdBy ?? me).name,
        if (!isNew) 'ea': serverTime,
        if (!isNew) 'es': me.name,
      },
      if (log.approvals.isNotEmpty) '${logPath(log.id)}/ok': null,
    };
  }

  static Map<String, Object?> deleteEntry(LedgerLog log, String entryId) => {
        '${logPath(log.id)}/entries/$entryId': null,
        if (log.approvals.isNotEmpty) '${logPath(log.id)}/ok': null,
      };

  /// "This ledger is right." When the friend already confirmed this same
  /// version, the ledger is cleared in the same write.
  static Map<String, Object?> approve(LedgerLog log, Side me) {
    final sig = log.sig;
    final p = logPath(log.id);
    final w = <String, Object?>{
      '$p/ok/${me.name}': {
        'sig': sig,
        'net': netForA(log.entries),
        'at': serverTime
      },
    };
    if (log.approvedBy(me.other)) w.addAll(finalize(log));
    return w;
  }

  /// Clears the ledger. Also used when both friends confirmed the same
  /// version at about the same moment, so neither write cleared it: whoever
  /// sees that first finishes it.
  ///
  /// A cleared ledger has no join code (reopening makes a new one), and the
  /// cleaner's list holds only its id and time, so nothing in that public
  /// list lets anyone in.
  static Map<String, Object?> finalize(LedgerLog log) => {
        '${logPath(log.id)}/done': serverTime,
        gcPath(log.id): {'t': serverTime},
        if (log.code.isNotEmpty) codePath(log.code): null,
        if (log.code.isNotEmpty) '${logPath(log.id)}/meta/code': null,
      };

  /// Takes back my own confirmation before my friend confirms.
  static Map<String, Object?> withdraw(LedgerLog log, Side me) => {
        '${logPath(log.id)}/ok/${me.name}': null,
      };

  /// Opens a cleared ledger again (allowed until it is deleted), with a new
  /// join code.
  static Map<String, Object?> reopen(LedgerLog log, String newCode) => {
        '${logPath(log.id)}/done': null,
        '${logPath(log.id)}/ok': null,
        gcPath(log.id): null,
        codePath(newCode): {'id': log.id, 'a': log.nameA, 'b': log.nameB},
        '${logPath(log.id)}/meta/code': newCode,
      };

  /// Removes the log from the cloud: a cleared one after [settledKeep], or
  /// one with no entries at any time.
  static Map<String, Object?> delete(String id, String code) => {
        logPath(id): null,
        gcPath(id): null,
        if (code.isNotEmpty) codePath(code): null,
      };
}
