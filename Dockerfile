# Entorno de desarrollo ROS 2 Jazzy (Ubuntu 24.04) para convivir con ROS 2 Lyrical nativo (Ubuntu 26.04).
# Sirve para lo que aún no esté empaquetado para Lyrical (p. ej. PX4 SITL).
FROM osrf/ros:jazzy-desktop-full

ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

# Herramientas de desarrollo y de diagnóstico de GUI/GPU (glxinfo, xdpyinfo, vulkaninfo).
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash-completion \
        git \
        gdb \
        mesa-utils \
        vulkan-tools \
        x11-utils \
        python3-pip \
        python3-venv \
        ros-dev-tools \
        sudo \
        nano \
    && rm -rf /var/lib/apt/lists/*

# La imagen base de Ubuntu 24.04 trae el usuario "ubuntu" con UID 1000: se elimina para que
# el usuario del contenedor tenga el mismo UID/GID que el del host y los ficheros del volumen no queden de root.
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi \
    && (getent group ${USER_GID} >/dev/null || groupadd --gid ${USER_GID} ${USERNAME}) \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME} \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Acceso a la GPU con el NVIDIA Container Toolkit (incluye OpenGL/Vulkan para Gazebo y RViz).
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all \
    QT_X11_NO_MITSHM=1

USER ${USERNAME}
WORKDIR /home/${USERNAME}/ros2_ws

RUN echo 'source /opt/ros/jazzy/setup.bash' >> ~/.bashrc \
    && echo '[ -f ~/ros2_ws/install/setup.bash ] && source ~/ros2_ws/install/setup.bash' >> ~/.bashrc \
    && echo 'source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash' >> ~/.bashrc

COPY --chown=${USERNAME}:${USERNAME} entrypoint.sh /home/${USERNAME}/entrypoint.sh
ENTRYPOINT ["/home/dev/entrypoint.sh"]
CMD ["bash"]
