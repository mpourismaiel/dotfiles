# Dotfiles

## Notes

Awesomewm config is available in `awesome` directory, the old readme is in there as well. My configuration of it should be considered deprecated. Hyprland/AGS is my main driver but it's configuration is not even in alpha, works most of the way at this stage.

Wayland is great, Hyprland is fantastic, but a lot of applications don't support them properly. Gaming has been nice as far I can see, programming didn't cause me a lot of headache except some web pages I'm developing cause Firefox to crash. Display detection kinda sucks, `kanshi` has been helpful with that though. Maximized windows are a bit weird, sometimes they pop back into tiling mode. Screen sharing works with OBS virtual camera, screenshotting is a two step process instead of just "PrintScr" and done!

These notes are not to say you should not try Wayland, please do! More users means more incentive for developers to improve their programs. But just beware that these are new grounds for a lot of programs and there are a lot of pot holes around.

## Dependencies

Arch specific names are listed, might be different in your distro.

```
yay -S hyprland aylur-gtk-shell gnome-bluetooth-3.0 satty grim slurp wlr-randr wf-recorder swww matugen
```

You might need to setup an action in your file manager to copy the image you want as wallpaper to `~/.config/background`. For `thunar` I'm using the following:

```
cp %f ~/.config/background # apply to image files
```

You might need the following as well:

```
kanshi: same as arandr for automatic display profile detection
swaylock: for secure screen locker
```

If you are using nvidia follow [this page](https://wiki.hyprland.org/Nvidia/) carefully. You might also need to [disable gdm rules](https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver) if you are using gdm:

```
sudo ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
```

**For Bluetooth to report battery percentage**: Edit `/etc/bluetooth/main.conf` and add `Experimental = true`. ([reference](https://aylur.github.io/ags-docs/services/bluetooth/))

After everything is installed clone this repo and `ln` everything, might need proper `kanshi` config as well.

```
ln -s path-to-mpourismaiel-dotfiles/ags ~/.config/ags
ln -s path-to-mpourismaiel-dotfiles/hyprland ~/.config/hypr
```

## TODO

### Required

- alt-tab switcher window with possibility to pin and favorite windows
- scroll to switch same clients in case of multiple of same class in focus
- info panel
  - calendar
- control center
  - audio
    - mic selector
    - app mixer
  - bluetooth menu
- application launcher
  - calculator
  - open urls
  - search in files
  - shutdown menu
  - plugins?
- lockscreen

### Improvements

- wifi menu password input doesn't open, improve the whole flow
- bluetooth menu is added but not working well, doesn't look for new devices, styling isn't good, pinning devices should be added, removing/unpairing/distrusting should be added
- application menu doesn't have a pinned section, would be good to have categories?
- more osd stuff?
