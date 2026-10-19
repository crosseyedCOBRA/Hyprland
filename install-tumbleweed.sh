#!/usr/bin/env bash
# install-tumbleweed.sh -- rebuild this desktop on a fresh openSUSE Tumbleweed
# install. The Arch counterpart is install.sh; configs (bin/link-dotfiles)
# are shared, only packages and system setup differ.
#
# Run as your normal user (with sudo rights) from a clone of this repo:
#   git clone git@github.com:crosseyedCOBRA/hyprland.git ~/hyprland
#   ~/hyprland/install-tumbleweed.sh
#
# Assumes the base install is already done: booted, network up, a sudo
# user, btrfs root (the installer default -- snapper with zypper snapshots
# and bootable snapshots come with it, so this script only adds /home).
# Works with the default systemd-boot as well as GRUB; the bootloader itself
# is left exactly as the installer set it up.
# Safe to re-run -- every step skips work that's already done, and re-running
# also updates the extras that zypper doesn't manage. Existing config files
# that would be replaced are backed up to ~/.config-backup-<timestamp>/ first.
#
# Order: package-list baseline -> repos (non-oss, Brave, Packman) ->
# packages -> dotfiles -> system config + services -> greetd -> user setup
# -> Flatpaks -> WFHelper -> extras not packaged for openSUSE (matugen,
# adw-gtk3, Bibata, JetBrains Mono Nerd Font, SwayOSD). Extras are last and
# their failures are collected, so a GitHub/build problem can't block the rest.
#
# Afterwards: reboot into greetd (tuigreet) -> Hyprland, then see the
# checklist printed at the end. Updating the system from then on is
# `sudo zypper dup` -- never `zypper up` on Tumbleweed.

set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BACKUP=~/.config-backup-$(date +%Y%m%d-%H%M%S)
STATE=${XDG_STATE_HOME:-~/.local/state}/hyprland-dotfiles
EXTRAS=/usr/local/share/hyprland-dotfiles   # installed version of each extra
ZYPPER=(sudo zypper --non-interactive --gpg-auto-import-keys)

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root -- it uses sudo where needed." >&2
    exit 1
fi
if ! grep -q '^ID="\?opensuse-tumbleweed' /etc/os-release; then
    echo "This is for openSUSE Tumbleweed -- on Arch, use install.sh." >&2
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
step "Package-list baseline (what the fresh install came with)"
# update-pkglists subtracts this from everything installed to find what was
# added on top -- zypper has no pacman -Qqen. Written once, before any
# package below is installed.
if [[ ! -f $STATE/tumbleweed-baseline.txt ]]; then
    mkdir -p "$STATE"
    rpm -qa --qf '%{NAME}\n' | LC_ALL=C sort -u > "$STATE/tumbleweed-baseline.txt"
    note "saved $(wc -l < "$STATE/tumbleweed-baseline.txt") packages to $STATE/tumbleweed-baseline.txt"
else
    note "already saved"
fi

step "Repos: non-oss (Steam), Brave, Packman (full codecs)"
if ! zypper lr -u | grep -q 'tumbleweed/repo/non-oss'; then
    sudo zypper addrepo -f https://download.opensuse.org/tumbleweed/repo/non-oss/ repo-non-oss
fi
if ! zypper lr -u | grep -q 'brave-browser-rpm-release'; then
    sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
    sudo zypper addrepo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
fi
# Priority 90 (lower = preferred) so Packman's full-codec builds win.
if ! zypper lr -u | grep -q 'packman/suse/openSUSE_Tumbleweed'; then
    sudo zypper addrepo -cfp 90 https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/ packman
fi
"${ZYPPER[@]}" refresh
zypper lr -P | sed 's/^/    /'

step "Bring the system current (zypper dup)"
"${ZYPPER[@]}" dup --auto-agree-with-licenses

step "Packages ($(pkglist "$REPO/packages/tumbleweed/packages.txt" | wc -l))"
mapfile -t pkgs < <(pkglist "$REPO/packages/tumbleweed/packages.txt")
"${ZYPPER[@]}" install --auto-agree-with-licenses "${pkgs[@]}"

