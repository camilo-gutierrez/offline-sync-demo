# offline-sync-demo

[![CI](https://github.com/camilo-gutierrez/offline-sync-demo/actions/workflows/ci.yml/badge.svg)](https://github.com/camilo-gutierrez/offline-sync-demo/actions/workflows/ci.yml)

Patrón **offline-first** de cola de subida de archivos, reutilizable y verificable, extraído de problemas reales de apps móviles con conectividad intermitente. Dart puro, con tests, **sin propiedad intelectual de terceros**.

> Implementación genérica y original del patrón. No contiene código de ningún producto de empresa.

---

## Problema

En apps móviles de campo (delivery, healthtech, marketplaces) el usuario captura fotos donde **no hay red estable**. Si la subida se hace de forma síncrona:

- la UI se bloquea o falla cuando no hay señal,
- un corte de red pierde la captura,
- reintentar a ciegas satura el backend cuando todos vuelven a estar en línea,
- y borrar el archivo local antes de confirmar la subida **pierde datos del usuario**.

## Solución

Una cola de subida desacoplada de la UI: capturar **encola** y la app sigue usable; un motor de sincronización **drena** la cola cuando hay conectividad, con reintentos controlados, y solo borra el archivo local **después** de que el backend confirma.

## Arquitectura

```
                 enqueue()                       sync()
   Captura  ─────────────────►  QueueStore  ◄───────────────  SyncEngine
   (UI)                         (persistente)                 │
                                                              ├─► Uploader  (red)
                                                              └─► LocalFiles (disco)

   pending ──► uploading ──► (éxito) ─► borra local ─► remove de la cola
                      │
                      └─► (falla) ─► backoff exponencial ─► reintento
                                          │
                                          └─► agota intentos ─► dead-letter
```

- **`UploadTask`** — unidad de trabajo inmutable con estado (`pending → uploading → failed → deadLettered`).
- **`QueueStore`** — persistencia abstracta (en memoria para tests; Hive/SQLite en prod).
- **`Uploader` / `LocalFiles`** — contratos inyectables: el núcleo no conoce Firebase ni el FS real.
- **`SyncEngine`** — orquesta drenado, reintentos con backoff y dead-letter.

## Tecnologías

- Dart 3 (librería pura, sin Flutter en el núcleo → testeable sin emulador).
- `package:test`, `package:lints`.
- Diseño portable a Flutter + Firebase Storage / S3 cambiando solo las implementaciones de `Uploader` y `LocalFiles`.

## Decisiones técnicas

| Decisión | Por qué |
|---|---|
| Núcleo en Dart puro, sin Flutter | El patrón se testea en milisegundos sin emulador; la UI es un detalle. |
| `Uploader`/`LocalFiles`/`QueueStore` inyectables | Permite probar reintentos y borrado con dobles de prueba, sin red ni disco. |
| Borrar local **después** de confirmar subida | Si el borrado falla, el archivo queda huérfano (recuperable), nunca se pierde sin subir. |
| Backoff exponencial **determinista** en el core | Comportamiento verificable en tests. El jitter (anti *thundering herd*) se suma en la capa de producción. |
| Dead-letter en vez de descartar | Una tarea que agota reintentos se conserva para inspección/reintento manual, no se pierde silenciosamente. |
| `id` estable por tarea | Idempotencia: reintentar no duplica subidas. |

## Funcionalidades

- Cola de subida persistente y desacoplada de la UI.
- Reintentos con backoff exponencial y tope.
- Dead-letter tras agotar intentos.
- Borrado seguro del archivo local tras subida confirmada.
- Reporte agregado por pasada (`uploaded`, `deadLettered`).

## Testing

Tres grupos de tests deterministas (la espera del backoff se inyecta como no-op):

- backoff: progresión exponencial, tope y validación de entrada;
- éxito tras N fallos transitorios + verificación de borrado local;
- camino a dead-letter y no-reprocesamiento de tareas muertas.

```
dart pub get
dart test
# 6/6 All tests passed!
```

## Cómo ejecutar

```bash
git clone https://github.com/camilo-gutierrez/offline-sync-demo
cd offline-sync-demo
dart pub get
dart test
```

## Estado actual

Núcleo del patrón completo y cubierto por tests. Pensado como **referencia de patrón**, no como paquete publicado en pub.dev.

## Limitaciones

- `InMemoryQueueStore` no persiste entre ejecuciones (en prod: Hive/SQLite/SharedPreferences).
- `sync()` drena secuencialmente; un escenario real añadiría concurrencia acotada y disparo por cambio de conectividad (`connectivity_plus`).
- Sin jitter en el core (decisión deliberada por testabilidad).

## Aprendizajes

- El orden *subir → confirmar → borrar* es la diferencia entre "perdimos la foto del cliente" y "no pasa nada".
- Inyectar tiempo (el `delay`) convierte un test de 30 s en uno de 3 ms.
- Un dead-letter explícito evita el peor bug de sync: el silencioso.