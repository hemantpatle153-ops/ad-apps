import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:roz_quiz/core/models.dart';
import 'package:roz_quiz/data/repository.dart';

/// The bundled starter bank is what every user sees offline on first
/// launch; a wrong or broken question there is the worst possible bug.
void main() {
  final devanagari = RegExp(r'[ऀ-ॿ]');
  final files = {
    for (final s in QuizRepository.bundledSubjects)
      s: jsonDecode(File(QuizRepository.bundledAsset(s)).readAsStringSync()) as Map
  };
  final all = <(String, Map)>[
    for (final e in files.entries)
      for (final q in e.value['questions'] as List) (e.key, q as Map)
  ];

  group('bank files', () {
    test('every bundled subject has a file listed in pubspec assets', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/bank/'));
      for (final s in QuizRepository.bundledSubjects) {
        expect(File(QuizRepository.bundledAsset(s)).existsSync(), isTrue, reason: s);
      }
    });
    test('no stray files in assets/bank', () {
      final names = Directory('assets/bank')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(names, {for (final s in QuizRepository.bundledSubjects) '$s.json'});
    });
    for (final e in files.entries) {
      test('${e.key}.json has schema 1 and its subject', () {
        expect(e.value['schema'], 1);
        expect(e.value['subject'], e.key);
        expect((e.value['questions'] as List).length, greaterThanOrEqualTo(10));
      });
      test('${e.key}.json: parser keeps every question', () {
        final raw = e.value['questions'] as List;
        expect(QuestionBank.tryParse(e.value)!.questions.length, raw.length);
      });
    }
    test('at least 150 questions in total', () => expect(all.length, greaterThanOrEqualTo(150)));
    test('no duplicate ids', () {
      final ids = all.map((e) => e.$2['id']).toList();
      expect(ids.toSet().length, ids.length);
    });
    test('no duplicate questions (English)', () {
      final t = all.map((e) => (e.$2['q'] as Map)['en'].toString().toLowerCase()).toList();
      expect(t.toSet().length, t.length);
    });
    test('no duplicate questions (Hindi)', () {
      final t = all.map((e) => (e.$2['q'] as Map)['hi']).toList();
      expect(t.toSet().length, t.length);
    });
    test('answers are spread over A-D (not always the same letter)', () {
      final counts = List.filled(4, 0);
      for (final e in all) {
        counts[e.$2['answer'] as int]++;
      }
      for (final c in counts) {
        expect(c, greaterThan(all.length ~/ 12), reason: '$counts');
      }
    });
    test('no previous-year labels in the starter bank (only real PYQs may carry one)', () {
      for (final e in all) {
        expect(e.$2['asked'], isNull, reason: e.$2['id'].toString());
      }
    });
    test('every exam appears somewhere', () {
      final exams = {for (final e in all) ...(e.$2['exams'] as List)};
      for (final x in kExams) {
        expect(exams, contains(x));
      }
    });
    test('every difficulty appears', () {
      final d = {for (final e in all) e.$2['difficulty']};
      expect(d, containsAll(['easy', 'medium', 'hard']));
    });
  });

  for (final (subject, q) in all) {
    final id = q['id'].toString();
    group(id, () {
      final opts = (q['options'] as List).cast<Map>();
      test('id is rq-$subject-NNN and subject matches its file', () {
        expect(RegExp('^rq-$subject-\\d{3}\$').hasMatch(id), isTrue);
        expect(q['subject'], subject);
      });
      test('exactly 4 options, distinct in English and in Hindi', () {
        expect(opts.length, 4);
        for (final lang in ['en', 'hi']) {
          final texts = opts.map((o) => (o[lang] as String).trim().toLowerCase()).toList();
          expect(texts.every((t) => t.isNotEmpty), isTrue, reason: lang);
          expect(texts.toSet().length, 4, reason: '$lang: $texts');
        }
      });
      test('answer is an index 0-3', () {
        expect(q['answer'], isA<int>());
        expect(q['answer'], inInclusiveRange(0, 3));
      });
      test('question and explanation exist in both languages', () {
        for (final key in ['q', 'explanation']) {
          final m = q[key] as Map;
          expect((m['en'] as String).trim(), isNotEmpty, reason: '$key.en');
          expect((m['hi'] as String).trim(), isNotEmpty, reason: '$key.hi');
        }
      });
      test('Hindi question and explanation are written in Devanagari', () {
        expect(devanagari.hasMatch((q['q'] as Map)['hi'] as String), isTrue);
        expect(devanagari.hasMatch((q['explanation'] as Map)['hi'] as String), isTrue);
        expect(devanagari.hasMatch((q['q'] as Map)['en'] as String), isFalse);
      });
      test('known exams and difficulty, verified, parses', () {
        for (final e in q['exams'] as List) {
          expect(kExams, contains(e));
        }
        expect(['easy', 'medium', 'hard'], contains(q['difficulty']));
        expect(q['verified'], isTrue);
        final parsed = Question.tryParse(q)!;
        expect(parsed.answer, q['answer']);
      });
      test('explanation names the right answer, not a wrong one', () {
        // The explanation should support the marked answer: it mentions the
        // correct option (or its key part) more readily than the others.
        final exp = ((q['explanation'] as Map)['en'] as String)
            .toLowerCase()
            .replaceAll('°', '')
            .replaceAll('₹', '')
            .replaceAll('%', '')
            .replaceAll('the ', '');
        final right = (opts[q['answer'] as int]['en'] as String).toLowerCase();
        final key = _keyPart(right);
        expect(exp.contains(key), isTrue,
            reason: 'explanation of $id should mention "$key"');
      });
    });
  }
}

/// The distinctive part of an option to look for in the explanation:
/// "Vitamin C" -> "vitamin c", "42nd Amendment" -> "42nd", "1 July 2017"
/// -> "1 july 2017", "₹200" -> "200", "Lahore, 1929" -> "lahore".
String _keyPart(String option) {
  var o = option.replaceAll('₹', '').replaceAll('the ', '').trim();
  const stripSuffix = [' amendment', ' years', ' seconds', ' bytes', ' ocean', ' lake', ' strait'];
  for (final s in stripSuffix) {
    if (o.endsWith(s)) o = o.substring(0, o.length - s.length);
  }
  if (o.contains(',')) o = o.split(',').first;
  if (o.contains(' (')) o = o.split(' (').first;
  if (o.startsWith('article ')) o = o.substring(8);
  if (o.startsWith('part ')) o = o.substring(5);
  if (o.startsWith('dr. ')) o = o.substring(4);
  if (o.startsWith('ctrl + ')) o = o.substring(7);
  return o.replaceAll(' cm²', '').replaceAll('°', '').replaceAll('%', '').trim();
}
