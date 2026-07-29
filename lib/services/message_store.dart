import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message.dart';

class MessageStore {
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'messages.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            status TEXT DEFAULT 'pending',
            createdAt TEXT NOT NULL,
            mode TEXT DEFAULT 'general'
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN mode TEXT DEFAULT "general"');
        }
      },
    );
  }

  Future<void> insertMessage(Message msg, {String mode = 'general'}) async {
    try {
      final db = await database;
      final map = msg.toMap();
      map['mode'] = mode;
      await db.insert('messages', map, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('insertMessage error: $e');
    }
  }

  Future<List<Message>> getMessages({String mode = 'general', int limit = 100}) async {
    try {
      final db = await database;
      final maps = await db.query(
        'messages',
        where: 'mode = ?',
        whereArgs: [mode],
        orderBy: 'createdAt DESC',
        limit: limit,
      );
      return maps.map((m) => Message.fromMap(m)).toList().reversed.toList();
    } catch (e) {
      debugPrint('getMessages error: $e');
      return [];
    }
  }

  Future<void> updateStatus(String id, String status) async {
    try {
      final db = await database;
      await db.update('messages', {'status': status}, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint('updateStatus error: $e');
    }
  }

  Future<void> clearAll({String mode = 'general'}) async {
    try {
      final db = await database;
      await db.delete('messages', where: 'mode = ?', whereArgs: [mode]);
    } catch (e) {
      debugPrint('clearAll error: $e');
    }
  }
}