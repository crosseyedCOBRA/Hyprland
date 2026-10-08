#!/usr/bin/env bash
# install.sh -- rebuild this desktop on a fresh base Arch install.
#
# Run as your normal user (with sudo rights) from a clone of this repo:
#   git clone git@github.com:crosseyedCOBRA/hyprland.git ~/hyprland
#   ~/hyprland/install.sh
#
# Assumes the base install is already done: booted, network up, a sudo
# user, GRUB on btrfs (for snapper / grub-btrfs). Safe to re-run -- every
# step skips work that's already done. Existing config files that would be
# replaced are backed up to ~/.config-backup-<timestamp>/ first. Configs are
# symlinked into this repo (bin/link-dotfiles), so later edits land here.
#
# Order: pacman setup + mirrors -> official packages -> dotfiles -> system
# config + services -> user setup -> Flatpaks -> WFHelper -> yay -> AUR
# packages. AUR is last, and only runs once yay is confirmed working, so an
# AUR problem can't block the rest.
#
# Afterwards: reboot into Ly -> Hyprland, then see the checklist printed
# at the end (Steam launch options, LACT, Vesktop).

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKUP=~/.config-backup-$(date +%Y%m%d-%H%M%S)

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root -- it uses sudo where needed." >&2
    exit 1
fi
sudo -v

