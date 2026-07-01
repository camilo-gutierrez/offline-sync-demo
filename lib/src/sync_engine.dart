import 'backoff.dart';
import 'queue_store.dart';
import 'upload_task.dart';
import 'uploader.dart';

/// Resultado agregado de una pasada de sincronización.
class SyncReport {
  const SyncReport({
    required this.uploaded,
    required this.deadLettered,
  });

  /// Tareas subidas con éxito (y cuyo archivo local fue borrado).
  final int uploaded;

  /// Tareas que agotaron reintentos y quedaron en dead-letter.
  final int deadLettered;

  @override
  String toString() =>
      'SyncReport(uploaded=$uploaded, deadLettered=$deadLettered)';
}

/// Orquesta el patrón offline-first:
///
/// 1. [enqueue] persiste la intención de subir (la app sigue usable offline).
/// 2. [sync] drena la cola cuando hay conectividad, reintentando con backoff.
/// 3. Tras una subida confirmada, borra el archivo local y saca la tarea.
/// 4. Si se agotan los reintentos, mueve la tarea a dead-letter sin perderla.
class SyncEngine {
  SyncEngine({
    required this.store,
    required this.uploader,
    required this.files,
    this.maxAttempts = 5,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final QueueStore store;
  final Uploader uploader;
  final LocalFiles files;

  /// Reintentos máximos antes de mover una tarea a dead-letter.
  final int maxAttempts;

  /// Espera inyectable: en tests se pasa un no-op para correr al instante.
  final Future<void> Function(Duration) _delay;

  /// Encola un archivo para subida diferida. No bloquea ni toca la red.
  Future<void> enqueue({
    required String id,
    required String localPath,
    required String remoteKey,
  }) async {
    await store.put(
      UploadTask(
        id: id,
        localPath: localPath,
        remoteKey: remoteKey,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Drena la cola una vez. Se invoca al recuperar conectividad o
  /// periódicamente desde un worker de fondo.
  Future<SyncReport> sync() async {
    final pending = await store.drainable();
    var uploaded = 0;
    var deadLettered = 0;

    for (final task in pending) {
      final outcome = await _process(task);
      if (outcome == UploadStatus.deadLettered) {
        deadLettered++;
      } else {
        uploaded++;
      }
    }

    return SyncReport(uploaded: uploaded, deadLettered: deadLettered);
  }

  Future<UploadStatus> _process(UploadTask task) async {
    var current = task;

    while (true) {
      current = current.copyWith(
        status: UploadStatus.uploading,
        attempts: current.attempts + 1,
      );
      await store.put(current);

      try {
        await uploader.upload(current.localPath, current.remoteKey);
        // Orden crítico: solo borramos el archivo local DESPUÉS de que el
        // backend confirma. Si el borrado fallara, el archivo simplemente
        // queda huérfano (recuperable), nunca se pierde sin haber subido.
        await files.delete(current.localPath);
        await store.remove(current.id);
        return UploadStatus.uploading; // éxito
      } catch (error) {
        if (current.attempts >= maxAttempts) {
          current = current.copyWith(
            status: UploadStatus.deadLettered,
            lastError: error.toString(),
          );
          await store.put(current);
          return UploadStatus.deadLettered;
        }
        current = current.copyWith(
          status: UploadStatus.failed,
          lastError: error.toString(),
        );
        await store.put(current);
        await _delay(backoffFor(current.attempts));
      }
    }
  }
}