step "Codecs: switch installed multimedia packages to Packman's builds"
"${ZYPPER[@]}" dup --from packman --allow-vendor-change --auto-agree-with-licenses

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
kwriteconfig6 --file dolphinrc --group UiSettings --key ColorScheme BreezeDark || note "kwriteconfig6 missing -- set Dolphin's color scheme by hand"
vesk=~/.config/vesktop/settings/settings.json
if [[ ! -f $vesk ]]; then
    mkdir -p "$(dirname "$vesk")"
    echo '{ "enabledThemes": ["matugen.theme.css"] }' > "$vesk"
else
    tmp=$(mktemp)
    jq '.enabledThemes = ((.enabledThemes // []) + ["matugen.theme.css"] | unique)' "$vesk" > "$tmp" && mv "$tmp" "$vesk"
fi
# Vesktop is a Flatpak here, and reads ~/.var/app/<id>/config/vesktop instead
# of ~/.config/vesktop. Point that at ~/.config/vesktop (where apply-colors
# writes the theme) and let the sandbox see it. The override is set in the
# Flatpak step, once the app is installed.
vdir=~/.var/app/dev.vencord.Vesktop/config/vesktop
if [[ -L $vdir ]]; then
    :
elif [[ -e $vdir ]]; then
    note "$vdir already exists (Vesktop was run before) -- left alone, theme won't apply"
else
    mkdir -p "$(dirname "$vdir")"
    ln -s ~/.config/vesktop "$vdir"
fi

# ---------------------------------------------------------------------------
step "System config: LACT overclock, ntsync, zram swap"
sudo install -Dm644 "$REPO/etc/lact/config.yaml" /etc/lact/config.yaml
# What LACT's "Enable overclocking" button writes: unlocks amdgpu overdrive.
# The driver may be loaded from the initramfs, so rebuild that. New installs
# boot with systemd-boot (or grub2-bls), where the initrds live on the ESP and
# belong to sdbootutil -- plain dracut would write ones nothing boots.
# `sdbootutil bootloader` errors on classic GRUB, which uses plain dracut.
if ! cmp -s "$REPO/etc/modprobe.d/99-amdgpu-overdrive.conf" /etc/modprobe.d/99-amdgpu-overdrive.conf; then
    sudo install -Dm644 "$REPO/etc/modprobe.d/99-amdgpu-overdrive.conf" /etc/modprobe.d/99-amdgpu-overdrive.conf
    bootloader=$(command -v sdbootutil >/dev/null && sudo sdbootutil bootloader 2>/dev/null || echo grub2)
    note "bootloader: $bootloader"
    case $bootloader in
        systemd-boot|grub2-bls) sudo sdbootutil mkinitrd ;;
        *)                      sudo dracut --force --regenerate-all ;;
    esac
fi
sudo install -Dm644 "$REPO/etc/modules-load.d/ntsync.conf" /etc/modules-load.d/ntsync.conf
sudo modprobe ntsync || note "ntsync module not available on this kernel"
sudo install -Dm644 "$REPO/etc/systemd/zram-generator.conf" /etc/systemd/zram-generator.conf
sudo systemctl daemon-reload
sudo systemctl start systemd-zram-setup@zram0.service || note "zram swap starts on next boot"

step "Zypper plugin: keep packages/tumbleweed/*.txt in this repo current"
sed -e "s|@USER@|$USER|g" -e "s|@REPO@|$REPO|g" "$REPO/etc/zypp/plugins/commit/zz-update-pkglists" \
    | sudo install -Dm755 /dev/stdin /usr/lib/zypp/plugins/commit/zz-update-pkglists

