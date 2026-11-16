# J Sensor Hub — Edición Google Pixel (`droid` VM / Android 16 / J9.7)

Plataforma web de monitoreo, álgebra de arreglos y control de sensores construida en **[J (J9.7 ARM64)](https://www.jsoftware.com/#/)** y adaptada específicamente para el entorno **Linux Terminal de Google Pixel (`droid` / Crosvm / Kernel 6.12 Android 16)**.

---

## 📱 Cómo abrirlo en tu Google Pixel

1. En la terminal de Linux (`droid`), inicia el servidor J:
   ```bash
   /home/droid/j-sensor-hub/start.sh 8080
   ```
2. El agente de la VM de tu Pixel (`linux_vm_manager`) detectará automáticamente que el puerto **`8080`** está escuchando en `0.0.0.0:8080`:
   - Si te aparece la notificación de **Terminal → Port forwarding**, acepta reenviar el puerto **8080** (o actívalo en el icono de **Port control / Reenvío de puertos** de la app Terminal de Android).
3. Abre **Chrome en tu Google Pixel** y entra en:
   - **`http://localhost:8080`**
   - *(Al entrar por `localhost`, Chrome Android habilita el **Contexto Seguro (`isSecureContext`)**, permitiendo conectar el acelerómetro, giroscopio, brújula, presión táctil OLED, micrófono, batería, motor háptico y bloqueo de pantalla activa de tu Pixel).*

---

## 🔬 Compatibilidad Específica con Google Pixel (`droid`)

### 1. Sensores Internos de la VM Linux del Pixel (Leídos Nativamente por J)
- **Topología Google Tensor G4 Tri-Cluster (`/proc/stat` y `/proc/cpuinfo`)**:
  - **Cluster Eficiencia (`cpu0`–`cpu3`)**: 4× ARM Cortex-A520 (`0xd80`)
  - **Cluster Rendimiento (`cpu4`–`cpu6`)**: 3× ARM Cortex-A720 (`0xd81`)
  - **Núcleo Prime (`cpu7`)**: 1× ARM Cortex-X4 (`0xd82`)
  - J calcula tanto el uso por cada uno de los 8 núcleos como el promedio vectorial de cada cluster (`mean 0 1 2 3 { cores`, `mean 4 5 6 { cores`, `7 { cores`).
- **Interfaz de Red Virtio del Pixel (`/sys/class/net/enp0s14/statistics/*`)**:
  - Lee directamente de `sysfs` los bytes y paquetes `rx_bytes`, `tx_bytes`, `rx_packets`, `tx_packets` de `enp0s14` (incluso dentro de namespaces aislados) y calcula los KB/s en vivo.
- **Memoria RAM y Swap Comprimido ZRAM (`/proc/meminfo` y `zram0`)**:
  - Monitoreo de RAM de la VM, memoria disponible y porcentaje de `zram0`.
- **Sensores PSI del Kernel Android 16 (`/proc/pressure/cpu`, `io`, `memory`, `irq`)**:
  - Métricas de presión (stall) del kernel `6.12-android16`.
- **Almacenamiento Virtio (`/proc/diskstats` - `vda` + `zram0`)** y **Periféricos Crosvm (`/sys/class/rtc/rtc0`, `/sys/class/drm/card0-Virtual-1`, `/sys/class/input/input0..3`)**.

### 2. Sensores Físicos y Actuadores del Google Pixel (Chrome Android → Motor J)
- **IMU 6-DOF + Brújula (`DeviceMotionEvent` / `DeviceOrientationEvent`)**: Acelerómetro 3D (`ax, ay, az` con norma euclidiana `%: +/ *: x,y,z` en J), Giroscopio (`α, β, γ`) y rumbo magnético.
- **Pantalla Táctil OLED del Pixel (`PointerEvent` / `TouchEvent`)**: Presión táctil (`pressure`/`force`), puntos multi-touch simultáneos y velocidad cinética en `px/s`.
- **Acústica, Batería y Entorno**: Decibelios en tiempo real desde el micrófono del Pixel (WebAudio FFT/RMS), nivel y estado de carga de la batería del Pixel (`navigator.getBattery()`), sensor de luz (`AmbientLightSensor`) y RTT de red.
- **Actuadores Físicos del Pixel**:
  - **Motor Háptico del Pixel (`navigator.vibrate`)**: Vibración háptica física al superar umbrales en J o mediante el botón de prueba.
  - **Screen Wake Lock (`navigator.wakeLock`)**: Mantiene encendida la pantalla OLED del Pixel mientras monitoreas los sensores.
  - **Sirena Acústica WebAudio** y **3 LEDs lógicos con reglas automáticas en J**.
- **Optimización para Chrome Android**:
  - El servidor de sockets en [`server.ijs`](/home/droid/j-sensor-hub/server.ijs) usa `sdselect_jsocket_` no bloqueante de `150ms` para cerrar al instante los sockets de pre-conexión especulativa que abre Chrome en Android sin retrasar el bucle de telemetría.
