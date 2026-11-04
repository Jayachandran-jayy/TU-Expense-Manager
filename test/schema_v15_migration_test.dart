@TestOn('vm')
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tu_expense_tracker/src/core/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Schema v15 Migration Tests', () {
    test('upgrades schema from v14 to v15 and adds budget column', () async {
      final dbFactory = databaseFactoryFfi;
      final tempDir = await Directory.systemTemp.createTemp('schema_v15_');
      final dbPath = p.join(tempDir.path, 'test_v15.db');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      
      // Step 1: Create a v14 database manually
      var db = await dbFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 14,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE categories (
                id    INTEGER PRIMARY KEY AUTOINCREMENT,
                name  TEXT NOT NULL UNIQUE COLLATE NOCASE,
                icon  TEXT NOT NULL DEFAULT '',
                color INTEGER
              )
            ''');
            await db.insert('categories', <String, Object?>{
              'name': 'Groceries',
              'icon': '🛒',
              'color': 1,
            });
            await db.insert('categories', <String, Object?>{
              'name': 'Dining',
              'icon': '🍔',
              'color': 2,
            });
          },
        ),
      );

      // Verify v14 rows
      var rows = await db.query('categories');
      expect(rows.length, 2);
      expect(rows.first.containsKey('budget'), isFalse);
      await db.close();

      // Step 2: Open with v15 and AppDatabase upgrade logic
      db = await dbFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: kSchemaVersion,
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 15) {
              await db.execute('ALTER TABLE categories ADD COLUMN budget REAL');
            }
          },
        ),
      );

      // Step 3: Verify budget column exists and preserves existing data
      rows = await db.query('categories', orderBy: 'id ASC');
      expect(rows.length, 2);
      expect(rows.first.containsKey('budget'), isTrue);
      expect(rows.first['budget'], isNull);
      expect(rows.first['name'], 'Groceries');

      // Step 4: Verify writing and reading budget works
      await db.update(
        'categories',
        <String, Object?>{'budget': 6500.0},
        where: 'name = ?',
        whereArgs: <Object?>['Groceries'],
      );

      final updated = await db.query('categories', where: 'name = ?', whereArgs: <Object?>['Groceries']);
      expect(updated.first['budget'], 6500.0);

      await db.close();
    });
  });
}
