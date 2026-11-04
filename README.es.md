<p align="center"><img src="docs/images/icon.png" width="120" alt="Icono de Nunsseop"></p>

<h1 align="center">Nunsseop</h1>

<p align="center">
  <b>El notch de tu MacBook, por fin útil.</b><br>
  Música, llamadas, archivos, un lanzador al estilo Spotlight, uso de IA, notificaciones de agentes, tu calendario y HUDs del sistema, todo a un gesto del puntero.
</p>

<p align="center">
  <a href="https://github.com/namekun/Nunsseop/releases/latest"><img src="https://img.shields.io/github/v/release/namekun/Nunsseop?color=111111&label=release" alt="Última versión"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14 o posterior">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-555555" alt="Licencia MIT"></a>
  <img src="https://img.shields.io/badge/Swift-native-orange?logo=swift&logoColor=white" alt="Swift nativo">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.ko.md">한국어</a> · <a href="README.ja.md">日本語</a> · <a href="README.zh-Hans.md">简体中文</a> · <b>Español</b> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="https://namekun.github.io/Nunsseop/">Sitio web</a>
</p>

<p align="center">
  <img src="docs/images/home.png" width="720" alt="Notch desplegado con la música en reproducción, el calendario y el tiempo">
</p>

*Nunsseop* (눈썹) significa *ceja* en coreano, ese pequeño arco sobre tu pantalla. Es gratuita, de código abierto y sin cuenta, suscripción ni rastreo.

## Instalación en 30 segundos

