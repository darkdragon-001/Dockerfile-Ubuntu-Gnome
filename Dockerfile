FROM ubuntu:20.04 AS base

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
RUN apt-get update && \
  apt-get install -y ubuntu-desktop && \
  apt-get purge -y --autoremove gnome-initial-setup && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/* && \
  sed -i 's/^Prompt=.*$/Prompt=never/' /etc/update-manager/release-upgrades && \
  dbus-launch gsettings set org.gnome.desktop.lockdown disable-lock-screen true && \
  dbus-launch gsettings set org.gnome.desktop.screensaver lock-enabled false && \
  dbus-launch gsettings set org.gnome.desktop.screensaver idle-activation-enabled false && \
  dbus-launch gsettings set org.gnome.desktop.session idle-delay 0 && \
  dbus-launch gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'

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
RUN mkdir -p /home/${USER}/.vnc
COPY xstartup /home/${USER}/.vnc/xstartup
RUN echo "acoman" | vncpasswd -f >> /home/${USER}/.vnc/passwd && chmod 600 /home/${USER}/.vnc/passwd

# switch back to root to start systemd
USER root

# Install user applications
FROM base AS user
# TODO split and run build with --squash (wait for hub.docker.com support: https://github.com/docker/hub-feedback/issues/955)

### Install software
# TODO chromium-browser uses snaps: https://github.com/ConSol/docker-headless-vnc-container/issues/137
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg \
    && sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
RUN apt-add-repository -y ppa:xtradeb/apps          # avidemux
RUN apt-add-repository -y ppa:heyarje/makemkv-beta  # makemkv-bin makemkv-oss
RUN wget -q -O /usr/share/keyrings/gpg-pub-moritzbunkus.gpg https://mkvtoolnix.download/gpg-pub-moritzbunkus.gpg \
    && sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gpg-pub-moritzbunkus.gpg] https://mkvtoolnix.download/ubuntu/ $(. /etc/os-release && echo ${VERSION_CODENAME}) main" > /etc/apt/sources.list.d/mkvtoolnix.list'  # mkvtoolnix mkvtoolnix-gui
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    openssh-server \
    default-jre \
    bzip2 cifs-utils zip unzip rar unrar p7zip-full p7zip-rar genisoimage squashfs-tools xarchiver \
    less nano vim \
    curl filezilla inetutils-ping nmap wget \
    git meld \
    terminator \
    code evince gimp inkscape libreoffice \
    firefox \
    imagemagick libimage-exiftool-perl exiv2 jhead \
    acidrip avidemux-qt ffmpeg handbrake makemkv-bin makemkv-oss mediainfo mkvtoolnix mkvtoolnix-gui vcdimager vlc \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
# TODO modify settings/customizations

# Set favoriate apps for dock
USER default
RUN dbus-launch gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'terminator.desktop', 'org.gnome.Nautilus.desktop', 'gnome-control-center.desktop']"
USER root
