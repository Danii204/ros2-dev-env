#!/bin/bash
# Comprueba la comunicación entre ROS 2 Lyrical (nativo) y ROS 2 Jazzy (contenedor) en los dos sentidos,
# y entre dos contenedores Jazzy.
#
# IMPORTANTE: los nodos demo cambiaron de tipo entre distros. `demo_nodes_cpp` usa std_msgs/String en Jazzy
# y example_interfaces/String en Lyrical. Con tipos distintos el topic NO conecta y ROS no da ningún error,
# así que cada prueba fuerza el mismo tipo en ambos extremos con `ros2 topic pub`.
#
# Uso: ./test-comm.sh          (SHARE_IPC=0 ./test-comm.sh para probar sin /dev/shm compartido)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
# El setup.bash de ROS usa variables sin definir, por eso se desactiva -u al cargarlo.
set +u
# shellcheck disable=SC1091
source /opt/ros/lyrical/setup.bash
set -u

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

jazzy() { "$HERE/run.sh" "$@"; }

# probar <nombre> <comando emisor> <comando receptor> <patrón que cuenta como recibido>
probar() {
    local name="$1" pub="$2" sub="$3" pat="$4" n
    eval "$pub" >"$TMP/pub.log" 2>&1 &
    sleep 4                                   # margen para arrancar el contenedor y descubrirse
    eval "$sub" >"$TMP/sub.log" 2>&1
    wait 2>/dev/null
    n=$(grep -c -E "$pat" "$TMP/sub.log" 2>/dev/null | head -1)
    if [[ "${n:-0}" -gt 0 ]]; then
        printf "  [ OK ] %-58s %s mensajes\n" "$name" "$n"
    else
        printf "  [FAIL] %-58s 0 mensajes\n" "$name"
        FAILS=$((FAILS + 1))
    fi
}

PUB_STD='ros2 topic pub -r 2 /chatter std_msgs/msg/String "{data: hola}"'
PUB_EX='ros2 topic pub -r 2 /chatter example_interfaces/msg/String "{data: hola}"'

echo "ROS_DOMAIN_ID=$ROS_DOMAIN_ID | SHARE_IPC=${SHARE_IPC:-1} | RMW nativo=${RMW_IMPLEMENTATION:-rmw_fastrtps_cpp}"
echo
echo "Lyrical (nativo) -> Jazzy (contenedor)"
probar "pub Lyrical -> listener C++ Jazzy (std_msgs)" \
       "timeout 14 $PUB_STD" "jazzy timeout 8 ros2 run demo_nodes_cpp listener" "I heard"
echo "Jazzy (contenedor) -> Lyrical (nativo)"
probar "pub Jazzy -> listener C++ Lyrical (example_interfaces)" \
       "jazzy timeout 14 $PUB_EX" "timeout 7 ros2 run demo_nodes_cpp listener" "I heard"
probar "talker C++ Jazzy -> topic echo Lyrical (std_msgs)" \
       "jazzy timeout 14 ros2 run demo_nodes_cpp talker" "timeout 6 ros2 topic echo /chatter" "data:"
echo "Jazzy <-> Jazzy (dos contenedores)"
probar "talker C++ Jazzy -> listener C++ Jazzy" \
       "jazzy timeout 14 ros2 run demo_nodes_cpp talker" "jazzy timeout 8 ros2 run demo_nodes_cpp listener" "I heard"

echo
if [[ "$FAILS" -eq 0 ]]; then
    echo "RESULTADO: OK"
else
    echo "RESULTADO: $FAILS prueba(s) fallida(s)"
    exit 1
fi
