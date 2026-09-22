*[Leer esto en español](README.es.md)*

# ros2-dev-env

Development environment for ROS 2 with **two distributions living side by side** on the same machine:

| | Runs on | Distribution | Ubuntu |
|---|---|---|---|
| **Native** | Directly on the host | ROS 2 **Lyrical** (LTS) | 26.04 |
| **Container** | Docker | ROS 2 **Jazzy** (LTS) | 24.04 |

The goal is to work with Lyrical natively and have Jazzy available for whatever isn't packaged for Lyrical yet
(for example **PX4 SITL** and its `px4_msgs` bridge). Both share the network, GPU, display and workspace.

## Requirements

- Ubuntu 26.04 with the proprietary NVIDIA driver working (`nvidia-smi`).
- ROS 2 Lyrical installed (official guide on docs.ros.org).
- [Docker Engine](https://docs.docker.com/engine/install/ubuntu/) and the
  [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
  configured for Docker (`nvidia-ctk runtime configure --runtime=docker`).
- Your user in the `docker` group.

Quick GPU check inside a container:

```bash
docker run --rm --gpus all nvidia/cuda:13.4.1-base-ubuntu24.04 nvidia-smi
```

## Usage

### Option A: Docker Compose (simplest, one persistent container)

```bash
docker compose up -d                  # builds the image (first time) and starts the container
docker compose exec ros2-jazzy bash   # enter it; can be repeated from several terminals at once
docker compose down                   # stop and remove the container
```

Optional variables (export them before `docker compose up` if you need to change them):
`USER_UID`/`USER_GID` (default 1000/1000, check with `id -u`), `ROS_WS` (default `~/ros2_ws`),
`ROS_DOMAIN_ID` (default 0), `XAUTHORITY`.

> `docker compose up` (without `-d`) is **not** an interactive shell: Compose doesn't attach your
> terminal to the container. That's why the service stays alive with `sleep infinity` and you enter with `exec`.

### Option B: `run.sh` (for more than one container at once, as in `test-comm.sh`)

```bash
./run.sh --build          # build the image (first time, a few minutes)
./run.sh                  # interactive shell inside the Jazzy container
./run.sh ros2 topic list  # or run a single command and exit
```

Docker Compose pins the service's container name, so it can't launch several Jazzy containers in parallel
(for example, the Jazzy↔Jazzy test below). `run.sh` generates a fresh container name on every run instead
(`ros2-jazzy-<pid>`, override with `CONTAINER_NAME`).

With either option, the host workspace is mounted at `/home/dev/ros2_ws` (`ROS_WS` variable), so you build and
edit from the host and files never end up owned by `root`: the image is built with your UID/GID.

### What `run.sh` and `docker-compose.yml` set up

| Option | Why |
|---|---|
| `--network host` / `network_mode: host` | DDS discovery between host and container with no port setup. |
| `--gpus all` / `deploy.resources.reservations.devices` + `NVIDIA_DRIVER_CAPABILITIES=all` | Compute (CUDA) and graphics (OpenGL/Vulkan) on the NVIDIA GPU. |
| `-v /tmp/.X11-unix` + `XAUTHORITY` | GUI apps (RViz, Gazebo) over **Xwayland**. |
| `ROS_DOMAIN_ID` | Must match on both sides so they can see each other. |
| `--ipc host` / `ipc: host` | Shares `/dev/shm` with the host; needed if Fast DDS uses shared memory between containers (see Notes). `run.sh` can disable it with `SHARE_IPC=0`. |

## Verifying Lyrical ↔ Jazzy communication

```bash
./test-comm.sh    # Lyrical -> Jazzy, Jazzy -> Lyrical, and Jazzy <-> Jazzy (two containers); uses run.sh, not Compose
```

Result on this machine (`rmw_fastrtps_cpp` on both sides, `ROS_DOMAIN_ID=0`):

```
Lyrical (native) -> Jazzy (container)
  [ OK ] pub Lyrical -> C++ listener Jazzy (std_msgs)                16 messages
Jazzy (container) -> Lyrical (native)
  [ OK ] pub Jazzy -> C++ listener Lyrical (example_interfaces)      13 messages
  [ OK ] C++ talker Jazzy -> topic echo Lyrical (std_msgs)           5 messages
Jazzy <-> Jazzy (two containers)
  [ OK ] C++ talker Jazzy -> C++ listener Jazzy                      7 messages
```

## Notes

Issues that came up while building this environment, worth knowing about.

### 1. The demo nodes changed message type between Jazzy and Lyrical

`demo_nodes_cpp talker/listener` publishes **`std_msgs/msg/String`** on Jazzy but **`example_interfaces/msg/String`**
on Lyrical. In ROS 2, two endpoints with the same topic name but a different type **don't connect and raise no
error**: discovery works fine (`ros2 node list` sees the node, `ros2 topic list` sees the topic) but no data arrives.

How to spot it: `ros2 topic info /chatter -v` shows a different `Topic type` on the publisher and the subscriber.
That's why the naive "talker from one distro, listener from the other" test gave 0 messages even though the
network was fine. `ros2 topic echo` did receive data, because it adapts to the publisher's type. `test-comm.sh`
forces the same type on both ends.

### 2. Two containers on the same machine don't exchange data unless they share `/dev/shm`

With the default Fast DDS, participants on the same machine try to use shared memory. If they're in different
containers, each has its own `/dev/shm`: **they discover each other, but no data gets through**. Fixed with
`--ipc host` (what `run.sh` and `docker-compose.yml` do by default) or by disabling shared memory with
`FASTDDS_BUILTIN_TRANSPORTS=UDPv4` (slower for large messages like images or point clouds). Between the host and
a container, neither was needed.

### 3. Fixed container name

A fixed `--name`/`container_name` blocks a second shell from running in parallel (the second `docker run` fails
on a name conflict, and tests silently gave 0 messages with no clue why). That's why `run.sh` generates a
different name on every run, and why Docker Compose (which does use a fixed name) is only meant for one
persistent container you `exec` into, not for running several at once.

### 4. GUI on GNOME/Wayland: the container's hostname doesn't need to match

While setting up `docker-compose.yml` I assumed (and `run.sh` originally reflected this) that the Xwayland
auth cookie required the container's `hostname` to match the host's. Testing it with Compose — which sets its
own hostname by default, with no matching — the GUI worked exactly the same (`glxinfo -B` →
`OpenGL renderer: NVIDIA GeForce RTX 4070 SUPER`, `direct rendering: Yes`). Conclusion: what actually matters is
sharing `/tmp/.X11-unix` and `XAUTHORITY`; the hostname doesn't matter in this setup. A good example of verifying
instead of taking an earlier explanation at face value.