# Copy a repo file/dir into place, backing up whatever was there.
place() {
    local src=$1 dst=$2
    if [[ -e $dst || -L $dst ]] && ! diff -rq "$src" "$dst" >/dev/null 2>&1; then
        mkdir -p "$BACKUP"
        cp -a "$dst" "$BACKUP/" 2>/dev/null || true
        rm -rf "$dst"
    fi
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

pkglist() { grep -vE '^\s*(#|$)' "$1"; }

# ---------------------------------------------------------------------------
step "pacman: Color, parallel downloads, multilib (32-bit libs for Steam)"
sudo sed -i 's/^#Color$/Color/; s/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    sudo sed -i '/^#\[multilib\]$/{s/^#//;n;s/^#//}' /etc/pacman.conf
fi
grep -A1 '^\[multilib\]' /etc/pacman.conf | sed 's/^/    /'

step "Fastest mirrors (reflector, US/CA, rated by speed)"
sudo pacman -S --needed --noconfirm reflector
sudo install -Dm644 "$REPO/etc/xdg/reflector/reflector.conf" /etc/xdg/reflector/reflector.conf
sudo reflector @/etc/xdg/reflector/reflector.conf || note "reflector failed -- keeping the existing mirrorlist"

step "Official packages ($(pkglist "$REPO/packages/pkglist-repo.txt" | wc -l))"
mapfile -t repo < <(pkglist "$REPO/packages/pkglist-repo.txt")
sudo pacman -Syu --needed --noconfirm "${repo[@]}"

# ---------------------------------------------------------------------------
step "Dotfiles: symlink ~/.config, ~/.local/bin, ... into this repo"
# Edits made in ~/.config land in the repo; `git status` shows them.
"$REPO/bin/link-dotfiles"
# kdeglobals is copied, not linked: KDE's atomic save would replace a link.
place "$REPO/kde/kdeglobals" ~/.config/kdeglobals
# Generated at login by apply-colors (matugen): make sure the target dirs exist.
mkdir -p ~/.cache/hypr ~/.config/swayosd ~/.config/btop/themes ~/.config/vesktop/themes ~/.config/fastfetch
[[ -d $BACKUP ]] && note "replaced files backed up to $BACKUP"

step "App settings: Dolphin dark scheme, Vesktop theme"
kwriteconfig6 --file dolphinrc --group UiSettings --key ColorScheme BreezeDark
vesk=~/.config/vesktop/settings/settings.json
if [[ ! -f $vesk ]]; then
    mkdir -p "$(dirname "$vesk")"
    echo '{ "enabledThemes": ["matugen.theme.css"] }' > "$vesk"
else
    tmp=$(mktemp)
    jq '.enabledThemes = ((.enabledThemes // []) + ["matugen.theme.css"] | unique)' "$vesk" > "$tmp" && mv "$tmp" "$vesk"
fi

# ---------------------------------------------------------------------------
step "System config: LACT overclock, ntsync"
sudo install -Dm644 "$REPO/etc/lact/config.yaml" /etc/lact/config.yaml
# What LACT's "Enable overclocking" button writes: unlocks amdgpu overdrive.
# The driver reads it at boot from the initramfs, so rebuild that.
if ! cmp -s "$REPO/etc/modprobe.d/99-amdgpu-overdrive.conf" /etc/modprobe.d/99-amdgpu-overdrive.conf; then
    sudo install -Dm644 "$REPO/etc/modprobe.d/99-amdgpu-overdrive.conf" /etc/modprobe.d/99-amdgpu-overdrive.conf
    sudo mkinitcpio -P
fi
sudo install -Dm644 "$REPO/etc/modules-load.d/ntsync.conf" /etc/modules-load.d/ntsync.conf
sudo modprobe ntsync || note "ntsync module not available on this kernel"

step "Pacman hook: keep packages/*.txt in this repo current"
sed -e "s|@USER@|$USER|g" -e "s|@REPO@|$REPO|g" "$REPO/etc/pacman.d/hooks/zz-update-pkglists.hook" \
    | sudo install -Dm644 /dev/stdin /etc/pacman.d/hooks/zz-update-pkglists.hook

step "Snapper (root + home) with grub-btrfs boot entries"
if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
    for cfg in root home; do
        mnt=$([[ $cfg == root ]] && echo / || echo /home)
        if ! sudo test -f /etc/snapper/configs/$cfg; then
            sudo snapper -c $cfg create-config "$mnt"
        fi
        sudo install -Dm640 "$REPO/etc/snapper/configs/$cfg" /etc/snapper/configs/$cfg
    done
else
    note "/ is not btrfs -- skipping snapper"
fi

step "Services"
sudo systemctl enable --now NetworkManager bluetooth cups lactd power-profiles-daemon \
    fstrim.timer paccache.timer reflector.timer snapper-timeline.timer snapper-cleanup.timer grub-btrfsd
# Ly replaces the tty1 login prompt (takes effect next boot).
sudo systemctl disable getty@tty1.service 2>/dev/null || true
sudo systemctl enable ly@tty1.service
powerprofilesctl set performance || true

step "User: fish shell, gamemode group, XDG dirs"
[[ $(getent passwd "$USER" | cut -d: -f7) == /usr/bin/fish ]] || sudo chsh -s /usr/bin/fish "$USER"
sudo usermod -aG gamemode "$USER"
xdg-user-dirs-update
fish -c fish_update_completions >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step "Flatpak: Flathub remote + apps ($(pkglist "$REPO/packages/flatpaks.txt" | wc -l), system-wide)"
sudo pacman -S --needed --noconfirm flatpak
sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t flatpaks < <(pkglist "$REPO/packages/flatpaks.txt")
sudo flatpak install --system -y --noninteractive flathub "${flatpaks[@]}"
flatpak list --system --app --columns=application,version | sed 's/^/    /'

step "WFHelper (latest AppImage from GitHub releases)"
if [[ ! -x ~/WFHelper.AppImage ]]; then
    url=$(curl -fsSL https://api.github.com/repos/WFHelper/WFHelper/releases/latest \
          | jq -r '.assets[] | select(.name | endswith(".AppImage")) | .browser_download_url')
    curl -fL -o ~/WFHelper.AppImage "$url"
    chmod +x ~/WFHelper.AppImage
    tmp=$(mktemp -d)
    (cd "$tmp" && ~/WFHelper.AppImage --appimage-extract wfhelper.png >/dev/null)
    install -Dm644 "$tmp/squashfs-root/wfhelper.png" ~/.local/share/pixmaps/wfhelper.png
    rm -rf "$tmp"
else
    note "already installed (it updates itself)"
fi
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/wfhelper.desktop <<EOF
[Desktop Entry]
Name=WFHelper
Comment=Warframe companion: inventory, foundry, relic and riven scanning, market orders.
Exec=$HOME/WFHelper.AppImage --no-sandbox %U
Icon=$HOME/.local/share/pixmaps/wfhelper.png
Terminal=false
Type=Application
StartupWMClass=wfhelper
Categories=Game;
EOF

# ---------------------------------------------------------------------------
# AUR last: everything above only needs the official repos, so a failed yay
# build or a broken AUR package can't stop the rest of the setup.
step "yay (AUR helper)"
aur_status=ok
if ! command -v yay >/dev/null; then
    tmp=$(mktemp -d)
    if git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" &&
       (cd "$tmp/yay-bin" && makepkg -si --noconfirm); then
        note "built and installed"
    fi
    rm -rf "$tmp"
else
    note "already installed"
fi
# Confirm it actually runs before handing it the package list.
if yay_version=$(yay --version 2>/dev/null); then
    note "$yay_version"
else
    aur_status="yay is not working"
fi

if [[ $aur_status == ok ]]; then
    step "AUR packages ($(pkglist "$REPO/packages/pkglist-aur.txt" | wc -l))"
    mapfile -t aur < <(pkglist "$REPO/packages/pkglist-aur.txt")
    if ! yay -S --needed --noconfirm --answerdiff None --answerclean None "${aur[@]}"; then
        aur_status="some AUR packages failed to build"
    fi
    # Report anything from the list that still isn't installed.
    missing=$(for p in "${aur[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || echo "$p"; done)
    if [[ -n $missing ]]; then
        aur_status="missing AUR packages: $(echo $missing)"
    else
        note "all ${#aur[@]} AUR packages installed"
    fi
fi

# ---------------------------------------------------------------------------
if [[ $aur_status == ok ]]; then
    step "Done -- reboot, log in through Ly, and Hyprland starts with a random wallpaper"
else
    step "Done, except the AUR step: $aur_status"
    cat <<EOF
    Everything else is installed. Fix yay / the failed package, then re-run
    this script -- finished steps are skipped. Until then: no Bibata cursor,
    Vesktop, Zen, Brave, Betterbird, Chatterino, Heroic or ProtonPlus.
EOF
fi
cat <<EOF
    After the first login:
      1. Steam: sign in, let it finish, quit Steam completely, then run
           $REPO/steam/launch-options restore
         to bring back every game's launch options.
      2. LACT: overclocking is already unlocked and the saved profile
         (280 W, -50 mV) applies at boot -- open LACT to confirm.
      3. Vesktop: first launch picks up the matugen theme automatically.
      4. Path of Exile 2: launch it once, then copy NeverSink's filters
         (github.com/NeverSinkDev/NeverSink-Filter-for-PoE2/releases) into
         its "My Games/Path of Exile 2" folder inside the Proton prefix, and
         pick "1-REGULAR" in Options > Game > Item Filter.
EOF