**[Descarga Nunsseop.dmg](https://github.com/namekun/Nunsseop/releases/latest/download/Nunsseop.dmg)**, ábrelo y arrastra Nunsseop a Aplicaciones. La app está firmada y notarizada por Apple, así que se abre sin problemas. Cuando hay una versión nueva, Instalar actualización en Ajustes › General › Actualizaciones muestra las novedades, la instala y reinicia Nunsseop (las copias anteriores a la 0.38.0 descargan el DMG nuevo una vez más).

O con [Homebrew](https://brew.sh):

```sh
brew install --cask namekun/tap/nunsseop
```

Para actualizar, ejecuta `brew update && brew upgrade --cask nunsseop`; cuando hay una versión nueva, Ajustes › General › Actualizaciones copia ese comando al portapapeles.

Requiere macOS 14 Sonoma o posterior. Funciona en Mac con Apple silicon (no en Intel), también en pantallas sin notch.

## Tu primer minuto

1. **Pasa el puntero sobre el notch.** Se abre. Aparta el puntero y vuelve a plegarse solo.
2. **Reproduce algo** en Música, Spotify, YouTube Music o cualquier navegador. El notch lo detecta y, plegado, muestra una pequeña carátula y un visualizador.
3. **Haz clic derecho en el notch → Ajustes** para elegir las pestañas, su orden, las ventanas emergentes que quieres y el tamaño.

No hay icono en el Dock. Nunsseop vive en el notch.

En una instalación nueva, el notch también se abre solo al cabo de un segundo y te guía en cuatro pasos breves: cómo se abre y se cierra, las pestañas, archivos y búsqueda, y conectar las herramientas de agentes que se encuentran en este Mac (o, si no hay ninguna, «Todo listo»). «Omitir», Esc o «Listo» la termina, y Ajustes › General › «Ver la guía otra vez» la reproduce de nuevo. Tras una actualización se abre una vez para contar las novedades de esa versión y luego te deja tranquilo.

## Un vistazo al interior

| | |
| :---: | :---: |
| <img src="docs/images/tab-search.png" alt="Buscar mostrando una app, un comando y un ajuste"><br>**Buscar.** Un lanzador de apps, archivos, comandos, portapapeles, emojis y cálculos, con el atajo que prefieras. | <img src="docs/images/tab-ai.png" alt="Uso de IA de Claude Code y Codex"><br>**Uso de IA.** Los límites de Claude Code y Codex, sin iniciar sesión. |
| <img src="docs/images/shelf.png" alt="Estante de archivos con los detalles del archivo elegido y AirDrop"><br>**Estante.** Deja archivos en el notch o suéltalos en AirDrop. | <img src="docs/images/tab-timer.png" alt="Pestaña Temporizador"><br>**Temporizador.** Cuenta atrás, Pomodoro y cronómetro, con la duración que quieras. |
| <img src="docs/images/tab-tools.png" alt="Pestaña Herramientas"><br>**Herramientas.** Salida de audio, silenciar el micrófono, mantener activo el Mac, grabación de pantalla, selector de color y captura de texto. | <img src="docs/images/tab-system.png" alt="Pestaña Sistema con la batería de los dispositivos"><br>**Sistema.** CPU, memoria, disco, red y batería de los dispositivos. |
| <img src="docs/images/tab-emoji.png" alt="Selector de emojis con una lista de categorías"><br>**Emoji.** Categorías a la izquierda, todos los emojis con búsqueda y un clic para copiar. | <img src="docs/images/hud-headphones.png" alt="HUD de batería de los auriculares"><br>**HUDs.** Volumen, brillo, batería de los AirPods y más. |
| <img src="docs/images/collapsed-call.png" alt="Notch plegado durante una llamada de Zoom"><br>**Llamadas.** La app de la llamada y cuánto llevas hablando. | <img src="docs/images/collapsed-idle.png" alt="Notch plegado con el uso restante de Claude Code y el tiempo"><br>**De un vistazo.** Elige qué muestra cada lado del notch plegado. |

## Todo lo que hace

**🎵 Música**
- **Reproducción actual de cualquier app.** Música, Spotify, YouTube Music y navegadores como Safari, Chrome, Arc, Dia y Aside. Carátula, controles y una barra de progreso que puedes arrastrar.
- **Letras sincronizadas** de [LRCLIB](https://lrclib.net), bajo el título o bajo el notch mientras trabajas.
- **Vista previa.** Cuando cambia la pista, el título se desliza un momento.
- **Pódcasts y vídeos largos** tienen saltos de 15 segundos y un botón de velocidad (de 1× a 2×), si el reproductor lo admite.

**🗂️ Para ser productivo**
- **Estante.** Arrastra archivos al notch y sácalos después, con vistas previas de imágenes, PDF y vídeos que crecen con la altura del estante. Las capturas de pantalla y las descargas terminadas pueden llegar allí automáticamente. Si agitas el puntero mientras arrastras archivos, en cualquier lugar, aparece un pequeño destino para soltarlos justo al lado.
- **Calendario y recordatorios.** El día de hoy en cifras grandes, tu semana con un punto en los días ocupados, los eventos de hoy y recordatorios que puedes marcar. Funciona con todas las cuentas añadidas a macOS (Google, iCloud, Exchange y más), y tú eliges qué calendarios se muestran.
- **Próximos eventos.** Cinco minutos antes de que empiece un evento con hora, el notch muestra su título y cuánto falta. Los eventos con un enlace de Zoom, Google Meet, Teams, Webex, FaceTime, Whereby o Chime tienen un botón verde Unirse en Inicio, y al hacer clic en el aviso te unes a la reunión.
- **Una búsqueda que puede sustituir a Spotlight.** Apps (incluso las que están fuera de Aplicaciones), archivos, comandos y ajustes del sistema, historial del portapapeles, emojis (empieza con `:`) y cálculos como `12*(3+4)`, ordenados según lo que más abres. Funcionan las iniciales: `vsc` encuentra Visual Studio Code. Las flechas eligen y Retorno abre.
- **Tus atajos.** <kbd>⇧⌘Espacio</kbd> abre Buscar por defecto, o graba cualquier combinación para ello. En Ajustes › General › Atajos hay además acciones que empiezan vacías: ir al agente que lleva más tiempo esperando (su terminal pasa al frente), abrir la pestaña Agentes, ir al origen del último aviso y abrir o cerrar el notch. Una combinación que ya usa otra acción no se guarda, y Nunsseop te avisa si macOS u otra app ya la usa.
- **Temporizador, historial del portapapeles, notas y un selector de emojis.** El historial del portapapeles se queda en memoria y omite todo lo que un gestor de contraseñas marque como secreto. Los parámetros de seguimiento como `utm_` y `fbclid` se quitan de los enlaces que copias.
- **Un detalle junto a la lista.** Estante, Portapapeles, Apps, Buscar y Notificaciones muestran a la derecha, con sus acciones, el elemento bajo el puntero (o el elegido con ↑ ↓). Un clic en una fila sigue copiando, abriendo o yendo al origen al instante.

**💻 Tu Mac**
- **HUDs del sistema.** Volumen, brillo (incluidas las pantallas externas DDC), retroiluminación del teclado, carga, Bloq Mayús y batería de los AirPods aparecen en el notch. Puede quedarse con las teclas de volumen y brillo para que no salga el HUD del sistema.
- **Estadísticas del sistema y baterías.** CPU, memoria, disco, red y la batería de este Mac en paneles, además del ratón, el teclado y el trackpad, con un aviso cuando alguno tiene la batería baja.
- **Indicador de cámara y micrófono.** Un punto en el notch mientras cualquier app los usa.
- **Herramientas.** Cambia la salida de audio, ajusta el volumen de cada app (experimental, macOS 14.2+), silencia el micrófono, mantén el Mac activo, graba la pantalla, expulsa discos, toma un color de cualquier punto de la pantalla y copia el texto de cualquier zona de la pantalla.
- **El tiempo, las descargas, el espejo y las apps del Dock**, a un gesto del puntero. El tiempo es una fila al pie de Inicio.

**📞 Incluso plegado**
- **Llamadas.** Durante una llamada en Zoom, FaceTime, Teams, Slack, Discord, WhatsApp o Google Meet, el notch plegado muestra la app y cuánto llevas hablando. Se basa en qué app usa el micrófono, así que mostrar la llamada de una app de escritorio no necesita permiso; en un navegador (Meet, o Zoom y Teams en la web) hace falta Automatización para ese navegador. En Zoom, FaceTime y Meet puedes silenciar el micrófono desde el notch (y apagar la cámara en Zoom y Meet), sin cambiar a la llamada; Zoom y FaceTime necesitan Accesibilidad, y Meet necesita *Permitir JavaScript desde Apple Events* en un navegador Chromium.
- **Tú eliges qué se ve en cada lado.** Cuando no suena nada, muestra el uso restante de Claude Code o Codex, los agentes en marcha, la batería, el tiempo o la fecha.
- **Música y temporizadores.** Una pequeña carátula y un visualizador mientras suena música, y el tiempo restante mientras corre un temporizador. Los temporizadores, las llamadas y las descargas ajustan cada lado a su propio contenido, así que un icono solo no deja un hueco.
- **Descargas.** El avance en porcentaje de una descarga de Safari o Chrome, a partir del mismo progreso que el Finder muestra en el archivo. No se consulta continuamente.

**🤖 Para desarrolladores**
- **Uso de IA.** Los límites de Claude y Codex con sus horas de restablecimiento, y el uso de tokens de las últimas 5 horas y los últimos 7 días, sumado entre Claude Code, Codex, gjc, omo y OpenCode. Se lee de archivos que esas herramientas ya guardan en tu Mac, así que no hay que iniciar sesión en nada. Un límite se vuelve naranja con un «!» a partir del 70 %.
- **Límites de Claude desde Claude Code.** En Ajustes › Servicios › Uso de IA, conecta la línea de estado de Claude Code. Claude Code le pasa tus límites de 5 horas y semanales con cada respuesta, así que la pestaña de IA se mantiene al día mientras trabajas, sin que Nunsseop le pida nada a Anthropic. La línea de estado que ya tenías sigue mostrándose como antes, y Desconectar la restablece. Si no se puede restaurar tu comando anterior, Ajustes te lo indica.
- **Límites de Claude en tiempo real (opcional).** Para cuando usas Claude en otro sitio, la pestaña de IA pregunta una vez si quieres obtener de Anthropic tus límites de Claude de 5 horas y semanales, aproximadamente cada hora, con el inicio de sesión que Claude Code guarda en el llavero. Claude Code renueva ese inicio de sesión cuando se ejecuta, así que tras un tiempo sin usarlo la pestaña de IA pide ejecutar Claude Code, no volver a iniciar sesión. Desactivado hasta que digas que sí; puedes cambiarlo después en Ajustes › Servicios. Gana la fuente más reciente, y el plan y las barras por modelo se mantienen cuando esta no los trae.
- **Avisos de límite.** La muesca avisa una vez cuando un límite de 5 horas o semanal de Claude o Codex pasa del 80 % y otra al 95 %, y te dice cuándo se restablece un límite que llegó a eso. Activado por defecto; Ajustes → Avisos → Uso de IA.
- **Notificaciones de agentes y terminales.** Los hooks de Claude Code, Codex, Gemini CLI, GitHub Copilot, Antigravity, Cursor y OpenCode, las extensiones de omp, omo y pi, los plugins de Hermes y Amp, los agentes de Muxy 2, cmux, herdr y Paseo, y las campanas de tmux y WezTerm aparecen en el notch. Haz clic en un aviso para traer al frente su terminal, panel o pestaña ([configuración más abajo](#notificaciones-de-agentes-y-terminales)).
- **Solicitudes de permiso y preguntas.** Permite, deniega o permite siempre lo que Claude Code pide ejecutar o editar, directamente desde el notch; «Permitir siempre» solo aparece cuando Claude Code sugiere una regla de caracteres de teclado simples (ASCII imprimible) que cabe en la tarjeta. La tarjeta muestra la herramienta, la carpeta y cada campo, y un indicador naranja «Caracteres inusuales» avisa cuando el texto tiene caracteres que pueden pasar por letras o símbolos del inglés. Las aprobaciones de Codex para comandos, ediciones de archivos (`apply_patch` lista los archivos) y herramientas MCP funcionan igual, con «Responder en el terminal» en lugar de «Permitir siempre». Las solicitudes de permiso de OpenCode funcionan igual, y también las aprobaciones de herramientas de Paseo, con «Responder en Paseo» en lugar de «Responder en el terminal». Las aprobaciones de GitHub Copilot, Antigravity (comandos y escritura de archivos) y Cursor (comandos de shell y llamadas MCP) funcionan igual, con «Responder en Cursor» en el caso de Cursor. Cuando una solicitud deja alguna duda sobre qué se ejecutaría (un comando de shell de Cursor que corre fuera de su sandbox, por ejemplo), no aparece tarjeta y la herramienta pregunta en su propio aviso. Gemini CLI, Hermes y Amp muestran sesiones y avisos, pero no aprobaciones. También se pueden responder las preguntas de Claude Code: elige una o varias respuestas, pasa por varias preguntas o usa «Responder en el terminal» para devolverla; una pregunta cuyas respuestas no se pueden mostrar fielmente se queda en el terminal. Si respondes antes en el terminal, la tarjeta desaparece. Lo que pide se queda en memoria (desactívalo en Ajustes › Avisos). Si la terminal del agente es la app que tienes al frente, la solicitud se queda en la terminal, donde ya estás mirando (Ajustes › Avisos).
- **Pestaña Notificaciones.** Los últimos 30 avisos de agentes, terminales y tu calendario, con una insignia para los no vistos; haz clic en uno para volver al lugar de donde vino. Desactivada por defecto (Ajustes › Notch) y guardada solo en memoria.
- **Una ceja con ánimo.** La ceja muestra cómo van tus agentes: alzada, con la cola arriba, mientras uno te espera; baja y recta mientras trabajan. Cuando un agente termina su turno, la ceja da dos saltitos y el notch dice cuál terminó (salvo que su terminal ya esté al frente; Ajustes › Avisos). Se cae cuando a un límite de Claude o Codex le queda poco y vuelve a alzarse cuando se restablece. Sin notch, la propia ceja de la app pone la cara; junto a la cámara, el número de agentes lleva una ceja pequeña, y los avisos de agentes y límites la usan como icono. Con «Reducir movimiento» se queda quieta.
- **Agentes en marcha.** Un elemento del notch plegado que muestra cuántos agentes de programación te esperan (una ceja alzada y el número en amarillo) o, si ninguno espera, cuántos están trabajando (una ceja baja y recta y el número en verde). Sigue a Claude Code, Codex, Gemini CLI, OpenCode, GitHub Copilot, Antigravity, Cursor, Hermes, Amp, omp, omo y pi a través de sus hooks, plugins o extensiones (conéctalos en Ajustes › Avisos; Codex te pide confiar en los hooks la próxima vez que se inicie), y a gjc, herdr, Muxy 2 y Paseo sin conectar nada, incluidas las sesiones en segundo plano iniciadas con `claude --bg`. Cuando Claude Code termina un turno y aún corren subagentes o comandos de shell en segundo plano, la sesión sigue contando como activa hasta dos horas, con una etiqueta «Segundo plano · N tareas» en la pestaña Agentes.
- **Pestaña Agentes.** Una línea por cada sesión de un agente de programación en marcha o a la espera de ti: Claude Code, Codex, Gemini CLI, OpenCode, GitHub Copilot, Antigravity, Cursor, Hermes, Amp, omp, omo, pi, gjc, Paseo y lo que corra en herdr o Muxy 2. El estado se distingue por la forma además del color: un punto naranja relleno cuando te espera, un arco verde que gira mientras trabaja y un anillo vacío cuando está inactiva. Luego van el título (el de `/rename` en Claude Code o su propio título; el nombre del hilo en Codex), la carpeta, la herramienta y el modelo, una etiqueta si el modo de permisos no es el predeterminado, un pequeño medidor de contexto con el número de tokens y el tiempo que lleva en ese estado. Cada fila tiene los botones «Ir al terminal» (en las filas de Paseo, «Abrir en Paseo») y «Mensaje»; uno con trazo discontinuo no puede actuar ahora, y su descripción dice por qué. Una sesión que te espera se despliega con «Responder en el terminal». La línea inferior resume los estados («1 esperando · 3 trabajando · 1 en reposo»). Teclado: ↑↓ selecciona, ↵ va al terminal y ⌘M abre el campo de mensaje; un doble clic en una fila también va a su terminal. Las sesiones abiertas que usaste en las últimas 3 horas salen atenuadas como «Inactiva» (el notch plegado no las cuenta). Si no hay ninguna sesión abierta, «Recientes» lista hasta 5 conversaciones de la última semana que no están abiertas: haz clic en una (o pulsa ↵) para reanudarla en el terminal elegido en Ajustes › Avisos (`claude --resume`, `codex resume` o la opción propia de cada herramienta). Lee la carpeta, el modelo, el número de tokens, el modo de permisos, el nombre de la sesión y el último prompt de los archivos de sesión de las propias herramientas en tu Mac. Bajo una sesión en marcha, o que terminó su turno, aparece su último paso: el archivo que leyó o editó, el comando que ejecutó, la pregunta que hizo. Una edición muestra su +N −M y **Ver diff**, que muestra las líneas cambiadas en lugar de la lista (← → para los demás cambios del turno, Esc para volver). Mientras la pestaña muestra una sesión en marcha, su archivo de sesión se mira cada 2 segundos.
- **Escribir a una sesión, soltar archivos en ella.** Pulsa el botón «Mensaje» de una fila (o ⌘M): la línea inferior se convierte en un campo «Para» con el nombre de la sesión, Return envía el texto a su entrada, seguido de Return, y Esc cancela. Si sueltas archivos del Estante o del Finder sobre una fila, sus rutas se escriben sin Return; al arrastrar desde el Estante, mantén el puntero sobre el botón de la pestaña Agentes para pasar a ella. Funciona en sesiones de Ghostty, Terminal, iTerm2, WezTerm, kitty, cmux, herdr, Muxy 2 y Orca (Terminal acepta mensajes pero no archivos), y en Paseo solo mensajes, a los agentes que no están trabajando (tabla más abajo, «Qué funciona dónde»). No se envía nada mientras pueda haber abierta una solicitud de permiso o una pregunta, a sesiones dentro de tmux, zellij o screen, ni cuando Nunsseop no puede confirmar en qué terminal está la sesión.
- **Resumen semanal.** La primera vez que abres el notch cada semana (desde el lunes), aparece una tarjeta «Lo que tu ceja vio la semana pasada» con lo que hicieron tus agentes: su tiempo de trabajo frente a la semana anterior, sesiones por herramienta, líneas cambiadas (+/−) y archivos, tokens por herramienta, el proyecto en el que más trabajaron con su parte del tiempo, la sesión más larga y el día más ocupado, en barras. Se calcula en este Mac a partir de los archivos de sesión de Claude Code, Codex, omo, gjc, omp, pi y OpenCode y no se envía a ningún sitio; las sesiones que un programa inicia con el Agent SDK quedan fuera. **Guardar imagen** escribe en Descargas un PNG de 1080×1920 sin los nombres de los proyectos. Puedes volver a abrirlo cuando quieras desde la pestaña Uso de IA («Semana pasada»). Activado por defecto; se desactiva en Ajustes › Avisos › Uso de IA.

**🧩 Hazlo tuyo**
- Todas las pestañas caben en una sola fila de la cabecera, y la pestaña actual muestra su nombre en una cápsula. En una pantalla con notch, la fila queda a la izquierda de la cámara y se desplaza si no cabe. Inicio, Temporizador, Herramientas, Sistema y Uso de IA son paneles con cifras grandes y barras finas. Ajustes tiene una barra lateral, y la lista de pestañas del panel Notch es una cuadrícula de dos columnas que puedes arrastrar para reordenar.
- Elige tus pestañas, arrástralas para ordenarlas y decide si la cabecera muestra la fecha, qué muestra el notch plegado y qué ventanas emergentes recibes. **Lo que desactivas deja de ejecutarse.**
- En macOS 26, el notch desplegado y sus tarjetas usan Liquid Glass, de modo que lo que hay detrás se transparenta con suavidad. Puedes ajustar lo oscuro que es el cristal, hasta el 100 % para un notch negro sólido, o desactivar el cristal.
- En pantallas sin notch, el notch plegado es una pequeña píldora en la barra de menús, de cristal si quieres, con la ceja, un trazo blanco de pincel, encima. La ceja se levanta cuando el puntero está encima. Tras un tiempo sin uso (de 3 a 60 segundos, o nunca) baja como un ojo que se cierra y se desvanece, y reaparece cuando el puntero llega hasta ella; si lo dejas medio segundo encima, se abre, unido al borde superior. Allí, los HUDs, los avisos, las letras y la vista previa ocupan una sola línea, con el símbolo junto a la barra de nivel, el porcentaje o el texto. Los valores en reposo alargan la píldora solo lo justo para cada uno, junto a la ceja, y la ceja se queda sobre la cámara.
- Elige la pantalla, el tamaño y el retraso al pasar el puntero, abre la app al iniciar sesión y oculta el notch con la tapa cerrada. En automático, el notch plegado sigue al puntero a otra pantalla, o se queda quieto si lo desactivas. Mission Control lo oculta.
- Desliza hacia abajo para abrir, hacia arriba para cerrar, y de lado en Inicio para cambiar de pista.
- Disponible en English, 한국어, 日本語, 简体中文, Español, Deutsch y Français, según el idioma de tu Mac.

## Preguntas frecuentes

<details>
<summary><b>macOS dice que no se puede abrir Nunsseop.</b></summary>

Desde la 0.37.0 la app está firmada y notarizada por Apple y se abre como cualquier otra. Las versiones anteriores no lo estaban: [descarga el DMG más reciente](https://github.com/namekun/Nunsseop/releases/latest/download/Nunsseop.dmg) o actualiza con Homebrew (`brew update && brew upgrade --cask nunsseop`).
</details>

<details>
<summary><b>¿Funciona en un MacBook Pro con Dynamic Island?</b></summary>

Debería, pero aún no hemos podido probarlo en uno. La Dynamic Island la dibuja el sistema, así que la ceja se queda a su lado y no encima, y al pasar el cursor Nunsseop se abre como siempre. Si tienes uno, ejecuta `/Applications/Nunsseop.app/Contents/MacOS/Nunsseop --print-screen-info` y [abre una incidencia](https://github.com/namekun/Nunsseop/issues) con lo que muestre; así podremos ajustarlo bien.
</details>

<details>
<summary><b>No aparece nada cuando reproduzco música.</b></summary>

Nunsseop muestra lo que macOS indique como En reproducción, así que el reproductor tiene que aparecer en el Centro de control. La mayoría de las apps y los navegadores lo hacen. Consulta [cómo funciona En reproducción](#cómo-funciona-en-reproducción) para ver la alternativa.
</details>

<details>
<summary><b>¿Puede Buscar sustituir a Spotlight?</b></summary>

Sí. Abre Ajustes → General, haz clic en el atajo y pulsa <kbd>⌘Espacio</kbd>. Nunsseop te indicará que Spotlight lo usa y abrirá las Funciones rápidas de teclado, donde desmarcas *Mostrar búsqueda de Spotlight*. Buscar también se abre cuando su pestaña está oculta.
</details>

<details>
<summary><b>Hay demasiadas pestañas.</b></summary>

Haz clic derecho en el notch → Ajustes → Notch y desactiva lo que no necesites. Las funciones desactivadas dejan de ejecutarse por completo.
</details>

<details>
<summary><b>Mi Mac no tiene notch.</b></summary>

En una pantalla sin notch, como un monitor externo con la tapa cerrada, el notch plegado es una pequeña píldora que flota en la barra de menús, con la ceja, un trazo blanco de pincel, encima. La ceja se levanta cuando el puntero está encima y, al abrirla, el notch se une al borde superior con su tamaño habitual. Los HUDs, los avisos, las letras y la vista previa se muestran en una sola línea en lugar de alrededor de una cámara. Cuando no se usa, la ceja baja como un ojo que se cierra y la píldora se desvanece; puedes desactivarlo o cambiar el retraso en Ajustes. Con varias pantallas, el notch plegado se mueve a la pantalla donde está el puntero una vez que termina de plegarse, y los HUDs, las aprobaciones y la vista previa también aparecen allí; elige una pantalla en Ajustes para que se quede en su sitio.
</details>

<details>
<summary><b>¿Por qué el uso de IA muestra límites antiguos de Claude?</b></summary>

Por defecto, los porcentajes de Claude de 5 horas y semanales salen de cachés que escriben otras herramientas: el HUD de [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) mientras usas Claude Code en un terminal, o gjc. La tarjeta indica cuándo se actualizaron por última vez. Para tener límites al día, conecta la línea de estado de Claude Code en Ajustes › Servicios › Uso de IA: Claude Code le pasa tus límites con cada respuesta y tu propia línea de estado sigue funcionando. Si usas Claude en otro sitio, activa en su lugar los límites de Claude en tiempo real en la pestaña de IA o en Ajustes › Servicios. Gana la fuente más reciente, y el plan y las barras por modelo se mantienen cuando esta no los trae. Los totales de tokens siempre están al día.
</details>

<details>
<summary><b>Las teclas de volumen dejaron de mostrar el HUD de Nunsseop tras una actualización.</b></summary>

Las versiones anteriores a la 0.8.3 estaban firmadas de una forma que hacía que macOS olvidara el permiso de Accesibilidad en cada actualización. Desde la 0.8.3 se conserva. Si vienes de una versión anterior, quita Nunsseop una vez de Ajustes del Sistema → Privacidad y seguridad → Accesibilidad y vuelve a permitirlo; surte efecto sin reiniciar.
</details>

## Notificaciones de agentes y terminales

Nunsseop escucha en `127.0.0.1:47750` las notificaciones de las herramientas de tu Mac. Las solicitudes deben incluir el token secreto guardado en `~/Library/Application Support/Nunsseop/notify-token`.

Abre Ajustes → Avisos y pulsa **Conectar** junto a Claude Code, Codex, Gemini CLI, GitHub Copilot, Antigravity, Cursor, OpenCode, Hermes, Amp, omp, omo o pi. Solo aparecen las herramientas que has usado en este Mac. Nunsseop modifica el archivo de ajustes de esa herramienta (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.codex/hooks.json`, `~/.gemini/settings.json`) o añade un plugin a `~/.config/opencode/plugins` o una pequeña extensión a `~/.omp/agent/extensions` (`~/.omo` y `~/.pi`, igual), y guarda el archivo anterior con la extensión `.nunsseop-backup`. Antes de escribir nada, una hoja muestra cómo cambiará el archivo (las líneas añadidas en verde, las quitadas en rojo y los tramos sin cambios plegados) y qué copia de seguridad se conserva; **Cancelar** no escribe nada. Donde el archivo se comparte con otras herramientas (Claude Code, Codex, Gemini CLI, Antigravity y Cursor), los hooks que ya tenías se quedan como están y **Desconectar** quita solo los de Nunsseop. Codex solo admite un comando `notify`, así que, si ya había uno, sigue ejecutándose después del de Nunsseop. Los hooks para el recuento de agentes se añaden a `~/.codex/hooks.json` junto a los de otras herramientas, y Codex te pide confiar en ellos la próxima vez que se inicie (con «Review hooks» confías solo en los de Nunsseop; «Trust all and continue» confía en los hooks nuevos de todas las herramientas); hasta entonces no los ejecuta, y vuelve a preguntar tras una actualización que cambie su texto. El hook para responder aprobaciones en el notch se aprueba igual; si ya habías conectado antes, Codex pregunta una vez más, así que revísalo en `/hooks`. **Desconectar** lo deshace. Las sesiones que inicies después envían sus notificaciones al notch. gjc no necesita conectarse: sus sesiones se leen de sus propios archivos mientras se muestra el recuento de agentes o la pestaña Agentes.

GitHub Copilot recibe un archivo de hooks propio, `~/.copilot/hooks/nunsseop.json`; Antigravity (su línea de comandos `agy`) recibe una entrada en `~/.gemini/config/hooks.json`, y Cursor entradas en `~/.cursor/hooks.json`, junto a los hooks de otras herramientas. Hermes y Amp reciben un plugin de Nunsseop (`~/.hermes/plugins/nunsseop`, `~/.config/amp/plugins/nunsseop.ts`). Hermes solo carga un plugin cuando ejecutas una vez `hermes plugins enable nunsseop` en un terminal; Ajustes muestra ese comando y si Hermes lo tiene activado. La API de plugins de Amp es experimental, así que una actualización de Amp puede dejar de funcionar. Una vez conectados, Gemini CLI, GitHub Copilot, Antigravity, Cursor, Hermes y Amp informan de sus sesiones al recuento de agentes y a la pestaña Agentes, y envían un aviso cuando termina un turno. Las aprobaciones de GitHub Copilot, Antigravity y Cursor aparecen en el notch solo con «Responder a solicitudes de permiso y preguntas en el notch» activado en Ajustes › Avisos.

Para configurar Claude Code a mano, pulsa **Copiar el comando del hook de Claude Code** y añádelo a `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      { "hooks": [{ "type": "command", "command": "<paste the copied command here>" }] }
    ]
  }
}
```

Los terminales y las apps de agentes no necesitan ningún hook:

- **Muxy 2:** los agentes que Muxy detecta por sí mismo, que se leen con `muxy activity list` mientras Muxy está en marcha. Aparecen como avisos (no mientras Muxy está al frente), y las sesiones que solo Muxy conoce, en la pestaña Agentes mientras trabajan o esperan. Muxy 1, que usaba un archivo de notificaciones y un socket, no está admitido.
- **cmux:** sus propias notificaciones, que se leen con el comando de cmux incluido en la app y no se muestran mientras está al frente.
- **herdr:** los agentes que terminan o esperan una respuesta, en todas las sesiones, se leen del socket de herdr.
- **Paseo:** los agentes que terminan o fallan, que se leen de los archivos de registro de Paseo, así que aparecen incluso sin su daemon. Las tarjetas de aprobación y sus eventos necesitan el daemon de este Mac, que debe ejecutarse sin contraseña y que Nunsseop nunca inicia.
- **tmux:** campanas de cualquier ventana. Nunsseop añade un hook solo al servidor de tmux en marcha; `tmux.conf` no se modifica.
- **WezTerm:** campanas, mediante las líneas que copias desde Ajustes › Avisos y pegas en `~/.wezterm.lua`.

Cada uno tiene un interruptor en Ajustes › Avisos (WezTerm tiene un botón que copia sus líneas de configuración), que solo aparece si la herramienta está instalada. Las herramientas ya conectadas mediante su propio hook no se muestran dos veces. Orca no tiene una fuente de notificaciones propia: sus sesiones aparecen solo por los hooks y extensiones conectados arriba (Claude Code, Codex, OpenCode, pi y similares), que envían el id de su panel.

Cualquier script también puede enviar una:

```sh
# notify-auth guarda la cabecera Authorization, así el token no aparece en la lista de procesos.
curl -X POST http://127.0.0.1:47750/notify \
  -H @"$HOME/Library/Application Support/Nunsseop/notify-auth" \
  -d '{"title": "Build", "message": "Finished in 42 s"}'
```

### Qué funciona dónde

Los botones «Ir al terminal» y «Mensaje» de una fila y el soltar archivos funcionan donde Nunsseop puede estar seguro de en qué terminal está la sesión: comprueba que el proceso de la sesión corre de verdad ahí. El texto entra por la API de entrada del propio terminal, nunca como pulsaciones simuladas. Donde un mensaje o un archivo soltado no puede funcionar, el botón tiene trazo discontinuo y su descripción dice por qué (tmux, zellij o screen de por medio; una solicitud esperando respuesta; varias pestañas de Ghostty en la misma carpeta; etc.); «Ir al terminal» sigue trayendo la app del terminal al frente.

| Terminal | Ir a su pestaña o panel | Mensaje | Soltar archivos | Reanudar desde «Recientes» |
| --- | :---: | :---: | :---: | :---: |
| Ghostty | ✓¹ | ✓¹ | ✓¹ | ✓ |
| Terminal | ✓ | ✓ | — | ✓ |
| iTerm2 | ✓ | ✓ | ✓ | ✓ |
| WezTerm | ✓ | ✓ | ✓ | ✓ |
| kitty | ✓ | ✓ | ✓ | ✓ |
| cmux | ✓ | ✓ | ✓ | ✓ |
| herdr | ✓ | ✓ | ✓ | — |
| Muxy 2 | ✓ | ✓ | ✓ | ✓ |
| Orca | ✓ | ✓ | ✓ | ✓ |
| Paseo | ✓ | ✓ | — | ✓ |

¹ Solo sesiones de Claude Code.

- **Ghostty, Terminal e iTerm2** se manejan con AppleScript, así que macOS pregunta una vez por cada uno si Nunsseop puede controlarlo (Ajustes del Sistema › Privacidad y seguridad › Automatización). Ghostty no dice a ningún shell qué pestaña es, así que Nunsseop elige la pestaña por la carpeta de la sesión y por el título que Claude Code le pone; por eso ir a ella, escribir y soltar archivos solo funcionan con sesiones de Claude Code, y si no está seguro de cuál es, no envía nada. Terminal solo admite texto que ejecuta, así que acepta mensajes pero rechaza archivos soltados.
- **WezTerm y kitty** se manejan con sus herramientas de línea de comandos (`wezterm cli`, `kitty @`). kitty necesita el control remoto activado, con un socket en el que escuche.
- **Muxy 2:** para ir al panel exacto de una sesión y reanudar conversaciones en una pestaña nueva, carga una vez la pequeña extensión puente de Nunsseop: en Muxy abre Settings › Extensions › Load Unpacked…, elige `~/Library/Application Support/Nunsseop/muxy-bridge` (Ajustes › Avisos › «Mostrar extensión en el Finder» abre esa carpeta) y activa la extensión. Sin ella, un clic solo selecciona el proyecto de la sesión. A las sesiones que solo conoce Muxy (sin hook) se puede ir, pero no escribirles.
- **Orca:** por la línea de comandos `orca`; las conversaciones recientes se reanudan, mientras Orca tiene una ventana, en una pestaña nueva del worktree que las contiene.
- **Paseo:** los mensajes van por `paseo send` y solo a agentes que no están trabajando (también los terminados o a la espera de tu turno; a uno que trabaja lo interrumpiría); un clic abre el agente en Paseo (es lo que significa la primera celda de su fila), y los agentes archivados vuelven desde «Recientes».
- **Reanudar** se hace en el terminal elegido en Ajustes › Avisos, en «Reanudar conversaciones en»; Terminal hace de respaldo. Ghostty, iTerm2 y cmux se ofrecen si están instalados y se inician si no están en marcha; WezTerm, si existe su herramienta de línea de comandos; kitty, solo mientras exista un socket que haya informado una de sus sesiones; Orca, solo mientras esté en marcha con una ventana y solo para carpetas que Orca conoce como worktree (si no, lo toma el siguiente terminal); Muxy, solo mientras su puente esté en marcha. Ghostty y iTerm2 abren una pestaña nueva con Automatización (Ghostty, una ventana nueva si no hay permiso); cmux abre un workspace nuevo, no una pestaña. Las entradas de Paseo en «Recientes» ignoran el ajuste y se abren en Paseo.

## Permisos

Nunsseop pide la mayoría de los permisos solo la primera vez que usas la función que los necesita. La excepción son la carpeta donde vigila las capturas (por defecto el Escritorio, o la que fijes para ellas) y Descargas: macOS puede preguntar por ellas la primera vez que Nunsseop se inicia.

| Función | Permiso | Cuándo se pide |
| --- | --- | --- |
| Calendario | Calendarios | Al pulsar *Permitir acceso* en la pestaña Inicio |
| Recordatorios | Recordatorios | Al pulsar *Permitir recordatorios* en la pestaña Inicio |
| Espejo | Cámara | Al pulsar *Permitir cámara* en la pestaña Espejo |
| Grabación de pantalla y copia de texto de las ventanas de otras apps | Grabación de pantalla | La primera vez que inicias una grabación o capturas texto |
| Grabación con sonido | Micrófono | La primera vez que grabas con el audio del micrófono activado |
| Quedarse con las teclas de volumen, brillo y retroiluminación del teclado | Accesibilidad | Al activar la opción en Ajustes |
| Reproducción actual alternativa para Música, Spotify y navegadores | Automatización | Solo si el helper de MediaRemote no está disponible |
| Mostrar llamadas de Google Meet, Zoom y Teams en un navegador, y los botones de silencio y cámara de Meet | Automatización (ese navegador) | La primera vez que un navegador usa el micrófono |
| Añadir capturas nuevas al Estante, avisos de descargas | Carpetas Escritorio y Descargas | La primera vez que se inicia Nunsseop, macOS puede preguntar (vigila la carpeta de capturas, por defecto el Escritorio, y la de Descargas) |
| Volumen por app | Grabación del audio del sistema | La primera vez que bajas el volumen de una app en la pestaña Herramientas |
| Botón de silencio en llamadas de Zoom y FaceTime, botón de cámara en Zoom | Accesibilidad | Nunca la pide por sí solo: los botones aparecen cuando Nunsseop tiene permiso de Accesibilidad (por ejemplo, con la opción de las teclas de volumen de arriba) |
| Escribir mensajes en sesiones de agentes, ir a la pestaña de una sesión, reanudar conversaciones en una pestaña nueva (solo iTerm2 y Ghostty) | Automatización (Terminal, iTerm2, Ghostty) | La primera vez que lo haces en esa app; en Ghostty, también cuando la pestaña Agentes lista por primera vez una sesión que corre en él |
| Abrir al iniciar sesión | Ítems de inicio | Al activarlo en Ajustes |

## Privacidad

Nunsseop no recopila ni envía datos personales. Solo se conecta a internet para:

- consultar `api.github.com` en busca de una versión nueva una vez al día (se puede desactivar) y, cuando instalas una actualización en una copia del DMG, descargar de GitHub el `appcast.xml` y el DMG de la última versión;
- buscar letras sincronizadas en `lrclib.net` (se puede desactivar);
- obtener el tiempo de `open-meteo.com` para la ciudad que indiques (desactivado hasta que indiques una), y pedir al geocodificador de Apple la ubicación de la ciudad cuando Open-Meteo no la encuentra;
- descargar carátulas por HTTPS desde servicios de música conocidos, solo cuando el helper de MediaRemote no está disponible;
- pedir a `api.anthropic.com` tus límites de Claude aproximadamente cada hora, con el inicio de sesión de Claude Code guardado en el llavero, solo si activas los límites de Claude en tiempo real.

Todo lo demás se queda en tu Mac. El servidor de notificaciones solo acepta conexiones de este Mac. El uso de IA se lee de archivos locales, incluidos los límites que la línea de estado de Claude Code guarda en este Mac, salvo que actives los límites de Claude en tiempo real. Los avisos de la pestaña Notificaciones se guardan solo en memoria. Las grabaciones se guardan junto a tus capturas de pantalla. La vista previa de la cámara solo funciona mientras la pestaña Espejo está abierta y nunca se graba. El historial del portapapeles se borra al salir de Nunsseop.

## Cómo funciona «En reproducción»

Desde macOS 15.4, el framework privado MediaRemote solo responde a procesos firmados por Apple. Nunsseop incluye una pequeña biblioteca auxiliar (`Sources/NowPlayingHelper`) que se ejecuta dentro del `/usr/bin/perl` del sistema, lee el estado de En reproducción, envía los comandos de reproducir, pausar, saltar de pista y desplazarse por la pista, y devuelve líneas JSON a la app.

Esto depende de una API privada, así que una futura actualización de macOS podría dejar de funcionar. Si ocurre, Nunsseop recurre a AppleScript para Música y Spotify y a leer las pestañas multimedia en los navegadores. Esa alternativa necesita tener activado *Permitir JavaScript desde Apple Events* en cada navegador. Dia no tiene un elemento de menú para ello, así que Nunsseop ofrece reabrirlo con `--enable-applescript-javascript`.

## Compilar desde el código fuente

```sh
git clone https://github.com/namekun/Nunsseop.git
cd Nunsseop
./scripts/bundle.sh release      # build/Nunsseop.app
./scripts/make-dmg.sh            # build/Nunsseop-<version>.dmg
```

Necesitas las herramientas de línea de comandos de Xcode con Swift 5.10 o posterior. `scripts/bundle.sh` compila el paquete de Swift y lo envuelve en un bundle de app con firma ad hoc.

## Licencia

[MIT](LICENSE). Los issues y los pull requests son bienvenidos.
