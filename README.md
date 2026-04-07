## Ubuntu Desktop (GNOME 3) Dockerfile

<<<<<<< HEAD
=======
_The user branch adds some applications._
>>>>>>> refs/rewritten/user

This repository contains the *Dockerfile* and *associated files* for setting up a container with Ubuntu, GNOME 3, TigerVNC and noVNC.

* The VNC Server currently defaults to 1366*768 24bit.

### Dependencies

* [ubuntu:20.04](https://hub.docker.com/_/ubuntu)


### Usage

#### Container actions

* Start container:

      sudo docker run --name=ubuntu-gnome -d --rm \
        --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
        --cgroupns=host --cap-add SYS_BOOT --cap-add SYS_ADMIN \
        -v /sys/fs/cgroup:/sys/fs/cgroup \
        -p 5901:5901 -p 6901:6901 \
        darkdragon001/ubuntu-gnome-vnc

* Open (root) shell:

      sudo docker exec -it ubuntu-gnome bash

* Open shell as user:

      sudo docker exec -it -u default ubuntu-gnome bash

* Stop container:

      sudo docker stop ubuntu-gnome

#### Connecting to instance

* Connect to `vnc://<host>:5901` via your VNC client.
* Connect to `http://<host>:6901` via your web browser.

_**NOTE** The password is hardcoded to `acoman`._

#### Using the desktop

* Gain root access via `sudo`


### Known issues

* Sidebar/dock hidden by default
* User switching / gdm3 not working

### Not tested

* Sound (PulseAudio)
