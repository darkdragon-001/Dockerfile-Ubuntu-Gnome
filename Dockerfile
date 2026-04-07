FROM ubuntu:24.04 AS base

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
  /lib/systemd/system/sssd* \
  /lib/systemd/system/systemd-oomd.* \
  /lib/systemd/system/systemd-resolved.service \
  /lib/systemd/system/systemd-update-utmp* \
  /lib/systemd/system/tpm-udev.* \
  /lib/systemd/system/upower.service

# Install TigerVNC server
# TODO set VNC port via environment variables
RUN apt-get update \
  && apt-get install -y tigervnc-standalone-server \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
EXPOSE 5901
ARG DISPLAY=:1
ARG USER=ubuntu
RUN echo "${DISPLAY}=${USER}" >> /etc/tigervnc/vncserver.users
RUN systemctl enable tigervncserver@${DISPLAY}.service

# Install noVNC
RUN apt-get update && apt-get install -y \
  novnc \
  && apt-get clean -y \
  && rm -rf /var/lib/apt/lists/*
RUN ln -s /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html
# TODO specify options like ports as environment variables -> source variables in service via EnvironmentFile=/path/to/env
COPY novnc.service /etc/systemd/system/novnc.service
RUN systemctl enable novnc
EXPOSE 6901

# Set up unprivileged user
RUN apt-get update && apt-get install -y sudo && apt-get clean && rm -rf /var/lib/apt/lists/* && \
  echo "${USER} ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/${USER}" && \
  chmod 440 "/etc/sudoers.d/${USER}"
USER "${USER}"

# Set up VNC
# - 'session=ubuntu-xorg' tells it to look for /usr/share/xsessions/ubuntu-xorg.desktop
# - 'localhost=no' allows external connections
# TODO how to set "-fg" (vncconfig "-nowin") to avoid showing the config window on startup?
RUN mkdir -p /home/${USER}/.vnc
RUN echo "session=ubuntu-xorg\ngeometry=1280x800\nlocalhost=no\nalwaysshared" > /home/${USER}/.vnc/config
RUN echo "acoman" | vncpasswd -f >> /home/${USER}/.vnc/passwd && chmod 600 /home/${USER}/.vnc/passwd

# switch back to root to start systemd
USER root

# Install user applications
FROM base AS user
# TODO split and run build with --squash (wait for hub.docker.com support: https://github.com/docker/hub-feedback/issues/955)

### Install software
# Packages: avidemux chromium firefox
RUN add-apt-repository -y ppa:xtradeb/apps
# NOTE chromium-browser in Ubuntu package sources uses snaps since 19.10
# NOTE firefox in Ubuntu package sources uses snaps since 22.04
RUN echo '\
Package: chromium firefox\
Pin: release o=LP-PPA-xtradeb\
Pin-Priority: 1001\
' | sudo tee /etc/apt/preferences.d/avoid-snaps
# Packages: code
RUN wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg \
    && sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
# Packages: makemkv-bin makemkv-oss
RUN apt-add-repository -y ppa:heyarje/makemkv-beta
# Packages: mkvtoolnix mkvtoolnix-gui
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
    chromium firefox \
    imagemagick libimage-exiftool-perl exiv2 jhead \
    avidemux-qt ffmpeg handbrake makemkv-bin makemkv-oss mediainfo mkvtoolnix mkvtoolnix-gui vcdimager vlc \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
# Configure chromium
RUN sed -i '/^Exec/ s/%U/--password-store=basic --no-sandbox %U/' /usr/share/applications/chromium.desktop

# TODO modify settings/customizations

# Set favoriate apps for dock
USER ubuntu
RUN dbus-launch gsettings set org.gnome.shell favorite-apps "['chromium.desktop', 'firefox.desktop', 'terminator.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Settings.desktop']"
USER root
