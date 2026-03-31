FROM ubuntu:20.04

ENV container=docker
ENV DEBIAN_FRONTEND=noninteractive

# Install locale
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
  locales && \
  echo "$LANG UTF-8" >> /etc/locale.gen && \
  locale-gen && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Unminimize to include man pages
RUN yes | unminimize

# Install systemd
RUN apt-get update && apt-get install -y \
  dbus dbus-x11 systemd && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  dpkg-divert --local --rename --add /sbin/udevadm && \
  ln -s /bin/true /sbin/udevadm
VOLUME ["/sys/fs/cgroup"]
STOPSIGNAL SIGRTMIN+3
CMD [ "/sbin/init" ]

# Install GNOME
# NOTE if you want plain gnome, use: "apt-get install -y --no-install-recommends gnome-session gnome-terminal"
# NOTE initial setup uninstalled as disabling via /etc/gdm3/custom.conf stopped working: https://askubuntu.com/q/1028822/206608
RUN apt-get update \
  && apt-get install -y ubuntu-desktop fcitx-config-gtk gnome-tweak-tool gnome-usage \
  && apt-get purge -y --autoremove gnome-initial-setup \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Remove unnecessary system targets
# TODO remove more targets but make sure that startup completes and login promt is displayed when "docker run -it"
#   https://github.com/moby/moby/issues/42275#issue-853601974
RUN rm -f \
  /lib/systemd/system/local-fs.target.wants/* \
  /lib/systemd/system/sockets.target.wants/*udev* \
  /lib/systemd/system/sockets.target.wants/*initctl* \
  /lib/systemd/system/sysinit.target.wants/systemd-tmpfiles-setup* \
  /lib/systemd/system/systemd-update-utmp* \
  /lib/systemd/system/systemd-resolved.service

# Install TigerVNC server
# TODO set VNC port in service file > exec command
# TODO check if it works with default config file
# NOTE tigervnc because of XKB extension: https://github.com/i3/i3/issues/1983
RUN apt-get update \
  && apt-get install -y tigervnc-common tigervnc-scraping-server tigervnc-standalone-server tigervnc-viewer tigervnc-xorg-extension \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
# TODO fix PID problem: Type=forking would be best, but system daemon is run as root on startup
#   ERROR tigervnc@:1.service: New main PID 233 does not belong to service, and PID file is not owned by root. Refusing.
#   https://www.freedesktop.org/software/systemd/man/systemd.service.html#Type=
#   https://www.freedesktop.org/software/systemd/man/systemd.unit.html#Specifiers
#   https://wiki.archlinux.org/index.php/TigerVNC#Starting_and_stopping_vncserver_via_systemd
# -> this should be fixed by official systemd file once released: https://github.com/TigerVNC/tigervnc/pull/838
# TODO specify options like geometry as environment variables -> source variables in service via EnvironmentFile=/path/to/env
# NOTE logout will stop tigervnc service -> need to manually start (gdm for graphical login is not working)
COPY tigervnc@.service /etc/systemd/system/tigervnc@.service
RUN systemctl enable tigervnc@:1
EXPOSE 5901

# Install noVNC
# TODO novnc depends on net-tools until version 1.1.0: https://github.com/novnc/noVNC/issues/1075
RUN apt-get update && apt-get install -y \
  net-tools novnc \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html
# TODO specify options like ports as environment variables -> source variables in service via EnvironmentFile=/path/to/env
COPY novnc.service /etc/systemd/system/novnc.service
RUN systemctl enable novnc
EXPOSE 6901

# Create unprivileged user
# NOTE user hardcoded in tigervnc.service
# NOTE alternative is to use libnss_switch and create user at runtime -> use entrypoint script
ARG UID=1000
ARG USER=default
RUN useradd ${USER} -u ${UID} -U -d /home/${USER} -m -s /bin/bash
RUN apt-get update && apt-get install -y sudo && apt-get clean && rm -rf /var/lib/apt/lists/* && \
  echo "${USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USER}" && \
  chmod 440 "/etc/sudoers.d/${USER}"
USER "${USER}"

# Set up VNC
ARG HOME=/home/${USER}
RUN mkdir -p ${HOME}/.vnc
COPY xstartup ${HOME}/.vnc/xstartup
RUN echo "acoman" | vncpasswd -f >> ${HOME}/.vnc/passwd && chmod 600 ${HOME}/.vnc/passwd

# switch back to root to start systemd
USER root

