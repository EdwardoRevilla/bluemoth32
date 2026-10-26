# BlueMoth32

Nombre del proyecto: **BlueMoth32**. Slug sugerido para GitHub: **bluemoth32**.
Descripcion corta: `Experimental ESP32 HCI bridge for Windows Bluetooth`.

El simbolo es una polilla, no una copia de la pina de WiFi Pineapple. La imagen
de referencia inspira el tratamiento de terminal y la idea de una mascota ASCII.

- **Blue**: Bluetooth, el enlace que se quiere integrar con Windows.
- **Moth**: polilla. Sus antenas evocan una radio y las alas los extremos del puente.
- **32**: el ESP32 real del proyecto; el chip ocupa el cuerpo de la mascota.

Firma verbal: **Un puente para desplegar tus conexiones.**

## Tratamiento visual

- Fondo: `#0c0e0c`, casi negro.
- Mascota y acciones principales: `#00ff00`, verde fosforo de terminal.
- Rutas y separadores: `#008000`, verde atenuado.
- Texto secundario: `#c0c0c0`, gris legible.
- Advertencias: amarillo; errores: rojo. Los colores mantienen su significado.
- Tipografia: Consolas/Cascadia Mono; ASCII de ancho fijo sin caracteres especiales.
- Composicion: una mascota central, nombre espaciado debajo y menu numerico real.

La figura, no una animacion de arranque ficticia, es la firma de la interfaz.
No se muestran sesiones SSH, usuarios root, paquetes ficticios ni conexiones
inventadas. El modo Preview se identifica; el diagnostico usa datos del equipo.
No hay parpadeos, efectos de escritura ni dependencias de red para el tema.

El ASCII fuente esta en `windows-driver/installer/Terminal.psm1`. La vista previa
SVG y PNG se generan con `tools/render_terminal_preview.py`, usando el mismo ASCII
y los mismos textos que el modulo. El SVG sirve tambien como cabecera del README.

La identidad se aplica a la interfaz, comandos, documentacion y nombre del ZIP.
El servicio y los identificadores Esp32HciBus permanecen estables. Este cambio
visual no implica que el driver ya haya sido cargado o validado en Windows.

Repositorio: [EdwardoRevilla/bluemoth32](https://github.com/EdwardoRevilla/bluemoth32).
La identidad del proyecto no constituye una reserva de marca o nombre.