step "Snapper: add /home (root is set up by the installer)"
# Root keeps openSUSE's own config -- it's tuned for zypper's pre/post
# snapshots and space-aware cleanup. /home gets the same config as on Arch.
if [[ $(findmnt -no FSTYPE /) == btrfs ]]; then
    if ! sudo test -f /etc/snapper/configs/root; then
        sudo snapper -c root create-config /
        sudo install -Dm640 "$REPO/etc/snapper/configs/root" /etc/snapper/configs/root
    fi
    if [[ $(findmnt -no FSTYPE /home) == btrfs ]]; then
        sudo test -f /etc/snapper/configs/home || sudo snapper -c home create-config /home
        sudo install -Dm640 "$REPO/etc/snapper/configs/home" /etc/snapper/configs/home
    else
        note "/home is not btrfs -- no /home snapshots"
    fi
    sudo snapper list-configs | sed 's/^/    /'
else
    note "/ is not btrfs -- skipping snapper"
fi

step "Services"
sudo systemctl enable --now bluetooth cups lactd power-profiles-daemon \
    fstrim.timer snapper-timeline.timer snapper-cleanup.timer
# The installer picks wicked on some system roles; don't fight it mid-run.
if systemctl is-enabled --quiet wicked 2>/dev/null; then
    note "wicked manages the network -- switch to NetworkManager in YaST > Network Settings"
else
    sudo systemctl enable --now NetworkManager
fi
powerprofilesctl set performance || true

step "Login: greetd + tuigreet (replaces Ly)"
# Keep the packaged config (its greeter user) and only swap the command.
greet_cmd='tuigreet --time --remember --remember-session --asterisks --sessions /usr/share/wayland-sessions'
sudo sed -i "s|^command *=.*|command = \"$greet_cmd\"|" /etc/greetd/config.toml
grep '^command' /etc/greetd/config.toml | sed 's/^/    /'
# openSUSE picks the display manager through this alternative, if present.
if [[ -e /usr/lib/X11/displaymanagers/greetd ]]; then
    sudo update-alternatives --set default-displaymanager /usr/lib/X11/displaymanagers/greetd
fi
for dm in sddm gdm lightdm; do
    systemctl is-enabled --quiet $dm 2>/dev/null && sudo systemctl disable $dm
done
sudo systemctl enable --force greetd.service
sudo systemctl set-default graphical.target

step "User: fish shell, gamemode group, XDG dirs"
[[ $(getent passwd "$USER" | cut -d: -f7) == /usr/bin/fish ]] || sudo chsh -s /usr/bin/fish "$USER"
getent group gamemode >/dev/null && sudo usermod -aG gamemode "$USER"
xdg-user-dirs-update
fish -c fish_update_completions >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step "Flatpak: Flathub remote + apps ($(pkglist "$REPO/packages/tumbleweed/flatpaks.txt" | wc -l), system-wide)"
sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
mapfile -t flatpaks < <(pkglist "$REPO/packages/tumbleweed/flatpaks.txt")
sudo flatpak install --system -y --noninteractive flathub "${flatpaks[@]}"
# Lets Vesktop follow the symlink to ~/.config/vesktop (see App settings).
sudo flatpak override --system --filesystem=xdg-config/vesktop dev.vencord.Vesktop
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
# Extras: on Arch these come from the repos/AUR; openSUSE doesn't package
# them, so they come from their GitHub releases. Each records the release it
# installed in $EXTRAS/<name>, so a re-run updates it only when upstream has a
# newer one. zypper never touches these -- re-run this script to update them.
failed=()

# extra <name> <github owner/repo> <install function>
# The function gets the release tag and a temp dir to work in.
extra() {
    local name=$1 gh=$2 fn=$3 tag have tmp
    step "Extra: $name ($gh)"
    if ! tag=$(curl -fsSL "https://api.github.com/repos/$gh/releases/latest" | jq -er .tag_name); then
        note "couldn't reach GitHub"; failed+=("$name"); return
    fi
    have=$(cat "$EXTRAS/$name" 2>/dev/null || true)
    if [[ $have == "$tag" ]]; then
        note "$tag already installed"; return
    fi
    tmp=$(mktemp -d)
    # Not `if (...)`: bash ignores set -e inside a condition, even in a
    # subshell, so a failed download/build would count as success.
    set +e
    (set -e; cd "$tmp"; "$fn" "$tag")
    local rc=$?
    set -e
    if [[ $rc -eq 0 ]]; then
        echo "$tag" | sudo install -Dm644 /dev/stdin "$EXTRAS/$name"
        note "installed $tag${have:+ (was $have)}"
    else
        failed+=("$name")
    fi
    rm -rf "$tmp"
}

