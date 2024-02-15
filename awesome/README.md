# This is Awesome

This has been my daily driver for over three years now. The base code has been used even longer. Still, it's a work in progress. All the typical stuff work and I don't expect your windows to disappear randomly but bugs are there and features are missing.

I have used this config on it's own and used `nm-applet`, `blueman` and `setxkbmap` in my `config/autostart` file, but using XFCE as the DE has proven much nicer for now. I hope to create more widgets and applets to replace the dependency on secondary gui so you wouldn't worry much about it.

The theme throughout the years have been ignored and theme values have been hardcoded all over the place but I've been trying to organize everything and progress is moving along nicely. Some configuration is already override-able using `config/configuration.json` which I'm trying to create an app to manage. There are examples in `config.example/configuration.json` you can use.

## Install

I will create a nicer documentaion on how everything works and how the install process goes but for now;

- Make sure you are using `awesome-git` in AUR if using pacman or somehow build development version of AwesomeWM.
- Make sure `lua-pam-git` is installed, or the alternative version if you are not using pacman.
- Clone the repo somewhere and make sure submodules are installed: `git clone --recurse-submodules https://github.com/mpourismaiel/dotfiles.git`.
  - If you have already cloned the repo or are trying to update: `git pull && git submodules update --init` will help.
- Go to the cloned directory and create `config/configration.json` and `config/autostart`:

`config/configuration.json` should look like this:

```json
{
  "terminal": "xfce4-terminal",
  "wallpaper": "/home/mahdi/Pictures/wallpaper.jpg",
  "profile_image": "/home/mahdi/Pictures/profile.jpg",
  "commands": {
    "full_screenshot": "flameshot full -p /home/mahdi/Pictures/Screenshots/ -c"
  },
  "available_layouts": ["max", "tile", "tabbed", "machi", "floating"],
  "tags": [
    {
      "name": "1",
      "layout": "max"
    },
    {
      "name": "2",
      "layout": "max"
    },
    {
      "name": "3",
      "layout": "tabbed"
    },
    {
      "name": "4",
      "layout": "max"
    },
    {
      "name": "5",
      "layout": "max"
    },
    {
      "name": "6",
      "layout": "max"
    }
  ]
}
```

All the values except `terminal`, `wallpaper` and `profile_image` have default values.

`config/autostart` should be a text file in which each line will be executed in the terminal to spawn the process. You can add for example `setxkbdmap us,fr` or `firefox -P` each in a new line.

You might find it helpful to check the `scratch.sh` file.

You can also start it in `Xephyr` before uprooting your entire setup. Use:

```sh
$ Xephyr -br -ac -noreset -screen 1920x1080 :2   # if :2 is not possible, change to another display slot. Use that value for DISPLAY variable in the next line
$ DISPLAY=:2 awesome -c ~/.config/awesome        # change to cloned directory path
```

## Other dependencies

I use a bunch of apps in my shortcuts or some stuff that's necessary. You will get notifications for them hopefully if they are missing. Stuff like:

- `flameshot` for screenshots
- `lua-pam-git` for lockscreen
- `system-monitoring-system` for task manager

## Functionalities

A bit too hard to document properly right now, the folder structure in `lib/modules/` and `lib/widgets/` should give you some idea. Use `Super+S` to view keybindings (the documented ones) and `Super+D` to open the launcher, Rofi can be run with `Super+Shift+D` as a backup.

Some functionalities to note:

- Start menu (in search of a better name) displaying notifications and some settings, more settings to come
- Calendar, hopefully integrating Google and other calendar providers soon
- Custom app launcher, with rofi as backup. Allows pinning applications right now with plans to add integrations with web services and `find` command.
- Grouped tasklist, nice task switcher with `Alt+Tab`
- Animations in a lot of places
- Multiple monitor support
- Mouse AND keyboard supported for almost every action, no need to remember a useless keybinding for something you rarely use

## Screenshots

![2023-08-04_12-07](https://github.com/mpourismaiel/dotfiles/assets/14017717/8eacc513-8be6-45d5-bb4a-fb5f2381e33e)
