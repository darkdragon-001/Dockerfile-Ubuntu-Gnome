FROM darkdragon001/ubuntu-gnome-vnc:latest
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
