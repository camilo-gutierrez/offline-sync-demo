/// Contrato de subida al backend (Firebase Storage, S3, etc.).
///
/// El motor de sincronización depende de esta abstracción, no de una
/// implementación concreta. Eso permite testear la lógica de cola y
/// reintentos con un uploader falso, sin red real.
abstract interface class Uploader {
  /// Sube el archivo en [localPath] bajo [remoteKey].
  /// Debe lanzar una excepción si la subida falla (red, permisos, etc.).
  Future<void> upload(String localPath, String remoteKey);
}

/// Contrato de acceso al sistema de archivos local.
///
/// Se inyecta para poder verificar en tests que el archivo se borra
/// exactamente cuando la subida fue confirmada, sin tocar disco real.
abstract interface class LocalFiles {
  /// Borra el archivo local. Se invoca solo tras una subida confirmada.
  Future<void> delete(String localPath);
}
