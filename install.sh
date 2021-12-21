#!/bin/bash

###
# this script automates a Fedora 35 setup.
# - FIRST STEP: setup dnf, disable wayland and remove old kernels (setup_dnf, disable_wayland, rm_old_kernels)
# - SECOND STEP: sets default configs (install_nvidia_drivers, setup_grub, setup_git, setup_ps1)
# - sets security files as GPG keys and SSH keypairs (setup_gpg, setup_ssh); should be made after placing these files next to install.sh
# - installs commonly used apps (install_apps)
# wget https://raw.githubusercontent.com/arthursimas1/my-fedora-post-install/main/install.sh
# run as: bash install.sh
###

set -e

USER_GROUP=arthur:arthur
CONDA_PREFIX=/home/arthur/miniconda3
HAS_BOOT_PARTITION=0

if [[ $(id -u) = 0 ]]; then
   echo "this script changes your users gsettings and should thus not be run as root!"
   echo "you may need to enter your password multiple times!"
   exit 1
fi

setup_dnf() {
  sudo sh -c 'echo -e "fastestmirror=1\nmax_parallel_downloads=20\ndeltarpm=true" >> /etc/dnf/dnf.conf'
  sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                      https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
  sudo dnf upgrade --refresh -y
  sudo dnf groupupdate core -y
  sudo dnf install -y rpmfusion-free-release-tainted dnf-plugins-core
}

disable_wayland() {
  # disabling wayland to enable screen sharing
  sudo sed --in-place 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm/custom.conf
}

setup_ps1() {
  cat <<EOF > custom-ps1.sh
if [ "$USER" == "root" ]; then
   export PS1='[\[\033[01;31m\]\u\[\033[00m\]\[\033[01;32m\]@\h\[\033[00m\] \[\033[01;34m\]\W\[\033[00m\]]\$ '
else
   export PS1='[\[\033[01;32m\]\u\[\033[00m\]\[\033[01;32m\]@\h\[\033[00m\] \[\033[01;34m\]\W\[\033[00m\]]\$ '
fi
EOF
  sudo chown root:root custom-ps1.sh
  sudo chmod 644 custom-ps1.sh
  sudo mv custom-ps1.sh /etc/profile.d
}

rm_old_kernels() {
  # to remove older kernels
  sudo dnf remove -y $(dnf repoquery --installonly --latest-limit=-1 -q)
}

install_nvidia_drivers() {
  # check if booted in last kernel version
  # current kernel: uname -r
  #if [[  ]]

  if [[ $(modinfo -F version nvidia) != 0 ]]; then
    sudo dnf install -y \
      akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-cuda-libs \
      vdpauinfo libva-vdpau-driver libva-utils \
      vulkan
    modinfo -F version nvidia
  fi
}

setup_grub() {
  sudo sh -c 'echo -e "\n\n### BEGIN linux-personal-setup.sh ###\nGRUB_DEFAULT=saved\nGRUB_SAVEDEFAULT=true\nGRUB_ENABLE_BLSCFG=false\n### END linux-personal-setup.sh ###" >> /etc/default/grub'

  sudo dnf -y reinstall grub2-common

  if [[ $HAS_BOOT_PARTITION -eq 1 ]]; then
    #cat /boot/efi/EFI/fedora/grub.cfg
    #search --no-floppy --fs-uuid --set=dev 43fda7f4-cc5e-4c6b-802f-d99e3d2d2320
    #set prefix=($dev)/boot/grub2
    #export $prefix
    #configfile $prefix/grub.cfg

    sudo grub2-editenv create
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
  else
    sudo grub2-editenv /boot/efi/EFI/fedora/grubenv create
    sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
  fi

  sudo dracut -f --regenerate-all
}

setup_git() {
  echo -n "setup_git ... "

  cat <<EOF > .gitconfig
[user]
	email = arthursimas1@gmail.com
	name = Arthur Simas
	signingKey = 6D5A909AEDB93E41A60BDD4A8BE618E9915C28D8
[gpg]
	program = gpg
[commit]
	gpgSign = true
[tag]
	forceSignAnnotated = true
[url "git@github.com:"]
	insteadOf = https://github.com/
[url "git@gitlab.com:"]
	insteadOf = https://gitlab.com/
EOF
  chmod 666 .gitconfig
  chown $USER_GROUP .gitconfig
  mv .gitconfig ~/.gitconfig

  echo "OK"
}

setup_ssh() {
  echo -n "setup_ssh ... "

  mkdir -p ~/.ssh
  cp ssh-key/id_* ~/.ssh
  cp ssh-key/config ~/.ssh

  chown -R $USER_GROUP ~/.ssh

  # ~./ssh : 700 (drwx------)
  chmod 700 ~/.ssh

  # private keys (id_rsa) : 600 (-rw-------)
  sudo chmod 600 ~/.ssh/id_*

  # public keys (.pub) and config: 644 (-rw-r--r--)
  sudo chmod 644 ~/.ssh/id_*.pub

  sudo chmod 600 ~/.ssh/config

  echo "OK"
}

