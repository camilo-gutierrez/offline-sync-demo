import 'upload_task.dart';

/// Persistencia de la cola de subida.
///
/// En producción se respalda con SharedPreferences/Hive/SQLite para
/// sobrevivir a cierres de la app. Aquí se abstrae para inyectar una
/// implementación en memoria en los tests.
abstract interface class QueueStore {
  /// Inserta o actualiza una tarea por su [UploadTask.id].
  Future<void> put(UploadTask task);

  /// Elimina la tarea de la cola (subida completada y confirmada).
  Future<void> remove(String id);

  /// Tareas que aún requieren trabajo (no dead-lettered).
  Future<List<UploadTask>> drainable();

  /// Snapshot de todas las tareas, incluido dead-letter.
  Future<List<UploadTask>> all();
}

/// Implementación en memoria. Determinista: preserva orden de inserción,
/// lo que da un drenado FIFO predecible para los tests.
class InMemoryQueueStore implements QueueStore {
  final Map<String, UploadTask> _tasks = <String, UploadTask>{};

  @override
  Future<void> put(UploadTask task) async {
    _tasks[task.id] = task;
  }

  @override
  Future<void> remove(String id) async {
    _tasks.remove(id);
  }

  @override
  Future<List<UploadTask>> drainable() async {
    return _tasks.values
        .where((t) => t.status != UploadStatus.deadLettered)
        .toList(growable: false);
  }

  @override
  Future<List<UploadTask>> all() async {
    return _tasks.values.toList(growable: false);
  }
}