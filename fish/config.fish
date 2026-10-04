# fish has autosuggestions (accept with ->) and tab completion built in;
# run `fish_update_completions` once after install to also generate
# completions from every installed man page.

# Helper scripts (random-wallpaper, wofi-power, ...) -- same as ~/.bashrc.
fish_add_path -g ~/.local/bin




if status is-interactive
    set -g fish_greeting


    fastfetch
    echo
    echo
    echo
end
