# Protocolo AEGIS v1.1 — pulsera ↔ app (contrato para el firmware)

Todo lo que el firmware debe cumplir. La app (Dart) y el backend ya lo implementan; el firmware se escribe contra este documento.

## Marco
`ver(1) tipo(1) flags(1) seq(2 LE) len(2 LE) payload CRC16-CCITT-FALSE(2 LE)`. Versión 1. Marco con CRC o versión inválidos = se descarta.

## GATT
Servicio `aab5d599-d6ce-40dd-aca0-d30900dbf06c`

| Característica | UUID | Uso |
|---|---|---|
| SOS_EVENT | 63d6e2d3-… | indicate: SOS_START, SOS_CANCEL, BUTTON, BAND_ALERT |
| COMMAND | c88eee2d-… | write: ACK, CONFIG, COMMAND |
| COMMAND_RESP | 37e43c76-… | indicate: respuestas |
| STATUS | 6fd6aae5-… | notify: HEALTH (cada 2 s con la app conectada) |

## Tipos
| Tipo | Valor | Sentido | Payload |
|---|---|---|---|
| SOS_START | 1 | P→A | origen (1 B). Con reintentos hasta recibir ACK (ya implementado) |
| SOS_CANCEL | 2 | P→A | — |
| ACK | 10 | A→P | — (seq del marco confirmado) |
| HEARTBEAT | 11 | P→A | — |
| HEALTH | 12 | P→A | hr u8 · spo2 u8 · temp u16 LE (0,01 °C) · pasos u32 LE · batería u8 (0xFF = desconocida). 0 = sin lectura |
| BUTTON | 13 | P→A | gesto u8 |
| CONFIG | 14 | A→P | sos_hold_s u8 (2-5) · flags u8 · arm_s u8 (2-10) |
| COMMAND | 15 | A→P | cmd u8 · arg u8 [· u32 LE] |
| BAND_ALERT | 16 | P→A | código u8 · valor u8 |

### Gestos (BUTTON)
1 SOS doble · 2 SOS triple · 3 AUX corta · 4 AUX doble · 5 AUX mantenida (≥1,5 s).
**Mantener SOS (`sos_hold_s`, 3 s por defecto) = SOS_START y es fijo**: no depende de la app ni de la configuración.
El firmware NO decide qué hace cada gesto: solo lo reporta; la app lo traduce (mensaje rápido, ubicación, check-in, buscar teléfono, llamada falsa…) según los ajustes del usuario guardados en el backend (`/me/settings`).
Si no hay enlace BLE, el firmware da feedback háptico de "sin conexión" (3 vibraciones cortas) y encola el gesto 60 s.

### Flags de CONFIG
bit0 detección de caídas · bit1 módulo de defensa habilitado · bit2 háptica. Se persisten en NVS y se reaplican al reiniciar.

### Comandos (COMMAND)
1 FIND (arg = segundos de zumbador+vibración, máx. 30) · 2 VIBRATE (arg = patrón) · 3 TIME_SYNC (+ epoch u32) · 4 SPRAY_DISARM · 5 REC_START (arg 1 audio, 2 foto, 3 video) · 6 REC_STOP · 7 SNAPSHOT.

### Alertas (BAND_ALERT)
1 caída (valor = confianza %) · 2 batería baja (valor = %; avisar a 20 % y 10 %) · 3 pulsera quitada · 4 manipulación · 5 defensa armada · 6 defensa activada · 7 defensa desarmada.
La app responde a una caída con cuenta atrás de 30 s y SOS automático si el usuario no la cancela.

## Módulo de defensa (gas pimienta) — RESERVADO
Desactivado por defecto (`flags.bit1 = 0`). Reglas que el firmware debe cumplir cuando exista el hardware:
1. **Doble seguro**: armado con AUX mantenida (acción `spray_arm`) → vibración + LED ámbar + BAND_ALERT(5). Sin armado no hay disparo, aunque llegue cualquier comando.
2. **Disparo solo por acción física** en la pulsera (nunca por un comando remoto de la app). Tras `arm_s` sin disparar se desarma solo (BAND_ALERT 7).
3. Cada disparo → BAND_ALERT(6) + SOS_START automático + registro en NVS.
4. Bloqueo mecánico/eléctrico independiente del firmware (el firmware no puede ser la única protección).
5. Antes de fabricar: revisar la normativa peruana sobre portar/comercializar dispositivos de defensa con agentes irritantes y el transporte (aerolíneas), y la seguridad del cartucho.

## Pendiente de definir al diseñar el hardware
Sensores concretos (FC/SpO2, acelerómetro para caídas, temperatura), actuador del módulo de defensa, carga, OTA firmada por BLE, autenticación HMAC/bonding.


## Cámara y micrófono de la pulsera (v1.2, reservado)
- **Todas las pulseras** llevan sensores, micrófono y cámara. Lo que cambia por plan es el uso: la **grabación automática**
  (SOS, caída, manipulación o a petición) y el **audio/vídeo** son solo de cuentas **Premium**; el servidor lo hace cumplir
  (`plan_feature_audio` / `plan_feature_auto_record`). Las cuentas Normal solo pueden adjuntar fotos a una emergencia.
- **Indicador obligatorio:** mientras graba, LED rojo fijo + una vibración corta al empezar. Nunca grabación oculta.
- La pulsera graba a su memoria (audio AAC mono ≤ 32 kbps, trozos de 30 s) y avisa `BAND_ALERT(8)` al empezar,
  `(9)` al terminar y `(10, n)` cuando hay `n` archivos listos. La app los baja por `MEDIA(17)` y los sube al servidor
  (`POST /emergencies/{id}/evidence/upload`, `source=band`). Hasta que exista este canal, la app graba con el micrófono del teléfono.
- El micrófono y la cámara **no** pueden activarse por un comando si la cuenta no es Premium: la app no envía REC_START.
