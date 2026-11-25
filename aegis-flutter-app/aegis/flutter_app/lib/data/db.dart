import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../health/reading.dart';

/// Almacenamiento local persistente (offline). Lo usan la UI, el SOS y el worker de sincronización.
class AegisDb {
  static Database? _db;

  static Future<Database> open() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'aegis.db'),
      version: 5,
      onCreate: (d, _) async {
        await d.execute('CREATE TABLE emergencies(id TEXT PRIMARY KEY, started_at INTEGER, lat REAL, lon REAL, source TEXT, status TEXT)');
        await d.execute('CREATE TABLE contacts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, priority INTEGER DEFAULT 1)');
        await d.execute('CREATE TABLE sync_queue(op_id TEXT PRIMARY KEY, type TEXT, priority INTEGER, payload TEXT, created_at INTEGER, attempts INTEGER DEFAULT 0, state TEXT DEFAULT "PENDING")');
        await _createHealth(d);
        await _createTracks(d);
        await _createEvidence(d);
        await _createSleep(d);
      },
      onUpgrade: (d, old, _) async {
        if (old < 2) await _createHealth(d);
        if (old < 3) await _createTracks(d);
        if (old < 4) await _createEvidence(d);
        if (old < 5) await _createSleep(d);
      },
    );
    return _db!;
  }

  static Future<void> _createSleep(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS sleep(night TEXT PRIMARY KEY, start INTEGER, end_ INTEGER, minutes INTEGER, quality INTEGER, source TEXT)');
  }

  static Future<void> saveSleep(Map<String, Object?> row) async => (await open()).insert('sleep', row, conflictAlgorithm: ConflictAlgorithm.replace);
  static Future<List<Map<String, Object?>>> sleepNights(int days) async => (await open()).query('sleep', orderBy: 'night DESC', limit: days);

  static Future<void> _createEvidence(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS evidence_files(client_id TEXT PRIMARY KEY, session TEXT, path TEXT, kind TEXT, mime TEXT, trigger_ TEXT, auto INTEGER, duration INTEGER, created INTEGER, attempts INTEGER DEFAULT 0)');
  }

  static Future<void> addEvidence(Map<String, Object?> row) async => (await open()).insert('evidence_files', row, conflictAlgorithm: ConflictAlgorithm.ignore);
  static Future<List<Map<String, Object?>>> pendingEvidence() async => (await open()).query('evidence_files', orderBy: 'created', limit: 20);
  static Future<void> removeEvidence(String cid) async => (await open()).delete('evidence_files', where: 'client_id=?', whereArgs: [cid]);
  static Future<void> bumpEvidence(String cid) async => (await open()).rawUpdate('UPDATE evidence_files SET attempts=attempts+1 WHERE client_id=?', [cid]);
  static Future<int> pendingEvidenceCount() async => Sqflite.firstIntValue(await (await open()).rawQuery('SELECT COUNT(*) FROM evidence_files')) ?? 0;

  static Future<void> _createTracks(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS tracks(id TEXT PRIMARY KEY, started INTEGER, ended INTEGER, distance REAL, steps INTEGER, points TEXT)');
  }

  static Future<void> saveTrack(Map<String, Object?> row) async =>
      (await open()).insert('tracks', row, conflictAlgorithm: ConflictAlgorithm.replace);
  static Future<List<Map<String, Object?>>> tracks() async => (await open()).query('tracks', orderBy: 'started DESC', limit: 60);
  static Future<void> deleteTrack(String id) async => (await open()).delete('tracks', where: 'id=?', whereArgs: [id]);

  static Future<void> _createHealth(Database d) async {
    await d.execute('CREATE TABLE IF NOT EXISTS health(id INTEGER PRIMARY KEY AUTOINCREMENT, client_id TEXT UNIQUE, ts INTEGER, hr INTEGER, spo2 INTEGER, temp REAL, steps INTEGER, battery INTEGER, source TEXT, queued INTEGER DEFAULT 0)');
    await d.execute('CREATE INDEX IF NOT EXISTS idx_health_ts ON health(ts)');
  }

  // ---- emergencias ----
  static Future<void> insertEmergency(String id, String source) async {
    final d = await open();
    await d.insert('emergencies', {'id': id, 'started_at': DateTime.now().millisecondsSinceEpoch, 'source': source, 'status': 'ACTIVE'},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> setLocation(String id, double lat, double lon) async {
    final d = await open();
    await d.update('emergencies', {'lat': lat, 'lon': lon}, where: 'id=?', whereArgs: [id]);
  }

  static Future<void> setEmergencyStatus(String id, String status) async {
    final d = await open();
    await d.update('emergencies', {'status': status}, where: 'id=?', whereArgs: [id]);
  }

  static Future<List<Map<String, Object?>>> emergencies() async =>
      (await open()).query('emergencies', orderBy: 'started_at DESC');

  // ---- cola de sincronización ----
  static Future<void> enqueue(String opId, String type, int priority, String payloadJson) async {
    final d = await open();
    await d.insert('sync_queue', {'op_id': opId, 'type': type, 'priority': priority, 'payload': payloadJson, 'created_at': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<List<Map<String, Object?>>> pending() async => (await open())
      .query('sync_queue', where: "state IN ('PENDING','FAILED')", orderBy: 'priority, created_at');

  static Future<int> pendingCount() async => (await pending()).length;

  static Future<void> markOp(String opId, String state) async {
    final d = await open();
    await d.rawUpdate('UPDATE sync_queue SET state=?, attempts=attempts+1 WHERE op_id=?', [state, opId]);
  }

  // ---- contactos ----
  static Future<List<Map<String, Object?>>> contacts() async => (await open()).query('contacts', orderBy: 'priority, id');
  static Future<void> addContact(String name, String phone) async => (await open()).insert('contacts', {'name': name, 'phone': phone});
  static Future<void> removeContact(int id) async => (await open()).delete('contacts', where: 'id=?', whereArgs: [id]);

  /// Borra todos los datos locales (otra persona inicia sesión en este teléfono).
  static Future<void> wipe() async {
    final d = await open();
    for (final t in ['emergencies', 'contacts', 'sync_queue', 'health', 'tracks', 'evidence_files', 'sleep']) {
      await d.delete(t);
    }
  }

  // ---- salud ----
  static Future<void> insertReading(Reading r) async =>
      (await open()).insert('health', r.toMap()..['queued'] = r.source == 'sim' ? 1 : 0, conflictAlgorithm: ConflictAlgorithm.ignore);

  static Future<List<Reading>> readingsSince(int sinceMs) async =>
      [for (final m in await (await open()).query('health', where: 'ts>=?', whereArgs: [sinceMs], orderBy: 'ts')) Reading.fromMap(m)];

  /// Lecturas reales aún no encoladas para el backend.
  static Future<List<Reading>> unqueuedReadings(int limit) async => [
        for (final m in await (await open()).query('health', where: 'queued=0', orderBy: 'ts', limit: limit)) Reading.fromMap(m)
      ];

  static Future<void> markQueued(List<Reading> rs) async {
    final d = await open();
    final b = d.batch();
    for (final r in rs) {
      b.update('health', {'queued': 1}, where: 'client_id=?', whereArgs: [r.clientId]);
    }
    await b.commit(noResult: true);
  }

  /// Conserva 30 días como máximo para no llenar el teléfono.
  static Future<void> pruneReadings() async => (await open())
      .delete('health', where: 'ts<?', whereArgs: [DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch]);
}
