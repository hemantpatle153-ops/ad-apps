/// Eligibility check: qualification and age against a post.
///
/// The rule throughout: the app may only say "You're eligible" when every
/// fact it needs is known. Anything uncertain (no "as on" date, a state's own
/// relaxation rules, ex-servicemen rules, equivalent qualifications) gives
/// [Verdict.unknown], shown as "Check the notice". "Not eligible" is shown
/// only when no plausible reading of the notice could make the user eligible.
library;

import '../core/ymd.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/taxonomy.dart';

enum Verdict { yes, no, unknown }

enum AgeProblem { tooYoung, tooOld }

/// What the engine needs to know about a post.
class EligibilityInput {
  const EligibilityInput({
    required this.qualifications,
    this.ageMin,
    this.ageMax,
    this.asOn,
    this.centralRules = false,
    this.windowStart,
    this.windowEnd,
  });

  /// Any one of these is enough. Empty = the feed did not say.
  final List<Qualification> qualifications;
  final int? ageMin;
  final int? ageMax;

  /// The date age is counted on. Without it the engine can still rule out
  /// someone who is too old or too young on every date in the window.
  final Ymd? asOn;

  /// Standard central government relaxations apply (SSC, UPSC, railways or
  /// tagged `central-govt`).
  final bool centralRules;
  final Ymd? windowStart;
  final Ymd? windowEnd;

  /// Days before the posting date an "as on" date can plausibly be.
  static const windowBefore = 366;

  /// Days after the last date an "as on" date can plausibly be.
  static const windowAfter = 366;

  factory EligibilityInput.fromSummary(PostSummary p) {
    final posted = p.postedAt == null ? null : Ymd.istOf(p.postedAt!);
    final last = p.lastDate ?? posted;
    return EligibilityInput(
      qualifications: p.qualifications,
      ageMin: p.ageMin,
      ageMax: p.ageMax,
      centralRules: p.followsCentralRules,
      windowStart: posted?.addDays(-windowBefore),
      windowEnd: last?.addDays(windowAfter),
    );
  }

  factory EligibilityInput.fromDetail(PostDetail d) {
    final base = EligibilityInput.fromSummary(d.summary);
    return EligibilityInput(
      qualifications: base.qualifications,
      ageMin: d.ageMin,
      ageMax: d.ageMax,
      asOn: d.age.asOn,
      centralRules: base.centralRules,
      windowStart: base.windowStart,
      windowEnd: base.windowEnd,
    );
  }
}

class EligibilityResult {
  const EligibilityResult({
    required this.overall,
    required this.qualification,
    required this.age,
    this.ageProblem,
    this.ageOnDate,
    this.relaxationYears = 0,
    this.usedRelaxation = false,
    this.profileMissing = false,
  });

  final Verdict overall;
  final Verdict qualification;
  final Verdict age;
  final AgeProblem? ageProblem;

  /// Completed years on the "as on" date, when known.
  final int? ageOnDate;

  /// Upper age relaxation applied for the user's category (central rules).
  final int relaxationYears;

  /// True when the user is only within the limit thanks to relaxation.
  final bool usedRelaxation;

  /// No details saved: nothing was checked.
  final bool profileMissing;

  static const notChecked = EligibilityResult(
    overall: Verdict.unknown,
    qualification: Verdict.unknown,
    age: Verdict.unknown,
    profileMissing: true,
  );

  bool get isEligible => overall == Verdict.yes;
  bool get isNotEligible => overall == Verdict.no;
}

/// Standard central government upper-age relaxation in years.
/// OBC 3, SC/ST 5; persons with benchmark disability 10 more (so 10, 13, 15).
/// Ex-servicemen rules depend on service length and are not counted here.
int centralRelaxationYears(UserProfile p) {
  final base = switch (p.category) {
    SocialCategory.obc => 3,
    SocialCategory.sc || SocialCategory.st => 5,
    _ => 0,
  };
  return base + (p.pwbd ? 10 : 0);
}

/// Whether a user with [level] as highest qualification meets [required].
Verdict qualificationMeets(Qualification level, Qualification required) {
  const degrees = {
    Qualification.graduate,
    Qualification.engineering,
    Qualification.medical,
    Qualification.law,
    Qualification.postgraduate,
  };
  switch (required) {
    case Qualification.any:
    case Qualification.class8:
      return Verdict.yes;
    case Qualification.class10:
      return level == Qualification.class8 ? Verdict.no : Verdict.yes;
    case Qualification.class12:
      if (level == Qualification.class12 || degrees.contains(level)) {
        return Verdict.yes;
      }
      // Some notices accept a 3-year diploma as equal to 12th, many don't.
      if (level == Qualification.diploma) return Verdict.unknown;
      return Verdict.no;
    case Qualification.iti:
      if (level == Qualification.iti) return Verdict.yes;
      // A higher technical qualification is sometimes accepted.
      if (level == Qualification.diploma || level == Qualification.engineering) {
        return Verdict.unknown;
      }
      return Verdict.no;
    case Qualification.diploma:
      if (level == Qualification.diploma) return Verdict.yes;
      if (level == Qualification.engineering) return Verdict.unknown;
      return Verdict.no;
    case Qualification.graduate:
      return degrees.contains(level) ? Verdict.yes : Verdict.no;
    case Qualification.engineering:
    case Qualification.medical:
    case Qualification.law:
      if (level == required) return Verdict.yes;
      // A postgraduate may hold this degree too; we don't know which.
      if (level == Qualification.postgraduate) return Verdict.unknown;
      return Verdict.no;
    case Qualification.postgraduate:
      return level == Qualification.postgraduate ? Verdict.yes : Verdict.no;
  }
}

