#!/bin/bash
# Carga ROS 2 Jazzy (y el workspace si ya está compilado) antes de ejecutar el comando pedido.
set -e
source /opt/ros/jazzy/setup.bash
if [ -f "$HOME/ros2_ws/install/setup.bash" ]; then
    source "$HOME/ros2_ws/install/setup.bash"
fi
exec "$@"
