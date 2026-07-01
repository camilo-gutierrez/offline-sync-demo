/// Patrón offline-first reutilizable para subir archivos (p. ej. imágenes)
/// de forma confiable sobre redes intermitentes.
///
/// Diseñado como librería Dart pura para que el núcleo del patrón sea
/// testeable sin Flutter, sin red real y sin sistema de archivos real.
library offline_sync_demo;

export 'src/backoff.dart';
export 'src/queue_store.dart';
export 'src/sync_engine.dart';
export 'src/upload_task.dart';
export 'src/uploader.dart';
