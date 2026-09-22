#!/bin/bash
# Arranca el contenedor ROS 2 Jazzy con red del host, GPU NVIDIA y GUI compartida (X11 / Xwayland).
#
# Uso:
#   ./run.sh                    # shell interactiva
#   ./run.sh <comando...>       # ejecuta un comando y sale (p. ej. ./run.sh ros2 topic list)
#   ./run.sh --build            # (re)construye la imagen y sale
#
# Variables opcionales:
#   ROS_WS=~/ros2_ws            # workspace del host que se monta en /home/dev/ros2_ws
#   ROS_DOMAIN_ID=0             # debe coincidir con el del ROS 2 nativo
#   SHARE_IPC=1                 # (por defecto) comparte el /dev/shm del host; SHARE_IPC=0 lo desactiva
#   CONTAINER_NAME=mi-nombre    # por defecto ros2-jazzy-<pid>, así se pueden abrir varias shells a la vez
set -euo pipefail

IMAGE="ros2-jazzy-dev"
# Nombre único por ejecución para poder abrir varias terminales/contenedores a la vez.
NAME="${CONTAINER_NAME:-ros2-jazzy-$$}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROS_WS="${ROS_WS:-$HOME/ros2_ws}"

build() {
    docker build \
        --build-arg USER_UID="$(id -u)" \
        --build-arg USER_GID="$(id -g)" \
        -t "$IMAGE" "$HERE"
}

if [[ "${1:-}" == "--build" ]]; then
    build
    exit 0
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo ">> La imagen $IMAGE no existe: construyéndola..."
    build
fi

mkdir -p "$ROS_WS/src"

ARGS=(
    --rm
    --name "$NAME"
    --network host
    --gpus all
    # La cookie de Xwayland está ligada al hostname: hay que conservar el del host.
    --hostname "$(hostname)"
    -e DISPLAY="${DISPLAY:-:0}"
    -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw
    -v "$ROS_WS":/home/dev/ros2_ws
)

# Autorización de X11: en GNOME/Wayland la cookie de Xwayland está en $XAUTHORITY (cambia en cada sesión).
if [[ -n "${XAUTHORITY:-}" && -f "$XAUTHORITY" ]]; then
    ARGS+=(-e XAUTHORITY="$XAUTHORITY" -v "$XAUTHORITY":"$XAUTHORITY":ro)
fi

# Fallback de Mesa (sin GPU NVIDIA) si existe /dev/dri.
[[ -d /dev/dri ]] && ARGS+=(--device /dev/dri)

# Por defecto se comparte el IPC (y /dev/shm) con el host: sin esto, dos contenedores en la misma máquina
# se descubren pero Fast DDS no logra pasarse datos por memoria compartida (ver README, sección Notas).
[[ "${SHARE_IPC:-1}" == "1" ]] && ARGS+=(--ipc host)

# Variables de ROS/DDS del host que se propagan al contenedor solo si están definidas.
for var in RMW_IMPLEMENTATION FASTDDS_BUILTIN_TRANSPORTS ROS_LOCALHOST_ONLY ROS_AUTOMATIC_DISCOVERY_RANGE; do
    [[ -n "${!var:-}" ]] && ARGS+=(-e "$var=${!var}")
done

# TTY interactiva solo si hay terminal.
if [[ -t 0 && -t 1 ]]; then ARGS+=(-it); fi

exec docker run "${ARGS[@]}" "$IMAGE" "${@:-bash}"
