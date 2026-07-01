/// Estados por los que transita una tarea de subida dentro de la cola.
enum UploadStatus {
  /// Encolada, aún no intentada.
  pending,

  /// Intento de subida en curso.
  uploading,

  /// Falló el último intento pero aún quedan reintentos disponibles.
  failed,

  /// Agotó los reintentos: se mueve a dead-letter para inspección manual.
  deadLettered,
}

/// Unidad de trabajo de la cola de subida.
///
/// Es inmutable: cada transición produce una copia nueva vía [copyWith],
/// de modo que el store siempre persiste un valor consistente.
class UploadTask {
  const UploadTask({
    required this.id,
    required this.localPath,
    required this.remoteKey,
    required this.createdAt,
    this.attempts = 0,
    this.status = UploadStatus.pending,
    this.lastError,
  });

  /// Identificador estable de la tarea (idempotencia en reintentos).
  final String id;

  /// Ruta del archivo en el dispositivo, a borrar tras subida exitosa.
  final String localPath;

  /// Clave/destino remoto bajo el cual se almacena el archivo.
  final String remoteKey;

  /// Número de intentos ya realizados.
  final int attempts;

  final UploadStatus status;

  /// Mensaje del último fallo, útil para diagnóstico en dead-letter.
  final String? lastError;

  final DateTime createdAt;

  UploadTask copyWith({
    int? attempts,
    UploadStatus? status,
    Object? lastError = _sentinel,
  }) {
    return UploadTask(
      id: id,
      localPath: localPath,
      remoteKey: remoteKey,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      status: status ?? this.status,
      lastError: identical(lastError, _sentinel)
          ? this.lastError
          : lastError as String?,
    );
  }

  @override
  String toString() =>
      'UploadTask($id, $status, attempts=$attempts, key=$remoteKey)';
}

/// Centinela para distinguir "no se pasó lastError" de "lastError = null".
const Object _sentinel = Object();