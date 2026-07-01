import 'package:offline_sync_demo/offline_sync_demo.dart';
import 'package:test/test.dart';

/// Uploader falso que falla las primeras [failuresRemaining] veces y luego
/// sube con éxito. Permite simular red intermitente de forma determinista.
class FlakyUploader implements Uploader {
  FlakyUploader(this.failuresRemaining);

  int failuresRemaining;
  final List<String> uploaded = <String>[];

  @override
  Future<void> upload(String localPath, String remoteKey) async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw Exception('error de red transitorio');
    }
    uploaded.add(remoteKey);
  }
}

/// Uploader que siempre falla, para ejercitar el camino a dead-letter.
class AlwaysFailUploader implements Uploader {
  @override
  Future<void> upload(String localPath, String remoteKey) async {
    throw Exception('backend caído');
  }
}

class FakeFiles implements LocalFiles {
  final List<String> deleted = <String>[];

  @override
  Future<void> delete(String localPath) async {
    deleted.add(localPath);
  }
}

/// Espera no-op: hace los tests instantáneos sin esperar el backoff real.
Future<void> noDelay(Duration _) async {}

void main() {
  group('backoffFor', () {
    test('crece exponencialmente desde la base', () {
      expect(backoffFor(1).inMilliseconds, 200);
      expect(backoffFor(2).inMilliseconds, 400);
      expect(backoffFor(3).inMilliseconds, 800);
    });

    test('respeta el tope máximo', () {
      expect(backoffFor(20, max: const Duration(seconds: 5)).inSeconds, 5);
    });

    test('rechaza intentos inválidos', () {
      expect(() => backoffFor(0), throwsArgumentError);
    });
  });

  group('SyncEngine', () {
    test('reintenta hasta tener éxito y borra el archivo local', () async {
      final store = InMemoryQueueStore();
      final uploader = FlakyUploader(2); // falla 2 veces, luego sube
      final files = FakeFiles();
      final engine = SyncEngine(
        store: store,
        uploader: uploader,
        files: files,
        delay: noDelay,
      );

      await engine.enqueue(
        id: 'task-1',
        localPath: '/tmp/foto.jpg',
        remoteKey: 'uploads/foto.jpg',
      );

      final report = await engine.sync();

      expect(report.uploaded, 1);
      expect(report.deadLettered, 0);
      expect(uploader.uploaded, ['uploads/foto.jpg']);
      // El archivo local se borra exactamente una vez, tras confirmar subida.
      expect(files.deleted, ['/tmp/foto.jpg']);
      // La cola queda vacía.
      expect(await store.all(), isEmpty);
    });

    test('mueve a dead-letter tras agotar los reintentos', () async {
      final store = InMemoryQueueStore();
      final files = FakeFiles();
      final engine = SyncEngine(
        store: store,
        uploader: AlwaysFailUploader(),
        files: files,
        maxAttempts: 3,
        delay: noDelay,
      );

      await engine.enqueue(
        id: 'task-2',
        localPath: '/tmp/rota.jpg',
        remoteKey: 'uploads/rota.jpg',
      );

      final report = await engine.sync();

      expect(report.uploaded, 0);
      expect(report.deadLettered, 1);
      // Nunca se borra un archivo que no se subió.
      expect(files.deleted, isEmpty);

      final all = await store.all();
      expect(all.single.status, UploadStatus.deadLettered);
      expect(all.single.attempts, 3);
      expect(all.single.lastError, contains('backend caído'));
    });

    test('una tarea dead-lettered no se vuelve a drenar', () async {
      final store = InMemoryQueueStore();
      final engine = SyncEngine(
        store: store,
        uploader: AlwaysFailUploader(),
        files: FakeFiles(),
        maxAttempts: 1,
        delay: noDelay,
      );

      await engine.enqueue(
        id: 'task-3',
        localPath: '/tmp/x.jpg',
        remoteKey: 'uploads/x.jpg',
      );

      await engine.sync(); // la deja en dead-letter
      final second = await engine.sync(); // no debería tocarla de nuevo

      expect(second.uploaded, 0);
      expect(second.deadLettered, 0);
    });
  });
}
