# AEGIS firmware (Fase 3, MVP) — SIN COMPILAR

Escrito para ESP-IDF 5.x (NimBLE), objetivo ESP32-S3 (XIAO ESP32S3 Sense). **No hay ESP-IDF en el entorno donde se
generó, así que no se ha compilado ni probado en hardware.** Verificado solo: `main/protocol.c` compilado con gcc en PC
y su prueba `test/test_protocol.c` (CRC, ida y vuelta, CRC corrupto, versión desconocida).

```bash
# En PC (sin hardware):
gcc -Wall -Wextra -Imain test/test_protocol.c main/protocol.c -o /tmp/tp && /tmp/tp
# Con ESP-IDF instalado y la placa conectada:
idf.py set-target esp32s3 && idf.py build flash monitor
```
Si falla la compilación, pásame la salida y lo corrijo.

## Implementado
- SOS: mantener el botón SOS 2 s (vibración a mitad como aviso). Se guarda en NVS antes de enviar, vibra, parpadea LED rojo,
  envía por indication BLE y reintenta cada 3 s hasta recibir ACK. Sobrevive a reinicios. No depende de teléfono ni Internet.
- AUX: pulsación corta = modo silencioso; mantener 2 s = cancelar SOS.
- GATT AEGIS v1 (SOS indicate, comando write cifrado, respuesta, estado), publicidad con UUID del servicio, reconexión.
- Protocolo con CRC16 y versión, idéntico al de la APK.
- Particiones OTA duales y rollback activados; el firmware se confirma a los 15 s de arrancar bien.

## Pendiente (NO implementado)
Cámara y almacenamiento en microSD, transferencia de evidencias, sensores (BMI270, MAX30102, batería), OTA por BLE con
verificación de firma, autenticación HMAC por pulsera, light sleep con despertar por interrupción, persistencia del modo
silencioso, heartbeat, diagnóstico, pruebas en hardware. Pinout en `main/pins.h` es preliminar: confirmar con Seeed.
