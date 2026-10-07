import '../core/json_read.dart';
import '../core/ymd.dart';
import 'taxonomy.dart';

enum SocialCategory {
  general('general'),
  obc('obc'),
  sc('sc'),
  st('st'),
  ews('ews');

  const SocialCategory(this.wire);
  final String wire;

  static SocialCategory? tryParse(Object? v) {
    for (final c in values) {
      if (c.wire == v) return c;
    }
    return null;
  }
}

enum Gender {
  male('male'),
  female('female'),
  other('other');

  const Gender(this.wire);
  final String wire;

  static Gender? tryParse(Object? v) {
    for (final g in values) {
      if (g.wire == v) return g;
    }
    return null;
  }
}

/// "My details": optional, stored only on the phone, used for the
/// eligibility check and alert matching. Every field may be unset.
class UserProfile {
  const UserProfile({
    this.dob,
    this.qualification,
    this.category,
    this.pwbd = false,
    this.exServiceman = false,
    this.state,
    this.gender,
  });

  final Ymd? dob;

  /// Highest qualification ([Qualification.any] is never stored).
  final Qualification? qualification;
  final SocialCategory? category;

  /// Person with benchmark disability.
  final bool pwbd;
  final bool exServiceman;

  /// Home state code (see [indianStates]).
  final String? state;
  final Gender? gender;

  static const empty = UserProfile();

  bool get isEmpty =>
      dob == null &&
      qualification == null &&
      category == null &&
      !pwbd &&
      !exServiceman &&
      state == null &&
      gender == null;

  /// Enough to say anything about eligibility.
  bool get canCheckEligibility => dob != null || qualification != null;

  UserProfile copyWith({
    Ymd? Function()? dob,
    Qualification? Function()? qualification,
    SocialCategory? Function()? category,
    bool? pwbd,
    bool? exServiceman,
    String? Function()? state,
    Gender? Function()? gender,
  }) =>
      UserProfile(
        dob: dob != null ? dob() : this.dob,
        qualification:
            qualification != null ? qualification() : this.qualification,
        category: category != null ? category() : this.category,
        pwbd: pwbd ?? this.pwbd,
        exServiceman: exServiceman ?? this.exServiceman,
        state: state != null ? state() : this.state,
        gender: gender != null ? gender() : this.gender,
      );

  Map<String, Object?> toJson() => {
        if (dob != null) 'dob': dob.toString(),
        if (qualification != null) 'qualification': qualification!.wire,
        if (category != null) 'category': category!.wire,
        if (pwbd) 'pwbd': true,
        if (exServiceman) 'exServiceman': true,
        if (state != null) 'state': state,
        if (gender != null) 'gender': gender!.wire,
      };

  /// Reads a stored profile; unreadable fields are left unset.
  static UserProfile fromJson(Object? json) {
    final m = readMap(json);
    if (m == null) return empty;
    var q = Qualification.tryParse(m['qualification']);
    if (q == Qualification.any) q = null;
    final st = parseStateCode(m['state']);
    return UserProfile(
      dob: readYmd(m['dob']),
      qualification: q,
      category: SocialCategory.tryParse(m['category']),
      pwbd: readBool(m['pwbd']),
      exServiceman: readBool(m['exServiceman']),
      state: st == allStates ? null : st,
      gender: Gender.tryParse(m['gender']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.dob == dob &&
      other.qualification == qualification &&
      other.category == category &&
      other.pwbd == pwbd &&
      other.exServiceman == exServiceman &&
      other.state == state &&
      other.gender == gender;

  @override
  int get hashCode =>
      Object.hash(dob, qualification, category, pwbd, exServiceman, state, gender);
}
