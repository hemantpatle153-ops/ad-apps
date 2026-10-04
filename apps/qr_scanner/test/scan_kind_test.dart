import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/src/scan_kind.dart';

void main() {
  test('classifies common QR contents', () {
    expect(ScanKind.of('upi://pay?pa=shop@okicici&pn=Shop'), ScanKind.upi);
    expect(ScanKind.of('https://example.com'), ScanKind.url);
    expect(ScanKind.of('WIFI:S:Home;T:WPA;P:secret;;'), ScanKind.wifi);
    expect(ScanKind.of('8901030865278'), ScanKind.product);
    expect(ScanKind.of('hello world'), ScanKind.text);
  });

  test('only offers to open things another app can handle', () {
    expect(ScanKind.launchUri('hello world'), isNull);
    expect(ScanKind.launchUri('WIFI:S:Home;;'), isNull);
    expect(ScanKind.launchUri('https://example.com').toString(),
        'https://example.com');
  });
}
