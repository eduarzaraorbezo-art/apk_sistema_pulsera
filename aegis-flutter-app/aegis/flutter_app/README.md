# AEGIS app (Flutter, Fase 4 MVP) — SIN COMPILAR

Reemplaza a la versión Kotlin. Escrita sin Flutter SDK ni red: **no se ha compilado ni ejecutado**; espera errores
menores (versiones de paquetes, API de plugins). Pásame la salida de `flutter run` y los corrijo.

## Puesta en marcha con Visual Studio Code
1. Instala Flutter SDK (flutter.dev), Android SDK (con Android Studio instalado solo como proveedor del SDK, o `cmdline-tools`) y en VS Code las extensiones **Flutter** y **Dart**.
2. En una carpeta nueva: `flutter create --org com.aegis --project-name aegis_app .`
3. Copia encima `pubspec.yaml`, `lib/` y `test/` de este proyecto y ejecuta `flutter pub get`.
4. Aplica los cambios de Android de `ANDROID_SETUP.md`.
5. Conecta un teléfono Android real (BLE no funciona en emulador) y `flutter run`. Pruebas: `flutter test`.
   Para apuntar al backend: `flutter run --dart-define=API_BASE=https://tu-dominio`.

## Novedades v0.2 (interfaz estilo iOS)
5 pestañas: **Inicio** (estado de la pulsera, SOS con anillo de pulsación larga, acciones rápidas, pulsaciones en vivo, SpO2/temperatura/pasos),
**Salud** (gráfica de FC en vivo/1 h/24 h/7 d con umbrales, mín/prom/máx, modo demostración), **Seguridad** (check-in "avísame si no confirmo" con cuenta atrás,
lugares seguros), **Contactos** (llamar/SMS, compartir ubicación), **Perfil** (cuenta, ficha médica, umbrales de FC, tema claro/oscuro, sincronización).
Alerta de FC tras 3 lecturas seguidas fuera de rango (no dispara SOS sola: pregunta "¿Estás bien?"). Lecturas guardadas offline y enviadas al backend (`telemetry`).
La pulsera envía salud con el marco tipo 12 por la característica STATUS (formato en `lib/ble/protocol.dart` y `firmware/main/protocol.h`);
el firmware aún **no tiene el sensor de pulso**: hasta entonces usa "Modo demostración" (Salud → Herramientas).
Cambios de Android obligatorios: ver ANDROID_SETUP.md (desugaring, Gradle ≤ 8.x/AGP, workmanager ^0.9).

## Implementado (v0.1)
SOS por BLE (indication + ACK + CRC), guardado local primero (sqflite), ubicación, notificación, cola de sincronización
con WorkManager (backoff, idempotencia por op_id, emergencias primero), estados ONLINE/OFFLINE/SYNCING/PENDING, última sync,
SOS en pantalla (pulsación larga), marcado asistido 105/116/106/100, contactos, login. Protocolo idéntico al firmware.

## Riesgos / pendiente
- **Segundo plano**: el servicio en primer plano mantiene viva la app, pero la conexión BLE corre en el isolate principal; si Android lo
  destruye al cerrar la app deslizándola, el SOS de la pulsera no llegaría. Hay que probarlo en varias marcas; si falla, se mueve el BLE al
  isolate del servicio o se vuelve a nativo (Kotlin) solo para esa parte.
- Sin: bonding/HMAC, transferencia de evidencias, OTA, sensores, cámara/audio/vídeo, FCM, refresh de token, tests de widgets,
  iOS, módulos separados.
