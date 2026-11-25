# Cambios en android/ tras `flutter create`

1. `android/app/build.gradle(.kts)`: `minSdk = 29`, `targetSdk = 34`.
2. `android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true"/>
```
3. Dentro de `<application>`:
```xml
<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
         android:foregroundServiceType="connectedDevice" android:exported="false"/>
```
4. Si el backend usa HTTP en desarrollo, añade `android:usesCleartextTraffic="true"` solo en debug.

## Ícono de la app (logo AEGIS)
Después de `flutter create .` ejecuta: `bash tools/install_icon.sh` (en Windows, Git Bash) o copia a mano las
carpetas `android_icons/mipmap-*` dentro de `android/app/src/main/res/` reemplazando los archivos existentes.

## Primer uso
1. Entra con `superadmin` / `admin123` → te obliga a cambiar la contraseña y a activar MFA.
2. Pestaña **Usuarios** → "+" para crear cuentas; cada usuario cambia su contraseña al primer ingreso.
3. Los mensajes reales (SMS) solo salen si configuras `NOTIFY_PROVIDER` en Railway; si no, la app abre tu app de SMS.

## Permisos de grabación y GPS en segundo plano (AndroidManifest.xml)
Dentro de `<manifest>` añade:
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>
```
y dentro de `<application>` el servicio del plugin con los tipos que usamos:
```xml
<service android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
         android:foregroundServiceType="connectedDevice|location|microphone" android:exported="false"/>
```
Android 14 exige estos tipos; sin ellos la app se cierra al iniciar el servicio o al grabar con la pantalla apagada.
