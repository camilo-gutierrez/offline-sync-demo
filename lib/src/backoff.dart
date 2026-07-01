/// Calcula el tiempo de espera antes del siguiente reintento usando
/// backoff exponencial con tope.
///
/// [attempt] es el número de intento ya realizado (1 = primer fallo).
/// La espera crece como `base * 2^(attempt-1)` y nunca supera [max].
///
/// Decisión: se mantiene determinista (sin jitter aleatorio) para que el
/// comportamiento sea verificable en tests. En producción se suma jitter
/// para evitar el efecto "thundering herd" cuando muchos clientes vuelven
/// a estar en línea a la vez (ver README › Decisiones técnicas).
Duration backoffFor(
  int attempt, {
  Duration base = const Duration(milliseconds: 200),
  Duration max = const Duration(seconds: 30),
}) {
  if (attempt < 1) {
    throw ArgumentError.value(attempt, 'attempt', 'debe ser >= 1');
  }
  // Tope del exponente para evitar desbordamiento en cadenas muy largas.
  final exponent = attempt - 1 > 32 ? 32 : attempt - 1;
  final scaled = base.inMilliseconds * (1 << exponent);
  final capped = scaled > max.inMilliseconds ? max.inMilliseconds : scaled;
  return Duration(milliseconds: capped);
}