import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/logic/job_query.dart';
import 'package:vacancy_bell/models/post.dart';
import 'package:vacancy_bell/models/profile.dart';
import 'package:vacancy_bell/models/taxonomy.dart';

import 'support/fakes.dart';

void main() {
  final today = Ymd(2026, 10, 7);
  final all = fixtureIndex.posts;
  final jobs = all.where((p) => p.type == PostType.job).toList();
  List<String> ids(List<PostSummary> l) => l.map((p) => p.id).toList();
  List<String> run(JobQuery q, {Iterable<PostSummary>? posts, UserProfile profile = UserProfile.empty}) =>
      ids(applyQuery(posts ?? all, q, today: today, profile: profile));

  group('normalizeForSearch', () {
    final cases = {
      'SSC-CGL 2026': 'ssc cgl 2026',
      '  RRB   NTPC  ': 'rrb ntpc',
      'PO/MT': 'po mt',
      'एसएससी सीजीएल': 'एसएससी सीजीएल',
      'Constable (Civil Police)': 'constable civil police',
      '': '',
    };
    cases.forEach((input, want) => test('"$input"', () => expect(normalizeForSearch(input), want)));
    test('tokens', () => expect(searchTokens(' SSC, cgl! '), ['ssc', 'cgl']));
    test('no tokens', () => expect(searchTokens(' - '), isEmpty));
  });

  group('search', () {
    final cases = <(String, List<String>)>[
      ('cgl', ['ssc-cgl-2026-notice', 'ssc-cgl-2026-syllabus']),
      ('CGL notice', ['ssc-cgl-2026-notice']),
      ('ssc-cgl', ['ssc-cgl-2026-notice', 'ssc-cgl-2026-syllabus']),
      ('staff selection gd', ['ssc-gd-constable-2026']),
      ('सीजीएल', ['ssc-cgl-2026-notice', 'ssc-cgl-2026-syllabus']),
      ('कर्मचारी चयन', ['ssc-cgl-2026-notice', 'ssc-gd-constable-2026', 'ssc-chsl-2026-admit-card', 'ssc-cgl-2026-syllabus']),
      ('railway', ['rrb-ntpc-graduate-2026', 'ncr-iti-apprentice-2026', 'rrb-alp-2026-cbt1-result']),
      ('police constable', ['up-police-constable-2026']),
      ('central-govt army', ['indian-army-agniveer-2026']),
      ('upsc', ['upsc-cse-mains-2026-admit-card', 'upsc-exam-calendar-2027']),
      ('xyzzy', []),
    ];
    for (final (q, want) in cases) {
      test('"$q"', () => expect(run(JobQuery(text: q)).toSet(), want.toSet()));
    }
    test('empty text matches everything', () => expect(run(const JobQuery(text: '  ')).length, all.length));
  });

  group('category filter', () {
    for (final c in JobCategory.values) {
      test(c.wire, () {
        final got = applyQuery(all, JobQuery(categories: {c}), today: today);
        expect(got.every((p) => p.category == c), isTrue);
        expect(got.length, all.where((p) => p.category == c).length);
      });
    }
    test('several categories', () {
      final got = applyQuery(all, const JobQuery(categories: {JobCategory.ssc, JobCategory.railway}), today: today);
      expect(got.map((p) => p.category).toSet(), {JobCategory.ssc, JobCategory.railway});
    });
  });

  group('qualification filter', () {
    final cases = <(Set<Qualification>, Set<String>)>[
      ({Qualification.class10}, {'indian-army-agniveer-2026', 'ssc-gd-constable-2026', 'nvs-class-6-admission-2027'}),
      ({Qualification.iti}, {'ncr-iti-apprentice-2026', 'rrb-alp-2026-cbt1-result', 'nvs-class-6-admission-2027'}),
      ({Qualification.engineering}, {'ntpc-engineer-trainee-2026', 'nvs-class-6-admission-2027'}),
      ({Qualification.postgraduate}, {'bihar-stet-2026', 'nvs-class-6-admission-2027'}),
    ];
    for (final (wanted, want) in cases) {
      test(wanted.map((e) => e.wire).join(','), () => expect(run(JobQuery(qualifications: wanted)).toSet(), want));
    }
    test('"any" posts always match', () {
      expect(run(const JobQuery(qualifications: {Qualification.law})), ['nvs-class-6-admission-2027']);
    });
    test('posts without qualifications never match a filter', () {
      expect(run(const JobQuery(qualifications: {Qualification.graduate})), isNot(contains('upsc-exam-calendar-2027')));
    });
  });

  group('state filter', () {
    test('UP keeps all-India posts and UP posts', () {
      final got = applyQuery(all, const JobQuery(state: 'UP'), today: today);
      expect(got.any((p) => p.id == 'up-police-constable-2026'), isTrue);
      expect(got.any((p) => p.id == 'rpsc-ras-2026'), isFalse);
      expect(got.any((p) => p.id == 'bihar-stet-2026'), isFalse);
      expect(got.every((p) => p.openToState('UP')), isTrue);
    });
    test('RJ', () {
      final got = run(const JobQuery(state: 'RJ'));
      expect(got, contains('rpsc-ras-2026'));
      expect(got, isNot(contains('delhi-high-court-jja-2026')));
    });
  });

  group('hide closed', () {
    test('drops past last dates only', () {
      final got = run(const JobQuery(hideClosed: true));
      expect(got, isNot(contains('bihar-stet-2026')));
      expect(got, contains('ibps-po-xv-2026')); // last day today is still open
      expect(got, contains('aiims-nursing-officer-2026')); // unknown last date
    });
  });

  group('only eligible', () {
    final grad = UserProfile(dob: Ymd(2000, 1, 1), qualification: Qualification.graduate, category: SocialCategory.general, gender: Gender.male);
    test('without a profile the switch does nothing', () {
      expect(run(const JobQuery(onlyEligible: true)).length, all.length);
    });
    test('a young graduate keeps 10th-level posts (higher qualification is fine)', () {
      final young = grad.copyWith(dob: () => Ymd(2004, 6, 1));
      final got = run(const JobQuery(onlyEligible: true), posts: jobs, profile: young);
      expect(got, contains('ssc-gd-constable-2026'));
    });
    test('a 26-year-old graduate loses SSC GD (18-23)', () {
      final got = run(const JobQuery(onlyEligible: true), posts: jobs, profile: grad);
      expect(got, isNot(contains('ssc-gd-constable-2026')));
    });
    test('a graduate loses ITI and engineering posts', () {
      final got = run(const JobQuery(onlyEligible: true), posts: jobs, profile: grad);
      expect(got, isNot(contains('ncr-iti-apprentice-2026')));
      expect(got, isNot(contains('ntpc-engineer-trainee-2026')));
    });
    test('a 26-year-old loses the Agniveer post (17-21)', () {
      final got = run(const JobQuery(onlyEligible: true), posts: jobs, profile: grad);
      expect(got, isNot(contains('indian-army-agniveer-2026')));
    });
    test('undecided posts stay visible', () {
      final got = run(const JobQuery(onlyEligible: true), posts: jobs, profile: grad);
      expect(got, contains('ssc-cgl-2026-notice'));
    });
    test('a 10th pass keeps only 10th-level posts', () {
      final p = UserProfile(dob: Ymd(2007, 1, 1), qualification: Qualification.class10, category: SocialCategory.general, gender: Gender.male);
      final got = run(const JobQuery(onlyEligible: true), posts: jobs, profile: p);
      expect(got.toSet(), {'indian-army-agniveer-2026', 'ssc-gd-constable-2026'});
    });
  });

  group('sort newest', () {
    test('by posting time, newest first', () {
      final got = applyQuery(all, const JobQuery(), today: today);
      for (var i = 1; i < got.length; i++) {
        expect(got[i - 1].postedAt!.isBefore(got[i].postedAt!), isFalse);
      }
      expect(got.first.id, 'ssc-cgl-2026-syllabus');
    });
    test('posts without a time go last', () {
      final noTime = PostSummary.tryParse({'id': 'no-time', 'title': 'X'})!;
      final got = applyQuery([noTime, ...jobs], const JobQuery(), today: today);
      expect(got.last.id, 'no-time');
    });
  });

  group('sort closing soon', () {
    final got = applyQuery(all, const JobQuery(sort: SortOrder.closingSoon), today: today);
    test('last day today first', () => expect(got.first.id, 'ibps-po-xv-2026'));
    test('then urgent', () => expect(got[1].id, 'rrb-ntpc-graduate-2026'));
    test('open dates ascend', () {
      final open = got.where((p) => p.lastDate != null && !p.lastDate!.isBefore(today)).toList();
      for (var i = 1; i < open.length; i++) {
        expect(open[i - 1].lastDate!.compareTo(open[i].lastDate!) <= 0, isTrue);
      }
    });
    test('unknown dates after open ones', () {
      final firstUnknown = got.indexWhere((p) => p.lastDate == null);
      final lastOpen = got.lastIndexWhere((p) => p.lastDate != null && !p.lastDate!.isBefore(today));
      expect(firstUnknown, greaterThan(lastOpen));
    });
    test('closed posts last', () => expect(got.last.id, 'bihar-stet-2026'));
  });

  group('combined', () {
    test('ssc + 10th + newest', () {
      expect(run(const JobQuery(categories: {JobCategory.ssc}, qualifications: {Qualification.class10})),
          ['ssc-gd-constable-2026']);
    });
    test('search inside a category', () {
      expect(run(const JobQuery(text: '2026', categories: {JobCategory.banking})).toSet(),
          {'ibps-po-xv-2026', 'ibps-clerk-2026-prelims-result'});
    });
  });

  group('JobQuery bookkeeping', () {
    test('activeFilters counts each kind once', () {
      const q = JobQuery(
        categories: {JobCategory.ssc, JobCategory.upsc},
        qualifications: {Qualification.graduate},
        state: 'UP',
        onlyEligible: true,
        hideClosed: true,
      );
      expect(q.activeFilters, 5);
    });
    test('default', () {
      expect(JobQuery.none.isDefault, isTrue);
      expect(const JobQuery(text: 'x').isDefault, isFalse);
      expect(const JobQuery(sort: SortOrder.closingSoon).isDefault, isFalse);
    });
    test('cleared keeps text only', () {
      final q = const JobQuery(text: 'cgl', state: 'UP', categories: {JobCategory.ssc}).cleared();
      expect(q.text, 'cgl');
      expect(q.activeFilters, 0);
    });
    test('copyWith can clear the state', () {
      expect(const JobQuery(state: 'UP').copyWith(state: () => null).state, isNull);
    });
  });
}
