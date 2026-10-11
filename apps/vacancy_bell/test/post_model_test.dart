import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vacancy_bell/core/json_read.dart';
import 'package:vacancy_bell/core/ymd.dart';
import 'package:vacancy_bell/models/feed_index.dart';
import 'package:vacancy_bell/models/post.dart';
import 'package:vacancy_bell/models/taxonomy.dart';

import 'support/fakes.dart';

Map<String, Object?> _base() => {
      'id': 'test-post',
      'type': 'job',
      'title': {'en': 'Test post', 'hi': 'परीक्षण'},
      'org': {'en': 'Org', 'hi': 'संस्था'},
      'category': 'ssc',
      'postedAt': '2026-10-07T05:00:00Z',
      'lastDate': '2026-11-05',
      'totalPosts': 100,
      'qualifications': ['graduate'],
      'states': ['all'],
      'ageMin': 18,
      'ageMax': 32,
      'tags': ['central-govt'],
      'verified': true,
    };

void main() {
  group('fixture index', () {
    final index = fixtureIndex;

    test('reads all 20 posts', () => expect(index.posts.length, 20));
    test('nothing skipped', () => expect(index.skipped, 0));
    test('schema', () => expect(index.schema, 1));
    test('generatedAt', () => expect(index.generatedAt, DateTime.utc(2026, 10, 7, 11, 30)));
    test('ids are unique', () => expect(index.posts.map((p) => p.id).toSet().length, 20));
    test('keeps feed order', () => expect(index.posts.first.id, 'ssc-cgl-2026-notice'));
    test('byId finds a post', () => expect(index.byId('rpsc-ras-2026')!.states, ['RJ']));
    test('byId of unknown id is null', () => expect(index.byId('nope'), isNull));

    final counts = {
      PostType.job: 12,
      PostType.admitCard: 2,
      PostType.result: 2,
      PostType.answerKey: 1,
      PostType.syllabus: 1,
      PostType.admission: 1,
      PostType.notice: 1,
    };
    counts.forEach((type, n) {
      test('$n posts of type ${type.wire}',
          () => expect(index.posts.where((p) => p.type == type).length, n));
    });

    test('SSC CGL fields', () {
      final p = index.byId('ssc-cgl-2026-notice')!;
      expect(p.title.en, 'SSC CGL 2026 Recruitment');
      expect(p.title.hi, 'एसएससी सीजीएल 2026 भर्ती');
      expect(p.org.en, 'Staff Selection Commission');
      expect(p.category, JobCategory.ssc);
      expect(p.source, 'ssc');
      expect(p.lastDate, Ymd(2026, 11, 5));
      expect(p.totalPosts, 14582);
      expect(p.qualifications, [Qualification.graduate]);
      expect(p.states, [allStates]);
      expect((p.ageMin, p.ageMax), (18, 32));
      expect(p.salary!.en, contains('Level 4-8'));
      expect(p.tags, ['central-govt']);
      expect(p.verified, isTrue);
      expect(p.postedAt, DateTime.utc(2026, 10, 7, 5, 12));
      expect(p.updatedAt, DateTime.utc(2026, 10, 7, 9, 12));
    });

    test('null fields stay null', () {
      final p = index.byId('aiims-nursing-officer-2026')!;
      expect(p.lastDate, isNull);
      expect(p.totalPosts, isNull);
      expect(p.salary, isNull);
    });

    test('missing ages on admit card are null', () {
      final p = index.byId('upsc-cse-mains-2026-admit-card')!;
      expect((p.ageMin, p.ageMax), (null, null));
    });

    test('state code list', () {
      expect(index.byId('up-police-constable-2026')!.states, ['UP']);
    });

    test('central rules for SSC, UPSC, railway and central-govt tags', () {
      expect(index.byId('ssc-gd-constable-2026')!.followsCentralRules, isTrue);
      expect(index.byId('rrb-ntpc-graduate-2026')!.followsCentralRules, isTrue);
      expect(index.byId('aiims-nursing-officer-2026')!.followsCentralRules, isTrue);
      expect(index.byId('up-police-constable-2026')!.followsCentralRules, isFalse);
      expect(index.byId('rpsc-ras-2026')!.followsCentralRules, isFalse);
      expect(index.byId('ibps-po-xv-2026')!.followsCentralRules, isFalse);
    });
  });

  group('every fixture summary round-trips through toJson', () {
    for (final p in fixtureIndex.posts) {
      test(p.id, () {
        final again = PostSummary.tryParse(jsonDecode(jsonEncode(p.toJson())))!;
        expect(jsonEncode(again.toJson()), jsonEncode(p.toJson()));
        expect(again.lastDate, p.lastDate);
        expect(again.qualifications, p.qualifications);
        expect(again.postedAt, p.postedAt);
      });
    }
  });

  group('malformed index', () {
    final index = FeedIndex.parse(fixture('malformed_index.json'));

    test('keeps only the valid entries', () {
      expect(index.posts.map((p) => p.id), ['good-minimal', 'good-weird-fields', 'good-states-only']);
    });
    test('counts the skipped ones', () => expect(index.skipped, 11));
    test('bad generatedAt is null', () => expect(index.generatedAt, isNull));
    test('first duplicate wins', () => expect(index.byId('good-minimal')!.title.en, 'Plain string title'));

    test('weird fields fall back safely', () {
      final p = index.byId('good-weird-fields')!;
      expect(p.type, PostType.notice);
      expect(p.title.of(AppLang.hi), 'Weird fields');
      expect(p.org, LocalText.empty);
      expect(p.category, JobCategory.other);
      expect(p.postedAt, isNull);
      expect(p.updatedAt, isNull);
      expect(p.lastDate, isNull);
      expect(p.totalPosts, isNull);
      expect(p.qualifications, [Qualification.graduate]);
      expect(p.states, [allStates]);
      expect((p.ageMin, p.ageMax), (null, null));
      expect(p.salary, isNull);
      expect(p.tags, isEmpty);
      expect(p.verified, isFalse);
    });

    test('string numbers and lower-case states are accepted', () {
      final p = index.byId('good-states-only')!;
      expect(p.title.of(AppLang.en), 'केवल हिंदी शीर्षक');
      expect(p.type, PostType.result);
      expect(p.states, ['MP', 'RJ']);
      expect(p.totalPosts, 1200);
      expect((p.ageMin, p.ageMax), (18, 35));
      expect(p.lastDate, Ymd(2026, 12, 31));
    });
  });

  group('FeedIndex.parse rejects unusable files', () {
    for (final body in ['', 'not json', '[]', '"posts"', '{"posts": "x"}', '{"schema": 1}', 'null']) {
      test(body.isEmpty ? '(empty)' : body, () => expect(() => FeedIndex.parse(body), throwsFormatException));
    }
    test('empty posts list is fine', () {
      expect(FeedIndex.parse('{"posts": []}').posts, isEmpty);
    });
    test('caps at 600 posts', () {
      final posts = [
        for (var i = 0; i < 650; i++) {'id': 'p-$i', 'title': 'Post $i'},
      ];
      final idx = FeedIndex.fromJson({'posts': posts});
      expect(idx.posts.length, FeedIndex.maxPosts);
      expect(idx.skipped, 50);
    });
    test('newer schema number is kept', () {
      expect(FeedIndex.parse('{"schema": 3, "posts": []}').schema, 3);
    });
  });

  group('PostSummary.tryParse: one broken field never drops the post', () {
    final breakers = <String, Object?>{
      'type': 7,
      'org': ['x'],
      'source': {'a': 1},
      'category': null,
      'postedAt': 'soon',
      'updatedAt': false,
      'lastDate': '05/11/2026',
      'totalPosts': 'many',
      'qualifications': 'graduate',
      'states': {'UP': true},
      'ageMin': 'eighteen',
      'ageMax': -1,
      'salary': 25000,
      'tags': 5,
      'verified': 'true',
      'unknownKey': {'deep': ['nested']},
    };
    breakers.forEach((field, value) {
      test('$field = $value', () {
        final m = _base()..[field] = value;
        final p = PostSummary.tryParse(m);
        expect(p, isNotNull);
        expect(p!.id, 'test-post');
        expect(p.title.en, 'Test post');
      });
    });

    final dropped = <String, Object?>{
      'id': null,
      'title': null,
    };
    dropped.forEach((field, value) {
      test('missing $field drops the post', () {
        final m = _base()..[field] = value;
        expect(PostSummary.tryParse(m), isNull);
      });
    });

    test('non-map is null', () => expect(PostSummary.tryParse('x'), isNull));
    test('swapped ages are both dropped', () {
      final p = PostSummary.tryParse(_base()
        ..['ageMin'] = 35
        ..['ageMax'] = 20)!;
      expect((p.ageMin, p.ageMax), (null, null));
    });
    test('equal min and max ages are kept', () {
      final p = PostSummary.tryParse(_base()
        ..['ageMin'] = 21
        ..['ageMax'] = 21)!;
      expect((p.ageMin, p.ageMax), (21, 21));
    });
    test('ages out of 10..80 are dropped', () {
      final p = PostSummary.tryParse(_base()
        ..['ageMin'] = 5
        ..['ageMax'] = 99)!;
      expect((p.ageMin, p.ageMax), (null, null));
    });
    test('updatedAt falls back to postedAt', () {
      final p = PostSummary.tryParse(_base()..remove('updatedAt'))!;
      expect(p.updatedAt, p.postedAt);
    });
    test('duplicate qualifications collapse', () {
      final p = PostSummary.tryParse(_base()..['qualifications'] = ['10th', '10th', '12th'])!;
      expect(p.qualifications, [Qualification.class10, Qualification.class12]);
    });
    test('"all" plus states becomes all', () {
      final p = PostSummary.tryParse(_base()..['states'] = ['UP', 'all'])!;
      expect(p.states, [allStates]);
    });
  });

  group('openToState', () {
    PostSummary withStates(List<String> s) => PostSummary.tryParse(_base()..['states'] = s)!;
    final cases = <(List<String>, String?, bool)>[
      (['all'], 'UP', true),
      (['all'], null, true),
      (['UP'], 'UP', true),
      (['UP'], 'BR', false),
      (['UP', 'BR'], 'BR', true),
      ([], 'BR', true),
      (['UP'], null, true),
    ];
    for (final (states, user, want) in cases) {
      test('$states for $user', () => expect(withStates(states).openToState(user), want));
    }
  });

  group('taxonomy parsing', () {
    for (final t in PostType.values) {
      test('type ${t.wire}', () => expect(PostType.parse(t.wire), t));
    }
    test('unknown type is a notice', () => expect(PostType.parse('webinar'), PostType.notice));
    for (final c in JobCategory.values) {
      test('category ${c.wire}', () => expect(JobCategory.parse(c.wire), c));
    }
    test('unknown category is other', () => expect(JobCategory.parse('astronaut'), JobCategory.other));
    for (final q in Qualification.values) {
      test('qualification ${q.wire}', () => expect(Qualification.tryParse(q.wire), q));
    }
    test('qualification is case-insensitive', () => expect(Qualification.tryParse(' 10TH '), Qualification.class10));
    test('unknown qualification is null', () => expect(Qualification.tryParse('phd'), isNull));
    test('there are 36 states and UTs', () => expect(indianStates.length, 36));
    test('state codes are unique', () => expect(stateByCode.length, indianStates.length));
    for (final st in indianStates) {
      test('state ${st.code} has both names', () {
        expect(st.en, isNotEmpty);
        expect(st.hi, isNotEmpty);
        expect(parseStateCode(st.code.toLowerCase()), st.code);
      });
    }
    test('unknown state code', () => expect(parseStateCode('XX'), isNull));
    test('ALL in any case', () => expect(parseStateCode('ALL'), allStates));
  });

  group('SSC CGL detail', () {
    final d = fixturePost('ssc-cgl-2026-notice');

    test('summary part', () => expect(d.summary.id, 'ssc-cgl-2026-notice'));
    test('short info in both languages', () {
      expect(d.shortInfo!.en, startsWith('Staff Selection Commission'));
      expect(d.shortInfo!.hi, startsWith('कर्मचारी चयन आयोग'));
    });
    test('dates: broken entry skipped', () => expect(d.importantDates.length, 5));
    test('date with text', () {
      final e = d.importantDates[1];
      expect(e.date, Ymd(2026, 11, 5));
      expect(e.text!.en, '05 Nov 2026 (11 PM)');
    });
    test('date null but text present', () {
      final e = d.importantDates[4];
      expect(e.date, isNull);
      expect(e.text!.hi, 'परीक्षा से पहले');
    });
    test('fees', () {
      expect(d.fees.length, 3);
      expect(d.fees[0].amount, 100);
      expect(d.fees[1].amount, 0);
      expect(d.fees[1].text!.en, 'No fee');
      expect(d.fees[2].amount, 200);
      expect(d.fees[2].text, isNull);
    });
    test('age', () {
      expect(d.age.min, 18);
      expect(d.age.max, 32);
      expect(d.age.asOn, Ymd(2026, 8, 1));
      expect(d.age.relaxation!.en, contains('OBC 3 years'));
    });
    test('vacancies: row without post skipped', () => expect(d.vacancies.length, 3));
    test('vacancy breakdown parts', () {
      expect(d.vacancies[0].breakdownParts,
          [('UR', 1700), ('OBC', 1134), ('EWS', 420), ('SC', 630), ('ST', 316)]);
      expect(d.vacancies[2].breakdownParts, isEmpty);
    });
    test('selection: non-text step skipped', () => expect(d.selection.length, 3));
    test('links: javascript and relative links dropped', () {
      expect(d.links.map((l) => l.label.en), ['Apply online', 'Official notice']);
    });
    test('notice and source urls', () {
      expect(d.officialNoticeUrl, endsWith('cgl2026.pdf'));
      expect(d.sourcePageUrl, 'https://ssc.gov.in/home/notice-board');
    });
    test('check info', () {
      expect(d.check!.rounds, 2);
      expect(d.check!.factsChecked, 31);
      expect(d.check!.factsDropped, 1);
      expect(d.check!.model, 'deepseek-flash');
    });
    test('total posts from summary', () => expect(d.totalPosts, 14582));
  });

  group('RRB NTPC detail with broken sections', () {
    final d = fixturePost('rrb-ntpc-graduate-2026');
    test('non-list dates become empty', () => expect(d.importantDates, isEmpty));
    test('null fees become empty', () => expect(d.fees, isEmpty));
    test('string and double ages are read', () => expect((d.age.min, d.age.max), (18, 36)));
    test('bad asOn format is null', () => expect(d.age.asOn, isNull));
    test('ftp notice url dropped', () => expect(d.officialNoticeUrl, isNull));
    test('total summed from vacancies when missing', () => expect(d.totalPosts, 615 + 3416 + 4082));
    test('missing selection is empty', () => expect(d.selection, isEmpty));
    test('ageMin falls back to summary', () => expect(d.ageMin, 18));
  });

  group('parsePostDetail', () {
    test('rejects non-post JSON', () => expect(() => parsePostDetail('{"x":1}'), throwsFormatException));
    test('rejects invalid JSON', () => expect(() => parsePostDetail('{'), throwsFormatException));
    test('rejects list', () => expect(() => parsePostDetail('[]'), throwsFormatException));
    test('accepts the bare minimum', () {
      final d = parsePostDetail('{"id": "x-1", "title": "X"}');
      expect(d.id, 'x-1');
      expect(d.age.isEmpty, isTrue);
      expect(d.links, isEmpty);
      expect(d.totalPosts, isNull);
    });
    test('vacancy total unknown in one row means unknown sum', () {
      final d = parsePostDetail(jsonEncode({
        'id': 'x-2',
        'title': 'X',
        'vacancies': [
          {'post': 'A', 'total': 5},
          {'post': 'B'},
        ],
      }));
      expect(d.totalPosts, isNull);
    });
    test('detail age limits override summary ones', () {
      final d = parsePostDetail(jsonEncode({
        'id': 'x-3',
        'title': 'X',
        'ageMin': 18,
        'ageMax': 30,
        'age': {'min': 20, 'max': 35},
      }));
      expect((d.ageMin, d.ageMax), (20, 35));
    });
  });

  group('breakdownParts parsing', () {
    final cases = <(String, List<(String, int)>)>[
      ('UR 50, OBC 32, EWS 12, SC 18, ST 8', [('UR', 50), ('OBC', 32), ('EWS', 12), ('SC', 18), ('ST', 8)]),
      ('UR: 1,200; OBC: 300', [('UR', 1200), ('OBC', 300)]),
      ('UR-10 | SC-4', [('UR', 10), ('SC', 4)]),
      ('Ex-SM 12', [('Ex-SM', 12)]),
      ('UR 10, something odd, ST 2', [('UR', 10), ('ST', 2)]),
      ('no numbers here', []),
      ('', []),
    ];
    for (final (text, want) in cases) {
      test(text.isEmpty ? '(empty)' : text, () {
        final v = VacancyEntry(const LocalText.same('P'), null, text.isEmpty ? null : LocalText.same(text));
        expect(v.breakdownParts, want);
      });
    }
  });
}