dl() { curl -fL --retry 3 -o "$2" "https://github.com/$1"; }

install_matugen() {   # colour scheme generator behind apply-colors
    dl "InioX/matugen/releases/download/$1/matugen-${1#v}-x86_64.tar.gz" m.tar.gz
    tar xzf m.tar.gz
    sudo install -Dm755 matugen /usr/local/bin/matugen
}
install_adw_gtk3() {  # GTK3 theme (gtk-3.0/settings.ini: adw-gtk3-dark)
    dl "lassekongo83/adw-gtk3/releases/download/$1/adw-gtk3$1.tar.xz" a.tar.xz
    tar xJf a.tar.xz
    sudo rm -rf /usr/share/themes/adw-gtk3 /usr/share/themes/adw-gtk3-dark
    sudo cp -r adw-gtk3 adw-gtk3-dark /usr/share/themes/
}
install_bibata() {    # cursor (icons/default/index.theme: Bibata-Modern-Ice)
    # /usr/share/icons, not /usr/local: Xcursor's default path skips /usr/local.
    dl "ful1e5/Bibata_Cursor/releases/download/$1/Bibata-Modern-Ice.tar.xz" b.tar.xz
    tar xJf b.tar.xz
    sudo rm -rf /usr/share/icons/Bibata-Modern-Ice
    sudo cp -r Bibata-Modern-Ice /usr/share/icons/
}
install_nerd_font() { # kitty / hyprlock font: JetBrainsMono Nerd Font
    dl "ryanoasis/nerd-fonts/releases/download/$1/JetBrainsMono.tar.xz" f.tar.xz
    mkdir fonts && tar xJf f.tar.xz -C fonts
    sudo rm -rf /usr/local/share/fonts/JetBrainsMonoNerd
    sudo install -Dm644 -t /usr/local/share/fonts/JetBrainsMonoNerd fonts/*.ttf
    sudo fc-cache -f /usr/local/share/fonts >/dev/null
}
install_swayosd() {   # volume OSD (swayosd-server / swayosd-client in hyprland.lua)
    # Build deps (meson, cargo, gtk4-devel, ...) are in packages.txt.
    dl "ErikReider/SwayOSD/archive/refs/tags/$1.tar.gz" s.tar.gz
    tar xzf s.tar.gz
    cd SwayOSD-*
    meson setup build --prefix=/usr/local --buildtype=release
    ninja -C build
    # --no-rebuild: upstream's cargo target is always stale, and rerunning
    # cargo as root would build into root-owned dirs.
    sudo meson install -C build --no-rebuild
}

extra matugen   InioX/matugen          install_matugen
extra adw-gtk3  lassekongo83/adw-gtk3  install_adw_gtk3
extra bibata    ful1e5/Bibata_Cursor   install_bibata
extra nerd-font ryanoasis/nerd-fonts   install_nerd_font
extra swayosd   ErikReider/SwayOSD     install_swayosd

# Record the packages this run added (the zypper plugin only does this from
# the next zypper transaction on).
"$REPO/bin/update-pkglists" || true

# ---------------------------------------------------------------------------
if [[ ${#failed[@]} -eq 0 ]]; then
    step "Done -- reboot, log in through tuigreet (pick Hyprland once; it's remembered)"
else
    step "Done, except these extras: ${failed[*]}"
    cat <<EOF
    Everything else is installed. Fix the problem (usually network/GitHub
    rate limits, or a SwayOSD build error above), then re-run this script --
    finished steps are skipped.
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
    From now on: update with \`sudo zypper dup\` (never \`zypper up\`), and
    re-run this script now and then to update the extras above.
EOF
