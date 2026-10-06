import 'package:doc_scanner/page_ranges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single pages and ranges', () {
    expect(parsePageRange('1, 3-5', 10), [0, 2, 3, 4]);
  });
  test('open ended ranges', () {
    expect(parsePageRange('8-', 10), [7, 8, 9]);
    expect(parsePageRange('-2', 10), [0, 1]);
  });
  test('spaces and semicolons are fine', () {
    expect(parsePageRange(' 2 ; 4 ', 5), [1, 3]);
  });
  test('out of range is rejected', () {
    expect(() => parsePageRange('0', 3), throwsFormatException);
    expect(() => parsePageRange('4', 3), throwsFormatException);
    expect(() => parsePageRange('3-2', 3), throwsFormatException);
  });
  test('junk and empty input are rejected', () {
    expect(() => parsePageRange('abc', 3), throwsFormatException);
    expect(() => parsePageRange('  ', 3), throwsFormatException);
  });
  test('split groups follow commas', () {
    expect(parseSplitGroups('1-2, 3, 4-5', 5), [
      [0, 1],
      [2],
      [3, 4],
    ]);
  });
  test('fixed groups', () {
    expect(fixedGroups(5, 2), [
      [0, 1],
      [2, 3],
      [4],
    ]);
    expect(() => fixedGroups(5, 0), throwsFormatException);
  });
}
