import 'package:doc_scanner/text_diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical text', () {
    final d = diffWords('a b  c', 'a\nb c');
    expect(d.identical, isTrue);
    expect(d.similarity, 1);
    expect(d.parts, [const DiffPart(DiffOp.same, 'a b c')]);
  });

  test('a changed word shows as removed then added', () {
    final d = diffWords('Pay 500 rupees by Monday', 'Pay 900 rupees by Friday');
    expect(d.parts, const [
      DiffPart(DiffOp.same, 'Pay'),
      DiffPart(DiffOp.removed, '500'),
      DiffPart(DiffOp.added, '900'),
      DiffPart(DiffOp.same, 'rupees by'),
      DiffPart(DiffOp.removed, 'Monday'),
      DiffPart(DiffOp.added, 'Friday'),
    ]);
    expect(d.added, 2);
    expect(d.removed, 2);
    expect(d.same, 3);
  });

  test('inserted and deleted words', () {
    final d = diffWords('one two three', 'zero one three four');
    expect(d.added, 2);
    expect(d.removed, 1);
    expect(d.same, 2);
  });

  test('empty sides', () {
    expect(diffWords('', '').identical, isTrue);
    expect(diffWords('', 'new text').added, 2);
    expect(diffWords('old', '').removed, 1);
  });

  test('similarity is a share of matching words', () {
    expect(diffWords('a b c d', 'a b c e').similarity, closeTo(0.75, 0.001));
  });

  test('large mostly equal documents stay quick', () {
    final base = List.generate(20000, (i) => 'w$i').join(' ');
    final changed = base.replaceFirst('w10000', 'CHANGED');
    final sw = Stopwatch()..start();
    final d = diffWords(base, changed);
    expect(d.added, 1);
    expect(d.removed, 1);
    expect(sw.elapsedMilliseconds, lessThan(3000));
  });
}
