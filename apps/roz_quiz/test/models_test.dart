import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/bi.dart';
import 'package:roz_quiz/core/day.dart';
import 'package:roz_quiz/core/models.dart';

import 'support/harness.dart';

Map<String, Object?> withChange(void Function(Map<String, Object?> j) change) {
  final j = questionJson();
  change(j);
  return j;
}

void main() {
  group('Bi.tryParse', () {
    final cases = <(String, Object?, Bi?)>[
      ('both', {'en': 'Hi', 'hi': 'नमस्ते'}, const Bi('Hi', 'नमस्ते')),
      ('english only', {'en': 'Hi'}, const Bi('Hi', 'Hi')),
      ('hindi only', {'hi': 'नमस्ते'}, const Bi('नमस्ते', 'नमस्ते')),
      ('empty hindi falls back', {'en': 'Hi', 'hi': ''}, const Bi('Hi', 'Hi')),
      ('null hindi falls back', {'en': 'Hi', 'hi': null}, const Bi('Hi', 'Hi')),
      ('trims', {'en': '  Hi ', 'hi': ' न '}, const Bi('Hi', 'न')),
      ('plain string', 'Text', const Bi('Text', 'Text')),
      ('empty map', <String, Object?>{}, null),
      ('both empty', {'en': ' ', 'hi': ''}, null),
      ('numbers not text', {'en': 5, 'hi': 6}, null),
      ('null', null, null),
      ('list', ['a'], null),
      ('empty string', '   ', null),
      ('extra keys ignored', {'en': 'A', 'hi': 'ब', 'ta': 'x'}, const Bi('A', 'ब')),
    ];
    for (final (name, json, want) in cases) {
      test(name, () => expect(Bi.tryParse(json), want));
    }
    test('of() and hasHindi', () {
      const b = Bi('A', 'ब');
      expect(b.of(Lang.en), 'A');
      expect(b.of(Lang.hi), 'ब');
      expect(b.hasHindi, isTrue);
      expect(const Bi.same('5').hasHindi, isFalse);
      expect(Bi.tryParse(b.toJson()), b);
    });
    test('Lang helpers', () {
      expect(Lang.parse('hi'), Lang.hi);
      expect(Lang.parse('en'), Lang.en);
      expect(Lang.parse(null), Lang.en);
      expect(Lang.parse('xx'), Lang.en);
      expect(Lang.en.other, Lang.hi);
      expect(Lang.hi.other, Lang.en);
    });
  });

  group('Question.tryParse accepts', () {
    test('a full valid question', () {
      final q = Question.tryParse(questionJson())!;
      expect(q.id, 'q-gk-1');
      expect(q.q.en, 'What?');
      expect(q.options.map((o) => o.hi), ['क', 'ख', 'ग', 'घ']);
      expect(q.answer, 1);
      expect(q.isCorrect(1), isTrue);
      expect(q.isCorrect(0), isFalse);
      expect(q.isCorrect(null), isFalse);
      expect(q.subject, 'gk');
      expect(q.exams, ['ssc']);
      expect(q.difficulty, Difficulty.easy);
      expect(q.source!.name, 'PIB');
      expect(q.source!.url, 'https://pib.gov.in/x');
      expect(q.isPyq, isFalse);
    });
    final ok = <(String, void Function(Map<String, Object?>), void Function(Question))>[
      ('unknown keys', (j) => j['newField'] = {'a': 1}, (q) => expect(q.id, 'q-gk-1')),
      ('answer 0', (j) => j['answer'] = 0, (q) => expect(q.answer, 0)),
      ('answer 3', (j) => j['answer'] = 3, (q) => expect(q.answer, 3)),
      ('answer as 2.0', (j) => j['answer'] = 2.0, (q) => expect(q.answer, 2)),
      ('null explanation', (j) => j['explanation'] = null, (q) => expect(q.explanation.en, '')),
      ('missing explanation', (j) => j.remove('explanation'), (q) => expect(q.explanation.hi, '')),
      ('null source', (j) => j['source'] = null, (q) => expect(q.source, isNull)),
      ('source without url', (j) => j['source'] = {'name': 'PIB'}, (q) => expect(q.source!.url, isNull)),
      ('source with bad url', (j) => j['source'] = {'name': 'PIB', 'url': 'javascript:alert(1)'},
          (q) => expect(q.source!.url, isNull)),
      ('source url only', (j) => j['source'] = {'url': 'https://pib.gov.in/a'},
          (q) => expect(q.source!.name, 'pib.gov.in')),
      ('source garbage', (j) => j['source'] = 'PIB', (q) => expect(q.source, isNull)),
      ('asked set', (j) => j['asked'] = 'SSC CGL 2023', (q) {
        expect(q.asked, 'SSC CGL 2023');
        expect(q.isPyq, isTrue);
      }),
      ('asked empty string', (j) => j['asked'] = '  ', (q) => expect(q.isPyq, isFalse)),
      ('asked number', (j) => j['asked'] = 2023, (q) => expect(q.asked, isNull)),
      ('unknown subject becomes gk', (j) => j['subject'] = 'astrology', (q) => expect(q.subject, 'gk')),
      ('subject case', (j) => j['subject'] = 'Polity', (q) => expect(q.subject, 'polity')),
      ('missing subject', (j) => j.remove('subject'), (q) => expect(q.subject, 'gk')),
      ('unknown exams dropped', (j) => j['exams'] = ['ssc', 'xyz', 5, 'upsc', 'ssc'],
          (q) => expect(q.exams, ['ssc', 'upsc'])),
      ('exams not a list', (j) => j['exams'] = 'ssc', (q) => expect(q.exams, isEmpty)),
      ('difficulty hard', (j) => j['difficulty'] = 'hard', (q) => expect(q.difficulty, Difficulty.hard)),
      ('difficulty unknown', (j) => j['difficulty'] = 'insane', (q) => expect(q.difficulty, Difficulty.medium)),
      ('difficulty null', (j) => j['difficulty'] = null, (q) => expect(q.difficulty, Difficulty.medium)),
      ('verified missing', (j) => j.remove('verified'), (q) => expect(q.id, 'q-gk-1')),
      ('verified null', (j) => j['verified'] = null, (q) => expect(q.id, 'q-gk-1')),
      ('plain string texts', (j) {
        j['q'] = 'What?';
        j['options'] = ['A', 'B', 'C', 'D'];
      }, (q) => expect(q.options[2].hi, 'C')),
      ('hindi option missing falls back', (j) => j['options'] = [
            {'en': 'A'}, {'en': 'B', 'hi': 'ख'}, {'en': 'C', 'hi': 'ग'}, {'en': 'D', 'hi': 'घ'}
          ], (q) => expect(q.options[0].hi, 'A')),
    ];
    for (final (name, change, check) in ok) {
      test(name, () {
        final q = Question.tryParse(withChange(change));
        expect(q, isNotNull);
        check(q!);
      });
    }
  });

  group('Question.tryParse rejects', () {
    final bad = <(String, void Function(Map<String, Object?>))>[
      ('missing id', (j) => j.remove('id')),
      ('null id', (j) => j['id'] = null),
      ('empty id', (j) => j['id'] = '  '),
      ('numeric id', (j) => j['id'] = 123),
      ('id with spaces', (j) => j['id'] = 'q gk 1'),
      ('id with slash', (j) => j['id'] = '../q'),
      ('very long id', (j) => j['id'] = 'q${'x' * 100}'),
      ('missing q', (j) => j.remove('q')),
      ('null q', (j) => j['q'] = null),
      ('empty q', (j) => j['q'] = {'en': '', 'hi': ''}),
      ('3 options', (j) => j['options'] = (j['options'] as List).sublist(0, 3)),
      ('5 options', (j) => j['options'] = [...(j['options'] as List), {'en': 'E', 'hi': 'ङ'}]),
      ('0 options', (j) => j['options'] = []),
      ('options not a list', (j) => j['options'] = 'A,B,C,D'),
      ('null option', (j) => (j['options'] as List)[2] = null),
      ('empty option', (j) => (j['options'] as List)[1] = {'en': '', 'hi': ''}),
      ('duplicate english options', (j) => (j['options'] as List)[1] = {'en': 'a', 'hi': 'ख'}),
      ('duplicate hindi options', (j) => (j['options'] as List)[1] = {'en': 'B', 'hi': 'क'}),
      ('answer 4', (j) => j['answer'] = 4),
      ('answer -1', (j) => j['answer'] = -1),
      ('answer 99', (j) => j['answer'] = 99),
      ('answer string', (j) => j['answer'] = '1'),
      ('answer 1.5', (j) => j['answer'] = 1.5),
      ('answer null', (j) => j['answer'] = null),
      ('answer missing', (j) => j.remove('answer')),
      ('answer bool', (j) => j['answer'] = true),
      ('verified false', (j) => j['verified'] = false),
    ];
    for (final (name, change) in bad) {
      test(name, () => expect(Question.tryParse(withChange(change)), isNull));
    }
    for (final v in [null, 1, 'q', <Object>[], true]) {
      test('non-map $v', () => expect(Question.tryParse(v), isNull));
    }
  });

  group('Question.parseList', () {
    test('skips malformed and repeated ids', () {
      final list = Question.parseList([
        questionJson(id: 'a'),
        questionJson(id: 'b', answer: 7),
        null,
        'x',
        questionJson(id: 'a', answer: 2),
        questionJson(id: 'c'),
      ]);
      expect(list.map((q) => q.id), ['a', 'c']);
      expect(list.first.answer, 1, reason: 'first copy wins');
    });
    test('non-list gives empty', () {
      expect(Question.parseList(null), isEmpty);
      expect(Question.parseList({'a': 1}), isEmpty);
    });
    test('toJson round-trips', () {
      final q = Question.tryParse(withChange((j) => j['asked'] = 'RRB NTPC 2021'))!;
      final back = Question.tryParse(jsonDecode(jsonEncode(q.toJson())))!;
      expect(back.id, q.id);
      expect(back.q, q.q);
      expect(back.options, q.options);
      expect(back.answer, q.answer);
      expect(back.explanation, q.explanation);
      expect(back.subject, q.subject);
      expect(back.exams, q.exams);
      expect(back.difficulty, q.difficulty);
      expect(back.asked, q.asked);
      expect(back.source!.url, q.source!.url);
    });
    test('equality by id', () {
      final a = Question.tryParse(questionJson(id: 'same'))!;
      final b = Question.tryParse(questionJson(id: 'same', answer: 2))!;
      expect(a, b);
      expect({a, b}.length, 1);
    });
  });

  group('isWebUrl', () {
    const good = ['https://pib.gov.in/x', 'http://example.com', 'https://a.b/c?d=e'];
    const bad = ['ftp://x.y', 'javascript:alert(1)', 'pib.gov.in', '', 'https://', 'mailto:a@b.c'];
    for (final u in good) {
      test('accepts $u', () => expect(isWebUrl(u), isTrue));
    }
    for (final u in bad) {
      test('rejects "$u"', () => expect(isWebUrl(u), isFalse));
    }
  });

  group('DailyQuiz', () {
    test('parses the fixture', () {
      final d = DailyQuiz.tryParse(fixtureJson('daily_2026-10-07.json'), expected: Day(2026, 10, 7))!;
      expect(d.date, Day(2026, 10, 7));
      expect(d.questions.length, 10);
      expect(d.title!.en, 'Daily Quiz · 7 Oct');
      expect(d.questions.first.asked, 'SSC CGL 2019');
    });
    test('keeps only the good questions of a malformed file', () {
      final d = DailyQuiz.tryParse(fixtureJson('daily_malformed.json'))!;
      expect(d.questions.map((q) => q.id), ['q-polity-000101', 'q-english-000110']);
      expect(d.title, isNull);
    });
    test('rejects a file for another date', () {
      expect(DailyQuiz.tryParse(fixtureJson('daily_2026-10-07.json'), expected: Day(2026, 10, 8)),
          isNull);
    });
    test('uses the expected date when the file has none', () {
      final j = fixtureJson('daily_2026-10-07.json') as Map;
      j.remove('date');
      expect(DailyQuiz.tryParse(j, expected: Day(2026, 10, 7))!.date, Day(2026, 10, 7));
      expect(DailyQuiz.tryParse(j), isNull);
    });
    test('no valid questions -> null', () {
      expect(DailyQuiz.tryParse({'date': '2026-10-07', 'questions': [null]}), isNull);
      expect(DailyQuiz.tryParse({'date': '2026-10-07'}), isNull);
    });
    for (final v in [null, 'x', 1, <Object>[]]) {
      test('non-map $v', () => expect(DailyQuiz.tryParse(v), isNull));
    }
  });

  group('CaDay', () {
    test('parses the fixture', () {
      final ca = CaDay.tryParse(fixtureJson('current_affairs_2026-10-07.json'))!;
      expect(ca.notes.length, 3);
      expect(ca.questions.length, 2);
      expect(ca.notes.first.source!.name, 'PIB');
      expect(ca.notes.last.source, isNull);
      expect(ca.notes.first.tags, ['gk']);
      expect(ca.questions.every((q) => q.subject == 'current_affairs'), isTrue);
    });
    test('drops broken notes and duplicate ids', () {
      final ca = CaDay.tryParse({
        'date': '2026-10-07',
        'notes': [
          {'id': 'n1', 'title': 'T', 'body': 'B', 'tags': ['a', 3, '', ' b ']},
          {'id': 'n1', 'title': 'T2', 'body': 'B2'},
          {'id': 'n2', 'title': null, 'body': 'B'},
          {'title': 'T', 'body': 'B'},
          {'id': 'n3', 'title': 'T', 'body': ''},
          'note',
        ],
      })!;
      expect(ca.notes.map((n) => n.id), ['n1']);
      expect(ca.notes.first.tags, ['a', 'b']);
    });
    test('empty day -> null', () {
      expect(CaDay.tryParse({'date': '2026-10-07', 'notes': [], 'questions': []}), isNull);
    });
    test('wrong date -> null', () {
      expect(CaDay.tryParse(fixtureJson('current_affairs_2026-10-07.json'),
          expected: Day(2026, 10, 6)), isNull);
    });
  });

  group('FeedIndex', () {
    test('parses the fixture, drops bad dates and unsafe bank paths', () {
      final idx = FeedIndex.tryParse(fixtureJson('index.json'))!;
      expect(idx.generatedAt, DateTime.utc(2026, 10, 7, 0, 45));
      expect(idx.daily.map((d) => d.key), ['2026-10-07', '2026-10-06', '2026-10-05']);
      expect(idx.currentAffairs.length, 2);
      expect(idx.banks.map((b) => b.id), ['polity']);
      expect(idx.banks.first.updatedAt, DateTime.utc(2026, 10, 6, 12));
      expect(idx.banks.first.title.hi, 'राजव्यवस्था');
    });
    test('sorts dates newest first and removes duplicates', () {
      final idx = FeedIndex.tryParse({
        'daily': ['2026-10-01', '2026-10-03', '2026-10-02', '2026-10-03'],
      })!;
      expect(idx.daily.map((d) => d.key), ['2026-10-03', '2026-10-02', '2026-10-01']);
    });
    test('tolerates nulls everywhere', () {
      final idx = FeedIndex.tryParse(
          {'generatedAt': null, 'daily': null, 'currentAffairs': 5, 'banks': null})!;
      expect(idx.daily, isEmpty);
      expect(idx.banks, isEmpty);
      expect(idx.generatedAt, isNull);
    });
    final badBanks = <Object?>[
      {'id': 'a', 'file': 'quiz/banks/../x.json'},
      {'id': 'a', 'file': 'https://evil.example/x.json'},
      {'id': 'a', 'file': 'quiz/daily/x.json'},
      {'id': 'a'},
      {'file': 'quiz/banks/a.json'},
      null,
    ];
    for (final b in badBanks) {
      test('bank entry rejected: $b', () => expect(BankInfo.tryParse(b), isNull));
    }
    test('bank count defaults to 0', () {
      expect(BankInfo.tryParse({'id': 'a', 'file': 'quiz/banks/a.json', 'count': -5})!.count, 0);
      expect(BankInfo.tryParse({'id': 'a', 'file': 'quiz/banks/a.json'})!.title.en, 'a');
    });
  });

  group('QuestionBank', () {
    test('parses the fixture', () {
      final b = QuestionBank.tryParse(fixtureJson('bank_polity.json'))!;
      expect(b.subject, 'polity');
      expect(b.questions.length, 3);
      expect(b.questions.where((q) => q.isPyq).length, 2);
    });
    test('null questions -> empty bank', () {
      expect(QuestionBank.tryParse({'subject': 'x'})!.questions, isEmpty);
      expect(QuestionBank.tryParse(null), isNull);
    });
  });
}
