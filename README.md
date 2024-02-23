## Notes

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
