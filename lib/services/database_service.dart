import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class ScanHistoryItem {
  final int? id;
  final String label;
  final double confidence;
  final DateTime timestamp;
  final Uint8List imageBytes;

  ScanHistoryItem({
    this.id,
    required this.label,
    required this.confidence,
    required this.timestamp,
    required this.imageBytes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'confidence': confidence,
      'timestamp': timestamp.toIso8601String(),
      'imageBytes': base64Encode(imageBytes),
    };
  }

  factory ScanHistoryItem.fromMap(Map<String, dynamic> map) {
    return ScanHistoryItem(
      id: map['id'],
      label: map['label'],
      confidence: map['confidence'],
      timestamp: DateTime.parse(map['timestamp']),
      imageBytes: base64Decode(map['imageBytes']),
    );
  }
}

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'plantguard.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE scan_history(id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT, confidence REAL, timestamp TEXT, imageBytes TEXT)',
        );
      },
    );
  }

  Future<void> insertScan(ScanHistoryItem item) async {
    final db = await database;
    await db.insert(
      'scan_history',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ScanHistoryItem>> getScans() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('scan_history', orderBy: 'timestamp DESC');

    return List.generate(maps.length, (i) {
      return ScanHistoryItem.fromMap(maps[i]);
    });
  }

  Future<void> deleteScan(int id) async {
    final db = await database;
    await db.delete(
      'scan_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
