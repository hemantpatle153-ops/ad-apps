import 'package:expense_tracker/data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Settings> fresh([Map<String, Object> init = const {}]) async {
    SharedPreferences.setMockInitialValues(init);
    return Settings(await SharedPreferences.getInstance());
  }

  test('defaults: rupee and no budget', () async {
    final s = await fresh();
    expect(s.currency, '₹');
    expect(s.budget, 0);
  });

  test('load() reads stored values', () async {
    SharedPreferences.setMockInitialValues({'currency': '£', 'budget': 500000});
    final s = await Settings.load();
    expect(s.currency, '£');
    expect(s.budget, 500000);
  });

  const currencies = ['₹', '\$', '€', '£', '¥', 'Rs ', 'R\$', '₦', '₱', '৳', ''];
  for (final c in currencies) {
    test('currency "$c" persists, notifies and affects money()', () async {
      final s = await fresh();
      var calls = 0;
      s.addListener(() => calls++);
      s.currency = c;
      expect(calls, 1);
      expect(s.currency, c);
      expect(s.money(150), '${c}1.50');
      final again = Settings(await SharedPreferences.getInstance());
      expect(again.currency, c);
    });
  }

  const budgets = [0, 1, 100, 500000, 1234567, 99999999999];
  for (final b in budgets) {
    test('budget $b persists and notifies', () async {
      final s = await fresh({'budget': 42});
      var calls = 0;
      s.addListener(() => calls++);
      s.budget = b;
      expect(calls, 1);
      expect(s.budget, b);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('budget'), b);
    });
  }

  test('removed listener is not notified', () async {
    final s = await fresh();
    var calls = 0;
    void l() => calls++;
    s.addListener(l);
    s.removeListener(l);
    s.budget = 10;
    s.currency = '€';
    expect(calls, 0);
  });

  test('each setter call notifies once', () async {
    final s = await fresh();
    var calls = 0;
    s.addListener(() => calls++);
    for (var i = 0; i < 5; i++) {
      s.budget = i;
    }
    s.currency = '¥';
    expect(calls, 6);
  });
}
