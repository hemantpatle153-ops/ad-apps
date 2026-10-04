import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class Category {
  const Category(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;

  static const all = [
    Category('food', 'Food', Icons.restaurant, Color(0xFFEF6C00)),
    Category('groceries', 'Groceries', Icons.local_grocery_store, Color(0xFF7CB342)),
    Category('transport', 'Transport', Icons.directions_bus, Color(0xFF1E88E5)),
    Category('fuel', 'Fuel', Icons.local_gas_station, Color(0xFF5E35B1)),
    Category('shopping', 'Shopping', Icons.shopping_bag, Color(0xFFD81B60)),
    Category('bills', 'Bills', Icons.receipt_long, Color(0xFF00897B)),
    Category('rent', 'Rent', Icons.home, Color(0xFF6D4C41)),
    Category('health', 'Health', Icons.medical_services, Color(0xFFE53935)),
    Category('education', 'Education', Icons.school, Color(0xFF3949AB)),
    Category('fun', 'Entertainment', Icons.movie, Color(0xFF8E24AA)),
    Category('gifts', 'Gifts', Icons.card_giftcard, Color(0xFFF4511E)),
    Category('other', 'Other', Icons.more_horiz, Color(0xFF757575)),
  ];

  static Category byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => all.last);
}

class Expense {
  Expense({
    this.id,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
  });

  final int? id;

  /// Stored in minor units (paise / cents) so totals never drift.
  final int amount;
  final String category;
  final DateTime date;
  final String note;

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'amount': amount,
        'category': category,
        'date': date.millisecondsSinceEpoch,
        'note': note,
      };

  factory Expense.fromRow(Map<String, Object?> r) => Expense(
        id: r['id'] as int,
        amount: r['amount'] as int,
        category: r['category'] as String,
        date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
        note: (r['note'] as String?) ?? '',
      );
}

/// SQLite on the phone. Nothing leaves the device unless the user exports.
class ExpenseDb {
  ExpenseDb._(this._db);
  final Database _db;

  static Future<ExpenseDb> open() async {
    final path = p.join(await getDatabasesPath(), 'expenses.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount INTEGER NOT NULL,
            category TEXT NOT NULL,
            date INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT ''
          )''');
        await db.execute('CREATE INDEX idx_date ON expenses(date)');
      },
    );
    return ExpenseDb._(db);
  }

  Future<List<Expense>> month(DateTime m) async {
    final start = DateTime(m.year, m.month);
    final end = DateTime(m.year, m.month + 1);
    final rows = await _db.query(
      'expenses',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Expense.fromRow).toList();
  }

  Future<List<Expense>> all() async =>
      (await _db.query('expenses', orderBy: 'date DESC, id DESC'))
          .map(Expense.fromRow)
          .toList();

  Future<void> save(Expense e) async {
    if (e.id == null) {
      await _db.insert('expenses', e.toRow());
    } else {
      await _db.update('expenses', e.toRow(), where: 'id = ?', whereArgs: [e.id]);
    }
  }

  Future<void> delete(int id) =>
      _db.delete('expenses', where: 'id = ?', whereArgs: [id]);
}

/// Currency symbol and monthly budget.
class Settings extends ChangeNotifier {
  Settings(this._p);
  final SharedPreferences _p;

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  String get currency => _p.getString('currency') ?? '₹';
  set currency(String v) {
    _p.setString('currency', v);
    notifyListeners();
  }

  /// Monthly budget in minor units, 0 = none.
  int get budget => _p.getInt('budget') ?? 0;
  set budget(int v) {
    _p.setInt('budget', v);
    notifyListeners();
  }

  String money(int minor) {
    final neg = minor < 0;
    final v = minor.abs();
    final whole = (v ~/ 100).toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    final cents = v % 100;
    return '${neg ? '-' : ''}$currency$whole${cents == 0 ? '' : '.${cents.toString().padLeft(2, '0')}'}';
  }
}

/// Parses "12", "12.5", "1,234.50" into minor units; null if invalid.
int? parseAmount(String s) {
  final t = s.replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(t)) return null;
  final parts = t.split('.');
  final whole = int.parse(parts[0]);
  final frac = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  final v = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return v > 0 ? v : null;
}

/// RFC 4180 CSV of every expense, for backup or a spreadsheet.
String toCsv(List<Expense> list) {
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer('date,category,amount,note\n');
  for (final e in list) {
    final d = e.date;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    b.writeln(
        '$date,${q(Category.byId(e.category).label)},${(e.amount / 100).toStringAsFixed(2)},${q(e.note)}');
  }
  return b.toString();
}
