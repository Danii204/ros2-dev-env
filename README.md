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

```bash
./run.sh --build          # construye la imagen (la primera vez, unos minutos)
./run.sh                  # shell interactiva dentro del contenedor Jazzy
./run.sh ros2 topic list  # o ejecuta un comando y sale
```

`run.sh` monta `~/ros2_ws` del host en `/home/dev/ros2_ws` (cámbialo con `ROS_WS=/otra/ruta ./run.sh`),
así que compilas y editas desde el host y los archivos nunca quedan como `root`: la imagen se construye con tu UID/GID.

### Qué hace `run.sh`

| Opción | Motivo |
|---|---|
| `--network host` | Descubrimiento DDS entre el host y el contenedor sin configurar puertos. |
| `--gpus all` + `NVIDIA_DRIVER_CAPABILITIES=all` | Cómputo (CUDA) y gráficos (OpenGL/Vulkan) con la GPU NVIDIA. |
| `-v /tmp/.X11-unix` + `XAUTHORITY` + `--hostname` | GUI (RViz, Gazebo) sobre **Xwayland**. En GNOME/Wayland la cookie de autorización está ligada al hostname, por eso se conserva el del host. |
| `ROS_DOMAIN_ID` | Debe coincidir en ambos lados para que se vean. |
| `SHARE_IPC=1` (opcional) | Comparte `/dev/shm` con el host, necesario si Fast DDS usa memoria compartida. |

## Comprobar la comunicación Lyrical ↔ Jazzy

```bash
./test-comm.sh    # Lyrical -> Jazzy, Jazzy -> Lyrical y Jazzy <-> Jazzy (dos contenedores)
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

Tres problemas que aparecieron al montar este entorno y que conviene conocer.

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
`--ipc host` (lo que hace `run.sh` por defecto, `SHARE_IPC=1`) o desactivando la memoria compartida con
`FASTDDS_BUILTIN_TRANSPORTS=UDPv4` (más lento con mensajes grandes como imágenes o nubes de puntos).
Entre el host y un contenedor no hizo falta ninguna de las dos.

### 3. Nombre de contenedor fijo

Un `--name` fijo impide abrir una segunda shell en paralelo (el segundo `docker run` falla por conflicto de nombre y
las pruebas daban 0 mensajes sin explicación). `run.sh` usa `ros2-jazzy-<pid>` por defecto; se cambia con `CONTAINER_NAME`.

### GUI en GNOME/Wayland

RViz y Gazebo se conectan por **Xwayland** (`DISPLAY` + `XAUTHORITY` + `--hostname` igual al del host).
Comprobado dentro del contenedor: `glxinfo -B` → `OpenGL renderer: NVIDIA GeForce RTX 4070 SUPER`, `direct rendering: Yes`.