setup_gpg() {
  echo -n "setup_gpg ... "

  gpg --import gpg/gpg-private-arthursimas1.key
  gpg --import-ownertrust gpg/gpg-ownertrust-arthursimas1.txt

  echo "OK"
}

install_apps() {
  echo -n "install_apps ... "

  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  sudo dnf install -y snapd
  sudo ln -s /var/lib/snapd/snap /snap

  snap install authy --beta

  sudo dnf install -y gnome-tweak-tool

  # https://extensions.gnome.org/extension/307/dash-to-dock/)
  sudo dnf install -y sassc
  export SASS=sassc

  git clone --single-branch --branch fzatlouk/gnome-41 https://github.com/frantisekz/dash-to-dock.git
  cd dash-to-dock
  make
  make install
  cd ..
  rm -rf dash-to-dock


  # Touchegg required for X11 Gestures, https://github.com/JoseExposito/touchegg
  sudo dnf copr enable -y jose_exposito/touchegg
  sudo dnf install -y touchegg

  #echo "manually install https://extensions.gnome.org/extension/906/sound-output-device-chooser/"
  #wget https://extensions.gnome.org/extension-data/sound-output-device-chooserkgshank.net.v40.shell-extension.zip
  #gnome-extensions install sound-output-device-chooserkgshank.net.v40.shell-extension.zip
  #rm -f sound-output-device-chooserkgshank.net.v40.shell-extension.zip
  dbus-send --session --print-reply --type=method_call --dest=org.gnome.Shell.Extensions /org/gnome/Shell/Extensions org.gnome.Shell.Extensions.InstallRemoteExtension string:sound-output-device-chooser@kgshank.net

  #echo "manually install https://extensions.gnome.org/extension/4033/x11-gestures/"
  dbus-send --session --print-reply --type=method_call --dest=org.gnome.Shell.Extensions /org/gnome/Shell/Extensions org.gnome.Shell.Extensions.InstallRemoteExtension string:x11gestures@joseexposito.github.io
  #wget https://extensions.gnome.org/extension-data/x11gesturesjoseexposito.github.io.v13.shell-extension.zip
  #gnome-extensions install x11gesturesjoseexposito.github.io.v13.shell-extension.zip
  #rm -f x11gesturesjoseexposito.github.io.v13.shell-extension.zip

  # Google Chrome
  wget https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm
  sudo dnf install -y google-chrome-stable_current_x86_64.rpm
  rm -f google-chrome-stable_current_x86_64.rpm

  sudo dnf remove -y firefox

  sudo flatpak install -y flathub \
    org.gnome.Extensions \
    com.google.AndroidStudio \
    org.freedesktop.Platform.openh264/x86_64/19.08 \
    org.videolan.VLC \
    org.onlyoffice.desktopeditors \
    com.jetbrains.PyCharm-Professional \
    com.jetbrains.CLion \
    com.jetbrains.WebStorm \
    org.telegram.desktop \
    com.slack.Slack \
    com.spotify.Client


  ### DEV APPS ###

  wget https://release.gitkraken.com/linux/gitkraken-amd64.rpm
  sudo dnf install -y gitkraken-amd64.rpm
  rm -f gitkraken-amd64.rpm

  sudo dnf install -y vnstat

  wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  chmod +x Miniconda3-latest-Linux-x86_64.sh
  ./Miniconda3-latest-Linux-x86_64.sh -b -p $CONDA_PREFIX
  rm -f Miniconda3-latest-Linux-x86_64.sh
  $CONDA_PREFIX/bin/conda init bash
  source ~/.bashrc
  conda config --set auto_activate_base false
  conda deactivate

  # https://nodejs.org/en/download/package-manager/#centos-fedora-and-red-hat-enterprise-linux
  sudo dnf install -y nodejs

  # https://stackoverflow.com/questions/40317578/yarn-global-command-not-working
  sudo npm install --global yarn
  yarn config set prefix ~/.yarn
  echo 'export PATH="$PATH:$(yarn global bin)"' >> ~/.bashrc
  yarn global add npm-check-updates expo-cli

  echo "OK"
}

