import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/logic/eligibility.dart';
import 'package:vacancy_bell/models/profile.dart';
import 'package:vacancy_bell/models/taxonomy.dart';

import 'support/fakes.dart';

const Y = Verdict.yes, N = Verdict.no, U = Verdict.unknown;

Ymd d(String s) => Ymd.tryParse(s)!;

UserProfile person(
  String? dob, {
  Qualification? q = Qualification.graduate,
  SocialCategory? cat = SocialCategory.general,
  bool pwbd = false,
  bool esm = false,
  Gender? gender = Gender.male,
}) =>
    UserProfile(
      dob: dob == null ? null : d(dob),
      qualification: q,
      category: cat,
      pwbd: pwbd,
      exServiceman: esm,
      gender: gender,
    );

void main() {
  group('qualification matrix (user level x required)', () {
    // Columns: 8th 10th 12th iti diploma graduate engineering medical law postgraduate any
    const table = {
      Qualification.class8: 'YNNNNNNNNNY',
      Qualification.class10: 'YYNNNNNNNNY',
      Qualification.class12: 'YYYNNNNNNNY',
      Qualification.iti: 'YYNYNNNNNNY',
      Qualification.diploma: 'YYUUYNNNNNY',
      Qualification.graduate: 'YYYNNYNNNNY',
      Qualification.engineering: 'YYYUUYYNNNY',
      Qualification.medical: 'YYYNNYNYNNY',
      Qualification.law: 'YYYNNYNNYNY',
      Qualification.postgraduate: 'YYYNNYUUUYY',
    };
    const cols = [
      Qualification.class8,
      Qualification.class10,
      Qualification.class12,
      Qualification.iti,
      Qualification.diploma,
      Qualification.graduate,
      Qualification.engineering,
      Qualification.medical,
      Qualification.law,
      Qualification.postgraduate,
      Qualification.any,
    ];
    table.forEach((level, row) {
      for (var i = 0; i < cols.length; i++) {
        final want = switch (row[i]) { 'Y' => Y, 'N' => N, _ => U };
        test('${level.wire} for ${cols[i].wire} -> ${want.name}',
            () => expect(qualificationMeets(level, cols[i]), want));
      }
    });
  });

  group('qualificationVerdict over alternatives', () {
    final cases = <(Qualification?, List<Qualification>, Verdict)>[
      (Qualification.graduate, [Qualification.graduate], Y),
      (Qualification.class12, [Qualification.graduate], N),
      (Qualification.class12, [Qualification.graduate, Qualification.class12], Y),
      (Qualification.diploma, [Qualification.graduate, Qualification.diploma], Y),
      (Qualification.diploma, [Qualification.class12], U),
      (Qualification.diploma, [Qualification.graduate, Qualification.class12], U),
      (Qualification.engineering, [Qualification.iti, Qualification.medical], U),
      (Qualification.class10, [Qualification.iti, Qualification.diploma], N),
      (Qualification.class8, [Qualification.any], Y),
      (null, [Qualification.graduate], U),
      (Qualification.graduate, [], U),
      (null, [], U),
    ];
    for (final (level, req, want) in cases) {
      test('${level?.wire} vs ${req.map((e) => e.wire)}', () => expect(qualificationVerdict(level, req), want));
    }
  });

  group('central relaxation years', () {
    final cases = <(SocialCategory?, bool, int)>[
      (SocialCategory.general, false, 0),
      (SocialCategory.ews, false, 0),
      (SocialCategory.obc, false, 3),
      (SocialCategory.sc, false, 5),
      (SocialCategory.st, false, 5),
      (SocialCategory.general, true, 10),
      (SocialCategory.ews, true, 10),
      (SocialCategory.obc, true, 13),
      (SocialCategory.sc, true, 15),
      (SocialCategory.st, true, 15),
      (null, false, 0),
      (null, true, 10),
    ];
    for (final (cat, pwbd, years) in cases) {
      test('${cat?.wire ?? "unknown"}${pwbd ? " + PwBD" : ""} = $years',
          () => expect(centralRelaxationYears(UserProfile(category: cat, pwbd: pwbd)), years));
    }
    test('ex-servicemen get no automatic relaxation', () {
      expect(centralRelaxationYears(const UserProfile(category: SocialCategory.general, exServiceman: true)), 0);
    });
  });

  group('age on the "as on" date, central rules (SSC CGL 18-32 as on 2026-08-01)', () {
    final post = EligibilityInput(
      qualifications: const [Qualification.graduate],
      ageMin: 18,
      ageMax: 32,
      asOn: d('2026-08-01'),
      centralRules: true,
    );
    final cases = <(String, UserProfile, Verdict, AgeProblem?, bool)>[
      ('26 general', person('2000-01-01'), Y, null, false),
      ('31 general', person('1994-08-02'), Y, null, false),
      ('exactly 32 general', person('1994-08-01'), Y, null, false),
      ('32 and a day general', person('1994-07-31'), Y, null, false),
      ('33 general', person('1993-08-01'), N, AgeProblem.tooOld, false),
      ('33 EWS', person('1993-08-01', cat: SocialCategory.ews), N, AgeProblem.tooOld, false),
      ('33 woman general', person('1993-08-01', gender: Gender.female), N, AgeProblem.tooOld, false),
      ('33 OBC', person('1993-08-01', cat: SocialCategory.obc), Y, null, true),
      ('35 OBC', person('1991-08-01', cat: SocialCategory.obc), Y, null, true),
      ('36 OBC', person('1990-08-01', cat: SocialCategory.obc), N, AgeProblem.tooOld, false),
      ('36 SC', person('1990-08-01', cat: SocialCategory.sc), Y, null, true),
      ('37 ST', person('1989-08-01', cat: SocialCategory.st), Y, null, true),
      ('38 SC', person('1988-08-01', cat: SocialCategory.sc), N, AgeProblem.tooOld, false),
      ('42 general PwBD', person('1984-08-01', pwbd: true), Y, null, true),
      ('43 general PwBD', person('1983-08-01', pwbd: true), N, AgeProblem.tooOld, false),
      ('45 OBC PwBD', person('1981-08-01', cat: SocialCategory.obc, pwbd: true), Y, null, true),
      ('46 OBC PwBD', person('1980-08-01', cat: SocialCategory.obc, pwbd: true), N, AgeProblem.tooOld, false),
      ('47 SC PwBD', person('1979-08-01', cat: SocialCategory.sc, pwbd: true), Y, null, true),
      ('48 ST PwBD', person('1978-08-01', cat: SocialCategory.st, pwbd: true), N, AgeProblem.tooOld, false),
      ('36 ex-serviceman: check notice', person('1990-08-01', esm: true), U, null, false),
      ('30 ex-serviceman is within the plain limit', person('1996-01-01', esm: true), Y, null, false),
      ('36 category not given: check notice', person('1990-08-01', cat: null), U, null, false),
      ('30 category not given is within the plain limit', person('1996-01-01', cat: null), Y, null, false),
      ('17 general', person('2008-08-02'), N, AgeProblem.tooYoung, false),
      ('17 SC: no relaxation on the minimum', person('2008-08-02', cat: SocialCategory.sc), N, AgeProblem.tooYoung, false),
      ('exactly 18', person('2008-08-01'), Y, null, false),
      ('born on 29 Feb', person('2000-02-29'), Y, null, false),
    ];
    for (final (name, p, want, problem, relaxed) in cases) {
      test(name, () {
        final r = checkEligibility(p, post);
        expect(r.age, want);
        expect(r.ageProblem, problem);
        expect(r.usedRelaxation, relaxed);
        if (want != U) expect(r.ageOnDate, isNotNull);
      });
    }
    test('reports the age on the date', () {
      expect(checkEligibility(person('2000-01-01'), post).ageOnDate, 26);
    });
    test('reports the relaxation for the category', () {
      expect(checkEligibility(person('1990-08-01', cat: SocialCategory.sc), post).relaxationYears, 5);
    });
  });

  group('state rules (UP Police 18-22 as on 2027-01-01): only certain answers', () {
    final post = EligibilityInput(
      qualifications: const [Qualification.class12],
      ageMin: 18,
      ageMax: 22,
      asOn: d('2027-01-01'),
      centralRules: false,
    );
    final cases = <(String, UserProfile, Verdict, AgeProblem?)>[
      ('21 general man', person('2006-01-01', q: Qualification.class12), Y, null),
      ('22 general man', person('2004-01-02', q: Qualification.class12), Y, null),
      ('23 general man', person('2004-01-01', q: Qualification.class12), N, AgeProblem.tooOld),
      ('23 EWS man', person('2004-01-01', q: Qualification.class12, cat: SocialCategory.ews), N, AgeProblem.tooOld),
      ('23 woman', person('2004-01-01', q: Qualification.class12, gender: Gender.female), U, null),
      ('23 gender not given', person('2004-01-01', q: Qualification.class12, gender: null), U, null),
      ('23 OBC man', person('2004-01-01', q: Qualification.class12, cat: SocialCategory.obc), U, null),
      ('23 SC man', person('2004-01-01', q: Qualification.class12, cat: SocialCategory.sc), U, null),
      ('23 category not given', person('2004-01-01', q: Qualification.class12, cat: null), U, null),
      ('23 PwBD man', person('2004-01-01', q: Qualification.class12, pwbd: true), U, null),
      ('23 ex-serviceman', person('2004-01-01', q: Qualification.class12, esm: true), U, null),
      ('17', person('2009-01-02', q: Qualification.class12), N, AgeProblem.tooYoung),
      ('17 woman (no minimum relaxation)', person('2009-01-02', q: Qualification.class12, gender: Gender.female), N, AgeProblem.tooYoung),
    ];
    for (final (name, p, want, problem) in cases) {
      test(name, () {
        final r = checkEligibility(p, post);
        expect(r.age, want);
        expect(r.ageProblem, problem);
        expect(r.relaxationYears, 0);
      });
    }
  });

  group('missing age limits never give a false "eligible"', () {
    final asOn = d('2026-08-01');
    final cases = <(int?, int?, String?, Verdict, AgeProblem?)>[
      (null, 30, '2000-01-01', U, null),
      (null, 30, '1990-01-01', N, AgeProblem.tooOld),
      (18, null, '2000-01-01', U, null),
      (18, null, '2010-01-01', N, AgeProblem.tooYoung),
      (null, null, '2000-01-01', U, null),
      (18, 32, null, U, null),
    ];
    for (final (min, max, dob, want, problem) in cases) {
      test('min $min max $max dob $dob', () {
        final r = checkEligibility(
          person(dob),
          EligibilityInput(
              qualifications: const [Qualification.graduate],
              ageMin: min,
              ageMax: max,
              asOn: asOn,
              centralRules: true),
        );
        expect(r.age, want);
        expect(r.ageProblem, problem);
      });
    }
  });

  group('no "as on" date: only certain failures (window check)', () {
    // Posted 2026-10-07, last date 2026-11-05: window 2025-10-06 .. 2027-11-06.
    EligibilityInput post({int? min = 18, int? max = 32, bool central = true}) => EligibilityInput(
          qualifications: const [Qualification.graduate],
          ageMin: min,
          ageMax: max,
          centralRules: central,
          windowStart: d('2026-10-07').addDays(-EligibilityInput.windowBefore),
          windowEnd: d('2026-11-05').addDays(EligibilityInput.windowAfter),
        );
    final cases = <(String, UserProfile, EligibilityInput, Verdict, AgeProblem?)>[
      ('25: still unknown, never yes', person('2001-05-01'), post(), U, null),
      ('far too old', person('1990-01-01'), post(), N, AgeProblem.tooOld),
      ('just too old at the earliest date', person('1992-01-01'), post(), N, AgeProblem.tooOld),
      ('could be 32 on an early date', person('1993-10-07'), post(), U, null),
      ('OBC 35 at the earliest date', person('1990-01-01', cat: SocialCategory.obc), post(), U, null),
      ('OBC 36 at the earliest date', person('1989-01-01', cat: SocialCategory.obc), post(), N, AgeProblem.tooOld),
      ('ex-serviceman far too old: unknown', person('1980-01-01', esm: true), post(), U, null),
      ('far too young', person('2012-01-01'), post(), N, AgeProblem.tooYoung),
      ('just too young at the latest date', person('2010-01-01'), post(), N, AgeProblem.tooYoung),
      ('18 at the latest date', person('2009-11-06'), post(), U, null),
      ('state post, woman far over: unknown', person('1980-01-01', gender: Gender.female), post(max: 40, central: false), U, null),
      ('state post, man far over: no', person('1980-01-01'), post(max: 40, central: false), N, AgeProblem.tooOld),
    ];
    for (final (name, p, input, want, problem) in cases) {
      test(name, () {
        final r = checkEligibility(p, input);
        expect(r.age, want);
        expect(r.ageProblem, problem);
      });
    }
    test('no posting date: unknown', () {
      final r = checkEligibility(person('1960-01-01'),
          const EligibilityInput(qualifications: [Qualification.graduate], ageMin: 18, ageMax: 32, centralRules: true));
      expect(r.age, U);
    });
  });

  group('overall verdict', () {
    final asOn = d('2026-08-01');
    EligibilityInput post(List<Qualification> q) =>
        EligibilityInput(qualifications: q, ageMin: 18, ageMax: 32, asOn: asOn, centralRules: true);
    final cases = <(String, UserProfile, EligibilityInput, Verdict)>[
      ('both yes', person('2000-01-01'), post([Qualification.graduate]), Y),
      ('qualification no', person('2000-01-01', q: Qualification.class12), post([Qualification.graduate]), N),
      ('age no', person('1980-01-01'), post([Qualification.graduate]), N),
      ('qualification unknown, age yes', person('2000-01-01', q: Qualification.diploma), post([Qualification.class12]), U),
      ('qualification unknown, age no', person('1980-01-01', q: Qualification.diploma), post([Qualification.class12]), N),
      ('no qualification given, age yes', person('2000-01-01', q: null), post([Qualification.graduate]), U),
      ('no dob, qualification yes', person(null), post([Qualification.graduate]), U),
      ('no dob, qualification no', person(null, q: Qualification.class10), post([Qualification.graduate]), N),
      ('post lists no qualification', person('2000-01-01'), post(const []), U),
    ];
    for (final (name, p, input, want) in cases) {
      test(name, () => expect(checkEligibility(p, input).overall, want));
    }
    test('empty profile is not checked', () {
      final r = checkEligibility(UserProfile.empty, post([Qualification.graduate]));
      expect(r.profileMissing, isTrue);
      expect(r.overall, U);
      expect(r.isEligible, isFalse);
      expect(r.isNotEligible, isFalse);
    });
    test('state and gender alone are not enough to check', () {
      const p = UserProfile(state: 'UP', gender: Gender.female);
      expect(checkEligibility(p, post([Qualification.graduate])).profileMissing, isTrue);
    });
  });

  group('oracle: every age x category x PwBD on a central 18-32 post', () {
    final asOn = d('2026-08-01');
    final post = EligibilityInput(
        qualifications: const [Qualification.graduate], ageMin: 18, ageMax: 32, asOn: asOn, centralRules: true);
    const relax = {
      SocialCategory.general: 0,
      SocialCategory.ews: 0,
      SocialCategory.obc: 3,
      SocialCategory.sc: 5,
      SocialCategory.st: 5,
    };
    for (var age = 15; age <= 49; age++) {
      for (final cat in SocialCategory.values) {
        for (final pwbd in [false, true]) {
          final limit = 32 + relax[cat]! + (pwbd ? 10 : 0);
          final want = age < 18 ? N : (age <= limit ? Y : N);
          test('age $age ${cat.wire}${pwbd ? " PwBD" : ""} -> ${want.name}', () {
            // Born on the "as on" date, [age] years earlier.
            final dob = Ymd(asOn.year - age, asOn.month, asOn.day);
            final r = checkEligibility(person(dob.toString(), cat: cat, pwbd: pwbd), post);
            expect(r.ageOnDate, age);
            expect(r.overall, want);
            expect(r.usedRelaxation, want == Y && age > 32);
          });
        }
      }
    }
  });

  group('never "eligible" from the list alone (no as-on date)', () {
    final index = fixtureIndex;
    final profiles = [
      person('2000-01-01'),
      person('2004-06-15', q: Qualification.class12, cat: SocialCategory.obc),
      person('1996-03-03', q: Qualification.engineering, cat: SocialCategory.sc, pwbd: true),
      person('2007-01-01', q: Qualification.class10),
      person('1999-09-09', q: Qualification.iti, esm: true),
    ];
    for (final p in index.posts) {
      test(p.id, () {
        for (final prof in profiles) {
          expect(eligibilityForSummary(prof, p).overall, isNot(Verdict.yes));
        }
      });
    }
  });

  group('fixture details', () {
    test('SSC CGL: 26-year-old graduate is eligible', () {
      final r = eligibilityForDetail(person('2000-01-01'), fixturePost('ssc-cgl-2026-notice'));
      expect(r.overall, Y);
    });
    test('SSC CGL: 12th pass is not', () {
      final r = eligibilityForDetail(person('2000-01-01', q: Qualification.class12), fixturePost('ssc-cgl-2026-notice'));
      expect(r.overall, N);
      expect(r.qualification, N);
    });
    test('SSC CGL: 34-year-old SC graduate is eligible with relaxation', () {
      final r = eligibilityForDetail(person('1992-01-01', cat: SocialCategory.sc), fixturePost('ssc-cgl-2026-notice'));
      expect(r.overall, Y);
      expect(r.usedRelaxation, isTrue);
    });
    test('UP Police: 23-year-old OBC must check the notice', () {
      final r = eligibilityForDetail(
          person('2003-06-01', q: Qualification.class12, cat: SocialCategory.obc), fixturePost('up-police-constable-2026'));
      expect(r.overall, U);
    });
    test('RRB NTPC: no as-on date in detail, so unknown', () {
      final r = eligibilityForDetail(person('2000-01-01'), fixturePost('rrb-ntpc-graduate-2026'));
      expect(r.overall, U);
    });
  });
}