/// Best verdict over a post's alternative qualifications.
Verdict qualificationVerdict(Qualification? level, List<Qualification> required) {
  if (level == null || required.isEmpty) return Verdict.unknown;
  var best = Verdict.no;
  for (final r in required) {
    final v = qualificationMeets(level, r);
    if (v == Verdict.yes) return Verdict.yes;
    if (v == Verdict.unknown) best = Verdict.unknown;
  }
  return best;
}

/// Whether the user might get an upper-age relaxation the engine can't
/// compute (state rules for women, reserved categories, disability or
/// ex-servicemen).
bool _mayHaveOtherRelaxation(UserProfile p) =>
    p.exServiceman ||
    p.pwbd ||
    p.gender != Gender.male ||
    (p.category != null &&
        p.category != SocialCategory.general &&
        p.category != SocialCategory.ews) ||
    p.category == null;

class _AgeOutcome {
  const _AgeOutcome(this.verdict,
      {this.problem, this.ageOnDate, this.relax = 0, this.usedRelax = false});
  final Verdict verdict;
  final AgeProblem? problem;
  final int? ageOnDate;
  final int relax;
  final bool usedRelax;
}

_AgeOutcome _ageVerdict(UserProfile p, EligibilityInput post) {
  final dob = p.dob;
  if (dob == null) return const _AgeOutcome(Verdict.unknown);
  final min = post.ageMin;
  final max = post.ageMax;
  if (min == null && max == null) return const _AgeOutcome(Verdict.unknown);
  final relax = post.centralRules ? centralRelaxationYears(p) : 0;
  // Is a user over the plain limit possibly still allowed?
  final tooOldIsCertain = post.centralRules
      ? !p.exServiceman && p.category != null
      : !_mayHaveOtherRelaxation(p);

  final asOn = post.asOn;
  if (asOn != null) {
    final age = AgeSpan.completedYears(dob, asOn);
    if (min != null && age < min) {
      return _AgeOutcome(Verdict.no,
          problem: AgeProblem.tooYoung, ageOnDate: age, relax: relax);
    }
    var verdict = Verdict.yes;
    var used = false;
    if (max != null && age > max) {
      if (age <= max + relax) {
        used = true;
      } else if (tooOldIsCertain) {
        return _AgeOutcome(Verdict.no,
            problem: AgeProblem.tooOld, ageOnDate: age, relax: relax);
      } else {
        verdict = Verdict.unknown;
      }
    }
    // A missing limit on either side leaves the answer open.
    if (verdict == Verdict.yes && (min == null || max == null)) {
      verdict = Verdict.unknown;
    }
    return _AgeOutcome(verdict, ageOnDate: age, relax: relax, usedRelax: used);
  }

  // No "as on" date: only certain failures can be reported.
  final start = post.windowStart;
  final end = post.windowEnd;
  if (start == null || end == null) {
    return _AgeOutcome(Verdict.unknown, relax: relax);
  }
  if (max != null && tooOldIsCertain) {
    final youngest = AgeSpan.completedYears(dob, start);
    if (youngest > max + relax) {
      return _AgeOutcome(Verdict.no, problem: AgeProblem.tooOld, relax: relax);
    }
  }
  if (min != null) {
    final oldest = AgeSpan.completedYears(dob, end);
    if (oldest < min) {
      return _AgeOutcome(Verdict.no, problem: AgeProblem.tooYoung, relax: relax);
    }
  }
  return _AgeOutcome(Verdict.unknown, relax: relax);
}

EligibilityResult checkEligibility(UserProfile profile, EligibilityInput post) {
  if (!profile.canCheckEligibility) return EligibilityResult.notChecked;
  final q = qualificationVerdict(profile.qualification, post.qualifications);
  final a = _ageVerdict(profile, post);
  final overall = (q == Verdict.no || a.verdict == Verdict.no)
      ? Verdict.no
      : (q == Verdict.yes && a.verdict == Verdict.yes)
          ? Verdict.yes
          : Verdict.unknown;
  return EligibilityResult(
    overall: overall,
    qualification: q,
    age: a.verdict,
    ageProblem: a.problem,
    ageOnDate: a.ageOnDate,
    relaxationYears: a.relax,
    usedRelaxation: a.usedRelax,
  );
}

EligibilityResult eligibilityForSummary(UserProfile p, PostSummary s) =>
    checkEligibility(p, EligibilityInput.fromSummary(s));

EligibilityResult eligibilityForDetail(UserProfile p, PostDetail d) =>
    checkEligibility(p, EligibilityInput.fromDetail(d));