default_config() {
  dconf write /org/gnome/tweaks/show-extensions-notice false

  dconf write /org/gnome/desktop/wm/preferences/button-layout "'appmenu:minimize,maximize,close'"
  dconf write /org/gnome/desktop/interface/enable-hot-corners false
  dconf write /org/gnome/shell/app-switcher/current-workspace-only true
  dconf write /org/gnome/mutter/attach-modal-dialogs false

  dconf write /org/gnome/desktop/interface/text-scaling-factor 0.9
  dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
  dconf write /org/gnome/nautilus/icon-view/default-zoom-level "'standard'"
  dconf write /org/gnome/gedit/preferences/editor/highlight-current-line false

  dconf write /org/gnome/desktop/interface/clock-format "'12h'"
  dconf write /org/gtk/settings/file-chooser/clock-format "'12h'"
  dconf write /org/gnome/desktop/interface/clock-show-weekday true
  dconf write /org/gnome/desktop/interface/clock-show-date true
  dconf write /org/gnome/desktop/interface/show-battery-percentage true

  dconf write /org/gnome/desktop/peripherals/touchpad/disable-while-typing false
  dconf write /org/gnome/desktop/peripherals/touchpad/tap-to-click true
  dconf write /org/gnome/desktop/peripherals/touchpad/two-finger-scrolling-enabled true

  dconf write /org/gnome/desktop/input-sources/xkb-options '@as []'

  dconf write /org/gnome/desktop/session/idle-delay 'uint32 0'
  dconf write /org/gnome/settings-daemon/plugins/power/idle-dim false
  dconf write /org/gnome/settings-daemon/plugins/power/power-saver-profile-on-low-battery false
  dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-ac-type "'nothing'"
  dconf write /org/gnome/settings-daemon/plugins/power/sleep-inactive-battery-type "'nothing'"

  dconf write /org/gnome/desktop/notifications/show-in-lock-screen false

  gnome-extensions enable dash-to-dock@micxgx.gmail.com
  gnome-extensions enable sound-output-device-chooser@kgshank.net
  gnome-extensions enable x11gestures@joseexposito.github.io
  gnome-extensions disable background-logo@fedorahosted.org

  dconf write /org/gnome/shell/extensions/dash-to-dock/intellihide false
  dconf write /org/gnome/shell/extensions/dash-to-dock/dash-max-icon-size 32
  dconf write /org/gnome/shell/extensions/dash-to-dock/isolate-workspaces true
  dconf write /org/gnome/shell/extensions/dash-to-dock/show-trash false
  dconf write /org/gnome/shell/extensions/dash-to-dock/show-mounts false
  dconf write /org/gnome/shell/extensions/dash-to-dock/middle-click-action "'previews'"
  dconf write /org/gnome/shell/extensions/dash-to-dock/hot-keys false
  dconf write /org/gnome/shell/extensions/dash-to-dock/apply-custom-theme true
  dconf write /org/gnome/shell/favorite-apps "['google-chrome.desktop', 'org.gnome.Nautilus.desktop', 'gitkraken.desktop']"

  dconf write /org/gnome/shell/extensions/sound-output-device-chooser/hide-menu-icons true

  dconf write /org/gnome/settings-daemon/plugins/media-keys/home "['<Super>e']"

  dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/binding "'<Super>t'"
  dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/command "'gnome-terminal'"
  dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/name "'Launch Terminal'"
  dconf write /org/gnome/settings-daemon/plugins/media-keys/custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"

  dconf write /org/gnome/desktop/wm/keybindings/switch-applications "@as []"
  dconf write /org/gnome/desktop/wm/keybindings/switch-applications-backward "@as []"
  dconf write /org/gnome/desktop/wm/keybindings/switch-windows "['<Alt>Tab']"
  dconf write /org/gnome/desktop/wm/keybindings/switch-windows-backward "['<Shift><Alt>Tab']"

  dconf write /org/gnome/settings-daemon/plugins/media-keys/area-screenshot-clip "['Print']"
  dconf write /org/gnome/settings-daemon/plugins/media-keys/screenshot "@as []"
}

step_start() {
  case "$1" in
    "1")
    setup_dnf
    ;&

    "2")
    disable_wayland
    ;&

    "3")
    setup_ps1
    ;&

    "4")
    rm_old_kernels
    ;;

    *)
    echo "sequence not matched"
    ;;
  esac
}

step_linux_setup() {
  case "$1" in
    "1")
    install_nvidia_drivers
    ;&

    "2")
    setup_grub
    ;&

    "3")
    setup_git
    ;&

    "4")
    install_apps
    ;&

    "5")
    default_config
    ;;

    *)
    echo "sequence not matched"
    ;;
  esac
}

step_security_setup() {
  setup_gpg
  setup_ssh
}

if [[ -z "$@" ]]; then
  if [[ ! -f ./install-state.txt ]]; then
    step_start 1
    echo "step_start" > install-state.txt
  elif [[ $(cat install-state.txt) = "step_start" ]]; then
    step_linux_setup 1
    echo "step_linux_setup" > install-state.txt
  elif [[ $(cat install-state.txt) = "step_linux_setup" ]]; then
    step_security_setup
    echo "step_security_setup" > install-state.txt
  elif [[ $(cat install-state.txt) = "step_security_setup" ]]; then
    echo "done"
  fi
else
  "$@"
fi
