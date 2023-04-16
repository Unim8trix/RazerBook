# Arch Linux on Razer Book 13 (RZ09-0357) in Hyprland

This are my personal notes setting up a Razer Book 13 with Arch Linux using Hyprland as window manager. Iam using full disk encryption, and btrfs as filesystem.

Main usage is for DevOps Development, Virtualization and some gaming. Configs for localisations are for german, so adjust for your needs.

A big THANK to [SOL](https://github.com/SolDoesTech/HyprV2) for getting me into hyprland. Most of the Hyprland config is from his repo. Kudos!

[TOC]

## Basic Install

### Prepare and Booting ISO

Boot into BIOS and change your Harwareclock to UTC. Now booting Arch Linux, using a prepared Usbstick

### Change Keyboard and Font

Change keyboard layout with  `loadkeys de-latin1-nodeadkeys`

I also change the font to much bigger size to be better readable on this 13" screen with `setfont sun12x22`

### Networking

For Network i use wireless, if you need wired please check the [Arch WiKi](https://wiki.archlinux.org/index.php/Network_configuration).

Launch `iwctl` and connect to your AP `station wlan0 connect YOURSSID` Type `exit` to leave.

Update System clock with `timedatectl set-ntp true`

### Format Disk

* My Disk is `nvme0n1`, check with `lsblk`
* Partition disk using `gdisk /dev/nvme0n1` with this simple layout:

* `o` for new partition table
* `n,1,<ENTER>,+1024M,ef00` for EFI Boot
* `n,2,<ENTER>,+16G,8200` for swap partition
* `n,3,<ENTER>,<ENTER>,8300` for system partition
* `w` to save layout

Format the EFI Partition

`mkfs.vfat -F 32 /dev/nvme0n1p1`

### Create encrypted filesystem

```bash
cryptsetup luksFormat /dev/nvme0n1p3
cryptsetup open /dev/nvme0n1p3 cryptsys
```

### Create and Mount btrfs Subvolumes

Create btrfs filesystem for root partition.
`mkfs.btrfs -f /dev/mapper/cryptsys`

Mount Partitions und create Subvol for btrfs.

```bash
mount /dev/mapper/cryptsys /mnt
btrfs sub create /mnt/@
btrfs sub create /mnt/@home
```

### Remount with btrfs subvols

Just unmount with `umount /mnt` and remount with subvolumes:

```bash
mount -o noatime,compress=zstd,commit=120,ssd,discard=async,subvol=@ /dev/mapper/cryptsys /mnt
mkdir -p /mnt/boot
mkdir -p /mnt/home
mount -o noatime,compress=zstd,commit=120,ssd,discard=async,subvol=@home /dev/mapper/cryptsys /mnt/home
mount /dev/nvme0n1p1 /mnt/boot/
```

Check mountmoints with `df -Th`

### Install the base system

Just install a base system with some tools for first boot:

```bash
pacstrap /mnt base base-devel linux linux-firmware btrfs-progs \
  intel-ucode networkmanager zsh git git-lfs curl wget reflector neovim
```

After this, generate the filesystem table using
`genfstab -p /mnt >> /mnt/etc/fstab`

Add some zsh configs for a nicer experience

```bash
cp /etc/zsh/zprofile /mnt/root/.zprofile && \
cp /etc/zsh/zshrc /mnt/root/.zshrc
```

### Chroot into the new system and create initial settings

```bash
arch-chroot /mnt /bin/zsh
echo {MYHOSTNAME} > /etc/hostname
echo LANG=de_DE.UTF-8 > /etc/locale.conf
echo LANGUAGE=de_DE >> /etc/locale.conf
echo KEYMAP=de-latin1-nodeadkeys > /etc/vconsole.conf
echo FONT=sun12x22 >> /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
```

Modify `nvim /etc/hosts` with these entries. For static IPs, remove 127.0.1.1

```bash
127.0.0.1 localhost
::1 localhost
127.0.1.1 {MYHOSTNAME}.localdomain {MYHOSTNAME}
```

`nvim /etc/locale.gen` to uncomment the following lines. Change it to your locale and keep en_US cause some tools may need it.

```bash
de_DE.UTF-8 UTF-8
de_DE ISO-8859-1
de_DE@euro ISO-8859-15
en_US.UTF-8
```

Execute `locale-gen` to create the locales now

Set root password and shell

```bash
passwd && \
chsh -s /bin/zsh
```

### Add hooks to initramfs

Edit the configuration with `nvim /etc/mkinitcpio.conf` and add `i915`
to the MODULES section.

I use systemd init style, so add `sd-vconsole and sd-encrypt` to hooks between
block/filesystems like:

```bash
HOOKS="base systemd keyboard autodetect modconf kms block sd-vconsole sd-encrypt filesystems fsck"
```

create Initramfs using `mkinitcpio -p linux`

### Install Systemd Bootloader

`bootctl --path=/boot install` installs bootloader

`nvim /boot/loader/loader.conf` delete anything and add these few lines and save

```bash
default arch.conf
timeout 1
editor 0
```

`nvim /boot/loader/entries/arch.conf` with these lines and save.

```bash
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
```

Append boot options with this command:

```bash
echo "options rd.luks.name=$(blkid -s UUID -o value /dev/nvme0n1p3)=cryptsys \
  rd.luks.options=password-echo=no root=/dev/mapper/cryptsys \
  rootflags=subvol=@ rw" >> /boot/loader/entries/arch.conf
```


### Add Swap Partition

I dont use suspend-to-disk, so i add the swap partition to crypttab und add the swap entry to fstab.

```bash
cryptswap  /dev/nvme0n1p2  /dev/urandom  swap,cipher=aes-xts-plain64,size=256
```

And in `/etc/fstab` add to end of file

```bash
/dev/mapper/cryptswap  none  swap  defaults  0 0
```

### Update Mirrorlist

```bash
reflector --country 'Germany' --latest 10 --sort score --protocol https --save /etc/pacman.d/mirrorlist
```

### Leave Chroot and Reboot

Type `exit` to exit chroot

`umount -R /mnt/` to unmount all volumes

Now its time to `reboot` into the new system!

## After first Reboot

### Enable Wireless Network using NetworkManager

Enable networkmanager on boot

```bash
systemctl enable --now NetworkManager
nmcli device wifi connect "{YOURSSID}" password "{SSIDPASSWORD}"
```

### WLAN Powersave

I want to disable all kind of WLAN powersaving, cause i had issues

For NetworkManager

```bash
# /etc/NetworkManager/conf.d/wifi-powersave-off.conf
[connection]
wifi.powersave = 2
```

And also for kernel module

```bash
# /etc/modprobe.d/iwlwifi.conf
options iwlwifi power_save=0
options iwlwifi uapsd_disable=0
options iwlmvm power_scheme=1
```

### Enable NTP Timeservice

```bash
systemctl enable --now systemd-timesyncd
```

(You may look at `/etc/systemd/timesyncd.conf` for default values and change if necessary)

### Create a new user

Create a new local user and point to zsh

```bash
useradd -m -g users -G wheel,lp,power,audio -s /bin/zsh {MYUSERNAME}
passwd {MYUSERNAME}
```

Execute `EDITOR=nvim visudo` and uncomment `%wheel ALL=(ALL) ALL`

Now `exit` and relogin with the new {MYUSERNAME}

## Install Desktop Environment

### YAY

I want to use YAY for managing packets

```bash
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
```

### Hyprland and other Tools

This tools, i found usefull, will be installed:

* hyprland: this is the compositor

* alacritty: my default terminal

* waybar-hyprland: fork of waybar with Hyprland workspace support

* firefox-developer-edition: my default browser

* swww: used to set a desktop background image

* swaylock-effects: allows for the locking of the desktop its a fork that adds some editional visual effects

* wofi: application launcher menu

* mako: graphical notification daemon

* xdg-desktop-portal-hyprland-git: xdg-desktop-portal backend for hyprland

* thunar: graphical file manager

* mc: midnight commander, a terminal file manager

* polkit-gnome: to get superuser access on some graphical application

* pamixer: audio settings

* pavucontrol: GUI for managing audio and audio devices

* brightnessctl: control monitor and keyboard bright level

* bluez: bluetooth service

* bluez-utils: command line utilities to interact with bluettoth devices

* blueman: bluetooth manager

* network-manager-applet: managing network connection

* gvfs: automount usb drives, etc

* thunar-archive-plugin: front ent for thunar to work with compressed files

* file-roller: tools for working with compressed files

* btop: terminal resource monitor

* pacman-contrib: adds additional tools for pacman. needed for showing system updates in the waybar

* ttf-jetbrains-mono-nerd: the main font

* noto-fonts-emoji: emoji fonts

* cantarell-fonts: nice fonts

* ttf-dejavu: also nice fonts

* lxappearance: set GTK theme

* xfce4-settings: needed to set GTK theme

* pulseaudio: audio server

* sof-firmware, alsa-firmware and alsa-ucm-settings are needed for this Razer Book

```bash
yay -Sy hyprland alacritty waybar-hyprland firefox-developer-edition-i18n-de \
  swww swaylock-effects wofi mako xdg-desktop-portal-hyprland-git \
  brightnessctl mc thunar polkit-gnome pamixer pavucontrol \
  bluez bluez-utils blueman network-manager-applet gvfs \
  thunar-archive-plugin file-roller btop pacman-contrib power-profiles-daemon \
  ttf-jetbrains-mono-nerd noto-fonts-emoji cantarell-fonts ttf-dejavu \
  lxappearance xfce4-settings pulseaudio sof-firmware alsa-firmware alsa-ucm-conf
```

Enable bluetooth and remove some might installed desktop portals

```bash
sudo systemctl enable bluetooth
yay -R --noconfirm xdg-desktop-portal-gnome xdg-desktop-portal-gtk
```

### Enable Wayland for Firefox

```bash
#/etc/environment

MOZ_ENABLE_WAYLAND=1
```

### Theming

Copy the dotfiles to their locations and edit them as needed..

Apply a system-wide dark theme and statusbar/launcher based on Catppuccin (mocha)

```bash
ln -sf ~/.config/waybar/style/style-dark.css ~/.config/waybar/style.css
ln -sf ~/.config/wofi/style/style-dark.css ~/.config/wofi/style.css
xfconf-query -c xsettings -p /Net/ThemeName -s "Adwaita-dark"
xfconf-query -c xsettings -p /Net/IconThemeName -s "Adwaita-dark"
gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
gsettings set org.gnome.desktop.interface icon-theme "Adwaita-dark"
```


### Oh-My-ZSH and Starship

I like to use oh-my-zsh with starship prompt

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
yay -Sy starship
```

Remark `ZSH_THEME="..` and set the starship init at the end of `~/.zshrc` with: `eval "$(starship init zsh)"´

### Install Screnshot Tools

For screenshots i use the swappy

```bash
sudo pacman -Sy grim slurp jq otf-font-awesome swappy
````


## DevOps Tools

Apps and tools i use for devops tasks

### VS Code

Iam using VSCode binary and install it from AUR using

```bash
yay -S visual-studio-code-bin
```

### Python, Ansible and Terraform

I use pyenv to switch between python versions and pip for installing ansible.

Add `export PATH=$HOME/.local/bin/:$PATH` to the PATH variable in .zshrc

```bash
sudo pacman -Sy pyenv terraform
```

Add this to `.zshrc`

```bash
if command -v pyenv 1>/dev/null 2>&1; then
eval "$(pyenv init -)"
fi
```

List avaiable version using `pyenv install --list` and install the desired version with

```bash
pyenv install 3.9.16
pyenv global 3.9.16
```

Install Ansible using pip

```bash
python -m pip install --upgrade pip
python -m pip install --user ansible ansible-lint
```

### Virtualization using QEMU and Libvirt

I go for QEMU/KVM as my hypervisor

```bash
sudo pacman -S qemu virt-manager virt-viewer dnsmasq vde2 \
  bridge-utils openbsd-netcat libguestfs dmidecode

sudo systemctl enable --now libvirtd
```

Enable normal user access by editing `/etc/libvirt/libvirtd.conf`
and enable this lines:

```bash
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
```

Add your user to the group libvirt

```bash
sudo usermod -a -G libvirt $(whoami)
```

Enable nested virtualization

```bash
echo "options kvm-intel nested=1" | sudo tee /etc/modprobe.d/kvm-intel.conf
```

### Kubernetes

Minikube and stuff

```bash
 sudo pacman -S minikube kubectl helm go k9s kubeone
```

For Openlens use the repo from AUR

```bash
yay -S openlens-git
````

For k8s configs i use context switching
(each config is in its own directory to keep it clean) and set some code in my zshrc:

```bash
## Kubectl Context Config
# Set the default kube context if present
DEFAULT_KUBE_CONTEXTS="$HOME/.kube/config"
if test -f "${DEFAULT_KUBE_CONTEXTS}"
then
  export KUBECONFIG="$DEFAULT_KUBE_CONTEXTS"
fi
# Additional contexts should be in ~/.kube/configs/XXXX-XXX-XX/xxx.yml/pem/..
KUBE_CONTEXTS="$HOME/.kube/configs"
mkdir -p "${KUBE_CONTEXTS}"

OIFS="$IFS"
IFS=$'\n'
for contextFile in `find "${KUBE_CONTEXTS}" -type f -name "*.yml" -or -name "*.json"`
do
    export KUBECONFIG="$contextFile:$KUBECONFIG"
done
IFS="$OIFS"
```

## Tweaks

### Autologin

Create a directory named `getty@tty1.service.d/` inside the systemd system unit files directory like:

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/
```

Create a file in this folder called override.conf with the following content:

```bash
# /etc/systemd/system/getty@tty1.service.d/override.conf

[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin {MYUSERNAME} --noclear %I $TERM
```

Now reload systemd and enable getty@tty1 like:

```bash
sudo systemctl daemon-reload
sudo systemctl enable getty@tty1
```

To my zshrc i add theese lines at the end to autostart the hyprland desktop (script in my dotfiles):

```bash
if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec /home/{MYUSERNAME}/hypr
fi
```

After reboot you will be booted straight into sway desktop

### Keyboard Lightning

Install openrazer driver and polychromatic frontend from AUR

```bash
cd ~/AUR
git clone https://aur.archlinux.org/openrazer.git
cd openrazer
makepkg -is
sudo gpasswd -a $USER plugdev

cd ~/AUR
git clone https://aur.archlinux.org/polychromatic.git
cd polychromatic
makepkg -is
```

## WIP: Yubikey

### Using FIDO 2 (Yubikey) with luks partition and systemd

I would also like to use yubikey to unlock the luks partition.
Install the needed FIDO lib and add yubikey to luks partition headers

```bash
sudo pacman -Sy libfido2

systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p3
```

Now edit this line to cryptab:

```bash
cryptsys /dev/nvme0n1p3 - fido2-device=auto
```

Change kernel boot parameters to use fido2. Edit /boot/loader/entries/arch.conf
and edit the rd.luks.options to:

```bash
options .. rd.luks.options=fido2-device=auto root=..
```

Now after reboot, yubikey is required to unluck luks partion

## Gaming

### Enable 32-Bit Lib

Comment out `[multilib]` section in `/etc/pacman.conf`

```bash
[multilib]
Include = /etc/pacman.d/mirrorlist
```

### Install Vulkan Driver and Libs

```bash
sudo pacman -Sy lib32-mesa vulkan-intel lib32-vulkan-intel vulkan-icd-loader \
  lib32-vulkan-icd-loader lib32-systemd ttf-liberation
```

Reboot your book and start installing the steam client

### Steam Client

Install the client from arh repos using

```bash
sudo pacman -Sy steam
```

Many Games just runs, few of them needs special launch parameters.
The [Arch Linux Wiki](https://wiki.archlinux.org/title/steam) is good place to start.

Some games come bundled with old versions of SDL, which do not support Wayland and might
break entirely if you set SDL_VIDEODRIVER=wayland which you normaly do under:

Go to the Game, Properties and Launch options:

``` bash
SDL_VIDEODRIVER=wayland %command%
```

You can also set it via terminal in your current session with:

```bash
set -x SDL_VIDEODRIVER 'wayland'
```

This way, `SDL_VIDEODRIVER` can also set to `x11`
