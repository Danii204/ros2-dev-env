*[Read this in English](README.md)*

# ros2-dev-env

Entorno de desarrollo para ROS 2 con **dos distribuciones conviviendo** en la misma máquina:

| | Dónde corre | Distribución | Ubuntu |
|---|---|---|---|
| **Nativo** | Directamente en el host | ROS 2 **Lyrical** (LTS) | 26.04 |
| **Contenedor** | Docker | ROS 2 **Jazzy** (LTS) | 24.04 |

El objetivo es trabajar con Lyrical de forma nativa y tener Jazzy a mano para lo que todavía no está
empaquetado para Lyrical (por ejemplo, **PX4 SITL** y su puente `px4_msgs`). Ambos comparten red, GPU, pantalla y workspace.

## Requisitos

- Ubuntu 26.04 con el driver NVIDIA propietario funcionando (`nvidia-smi`).
- ROS 2 Lyrical instalado (guía oficial en docs.ros.org).
- [Docker Engine](https://docs.docker.com/engine/install/ubuntu/) y el
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  configurado para Docker (`nvidia-ctk runtime configure --runtime=docker`).
- Tu usuario en el grupo `docker`.

Comprobación rápida de la GPU en contenedores:

```bash
docker run --rm --gpus all nvidia/cuda:13.4.1-base-ubuntu24.04 nvidia-smi
```

## Uso

### Opción A: Docker Compose (la más simple, un contenedor persistente)

```bash
docker compose up -d              # construye la imagen (la 1ª vez) y arranca el contenedor
docker compose exec ros2-jazzy bash   # entra; se puede repetir en varias terminales a la vez
docker compose down               # para y elimina el contenedor
```

Variables opcionales (expórtalas antes de `docker compose up` si necesitas cambiarlas):
`USER_UID`/`USER_GID` (por defecto 1000/1000, comprueba con `id -u`), `ROS_WS` (por defecto `~/ros2_ws`),
`ROS_DOMAIN_ID` (por defecto 0), `XAUTHORITY`.

> `docker compose up` (sin `-d`) **no** sirve para una shell interactiva: Compose no conecta el terminal
> al contenedor. Por eso el servicio se queda vivo con `sleep infinity` y se entra con `exec`.

### Opción B: `run.sh` (para más de un contenedor a la vez, como en `test-comm.sh`)

```bash
./run.sh --build          # construye la imagen (la primera vez, unos minutos)
./run.sh                  # shell interactiva dentro del contenedor Jazzy
./run.sh ros2 topic list  # o ejecuta un comando y sale
```

Docker Compose fija el nombre del servicio, así que no vale para lanzar varios contenedores Jazzy en paralelo
(por ejemplo, la prueba Jazzy↔Jazzy de más abajo). Para eso, `run.sh` genera un nombre de contenedor distinto
en cada ejecución (`ros2-jazzy-<pid>`, cambiable con `CONTAINER_NAME`).

En ambas opciones, el workspace del host se monta en `/home/dev/ros2_ws` (variable `ROS_WS`), así que compilas
y editas desde el host y los archivos nunca quedan como `root`: la imagen se construye con tu UID/GID.

### Qué configuran `run.sh` y `docker-compose.yml`

| Opción | Motivo |
|---|---|
| `--network host` / `network_mode: host` | Descubrimiento DDS entre el host y el contenedor sin configurar puertos. |
| `--gpus all` / `deploy.resources.reservations.devices` + `NVIDIA_DRIVER_CAPABILITIES=all` | Cómputo (CUDA) y gráficos (OpenGL/Vulkan) con la GPU NVIDIA. |
| `-v /tmp/.X11-unix` + `XAUTHORITY` | GUI (RViz, Gazebo) sobre **Xwayland**. |
| `ROS_DOMAIN_ID` | Debe coincidir en ambos lados para que se vean. |
| `--ipc host` / `ipc: host` | Comparte `/dev/shm` con el host; necesario si Fast DDS usa memoria compartida entre contenedores (ver Notas). En `run.sh` se puede desactivar con `SHARE_IPC=0`. |

## Comprobar la comunicación Lyrical ↔ Jazzy

```bash
./test-comm.sh    # Lyrical -> Jazzy, Jazzy -> Lyrical y Jazzy <-> Jazzy (dos contenedores); usa run.sh, no Compose
```

Resultado en esta máquina (`rmw_fastrtps_cpp` en ambos lados, `ROS_DOMAIN_ID=0`):

```
Lyrical (nativo) -> Jazzy (contenedor)
  [ OK ] pub Lyrical -> listener C++ Jazzy (std_msgs)               16 mensajes
Jazzy (contenedor) -> Lyrical (nativo)
  [ OK ] pub Jazzy -> listener C++ Lyrical (example_interfaces)     13 mensajes
  [ OK ] talker C++ Jazzy -> topic echo Lyrical (std_msgs)          5 mensajes
Jazzy <-> Jazzy (dos contenedores)
  [ OK ] talker C++ Jazzy -> listener C++ Jazzy                     7 mensajes
```

## Notas

Problemas que aparecieron al montar este entorno y que conviene conocer.

### 1. Los nodos demo cambiaron de tipo de mensaje entre Jazzy y Lyrical

`demo_nodes_cpp talker/listener` publica **`std_msgs/msg/String`** en Jazzy pero **`example_interfaces/msg/String`**
en Lyrical. En ROS 2, dos extremos con el mismo nombre de topic pero distinto tipo **no conectan y no dan ningún error**:
el descubrimiento funciona (`ros2 node list` ve el nodo y `ros2 topic list` el topic) pero no llega ningún dato.

Cómo se ve: `ros2 topic info /chatter -v` muestra `Topic type` distinto en el publicador y en el suscriptor.
Por eso la prueba ingenua «talker de una distro con listener de la otra» da 0 mensajes aunque la red esté bien.
`ros2 topic echo` sí recibía, porque se adapta al tipo del publicador. `test-comm.sh` fuerza el mismo tipo en ambos extremos.

### 2. Dos contenedores en la misma máquina no se pasan datos si no comparten `/dev/shm`

Con el Fast DDS por defecto, los participantes de la misma máquina intentan usar memoria compartida. Si están en
contenedores distintos, cada uno tiene su propio `/dev/shm`: **se descubren, pero no llegan datos**. Se soluciona con
`--ipc host` (lo hacen `run.sh` y `docker-compose.yml` por defecto) o desactivando la memoria compartida con
`FASTDDS_BUILTIN_TRANSPORTS=UDPv4` (más lento con mensajes grandes como imágenes o nubes de puntos).
Entre el host y un contenedor no hizo falta ninguna de las dos.

### 3. Nombre de contenedor fijo

Un `--name`/`container_name` fijo impide abrir una segunda shell en paralelo (el segundo `docker run` falla por
conflicto de nombre y las pruebas daban 0 mensajes sin explicación). Por eso `run.sh` genera un nombre distinto en
cada ejecución, y por eso Docker Compose (que sí usa un nombre fijo) es solo para un contenedor persistente al que
se entra con `exec`, no para lanzar varios a la vez.

### 4. GUI en GNOME/Wayland: el hostname del contenedor no hace falta que coincida

Al montar `docker-compose.yml` asumí (y así quedó primero en `run.sh`) que la cookie de Xwayland exigía que el
`hostname` del contenedor coincidiera con el del host. Al probarlo con Compose —que por defecto pone su propio
hostname, sin forzar coincidencia— la GUI funcionó igual (`glxinfo -B` → `OpenGL renderer: NVIDIA GeForce RTX 4070
SUPER`, `direct rendering: Yes`). Conclusión: lo que hace falta es compartir `/tmp/.X11-unix` y `XAUTHORITY`; el
hostname no importa en esta configuración. Es un buen ejemplo de comprobar en vez de dar una explicación por buena.
