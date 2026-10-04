import 'package:doc_scanner/doc_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file names drop characters Android cannot store', () {
    expect(DocStore.sanitize(' Bill: 3/4 '), 'Bill_ 3_4');
    expect(DocStore.sanitize('   '), 'Scan');
  });

  test('sizes are human readable', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });
}
