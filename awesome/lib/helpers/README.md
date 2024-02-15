# Helpers

There are a bunch of helpers I'm using throughout the configuration. Some of them are copied from other people's work of course. `inotify` and `math` and `icon_theme` for example.

I'll try to document the usage of them, mostly for my own use. Also it might come in handly if you stumble upon them.

## Animation

For animation I'm currently using [Aire-one's animation framework](https://github.com/Aire-One/awesome-AnimationFramework) but trying to switch over to [`animation-new`](https://github.com/mpourismaiel/dotfiles/blob/main/lib/helpers/animation-new.lua) which I hope to someday call `animation`. I like the chainability of it more since it looks cleaner. Aire-one's code is fantastic but it gets nested a lot for my liking. There's a lot of inspiration and flat out copying from their code.

### Variables

Since some variable names pop up here and there here's a simplified explanation of what they mean.

- subject: An object representing the current state of things. When animating, on each from the values in this object is changed. The object itself is persisten, the values are being updated.
- target: An object that the animation tries to reach. If animation is successful, subject will look like target. Note that the target object is not touched in the library. You can change it whenever you like and `tween-lua` will try to reach it.
- easing: The tween easing function. There are a bunch of them, you can check them out [here](https://github.com/mpourismaiel/dotfiles/blob/main/lib/helpers/animation-new.lua), look for `EASING_FUNCTIONS`.
- duration: Duration of the animation in seconds (0.2 is 200 milliseconds).

### API

### new({ subject: object, duration: number = 0.2, easing: string = 'linear' })

#### startAnimation(name: string, { from_start: boolean, callback: ({ subject: object, target: object, easing: string, duration: number }) => void} )

#### stopAnimation(name: string, {to_start: boolean})

#### add(name: string, { target: object, duration: number = 0.2, easing: string = 'linear' })

#### change(name: string, { target: object, duration: number = 0.2, easing: string = 'linear' })

#### remove(name: string)

#### updateSubject(subject: string)

#### updateDefaults({ subject: object, duration: number = 0.2, easing: string = 'linear' })

#### onStart((animationName: string, { subject: object, target: object, easing: string, duration: number }) => void)

#### onUpdate((animationName: string, subject: object, delta: number, { subject: object, target: object, easing: string, duration: number }) => void)

#### onFinish((animationName: string, { subject: object, target: object, easing: string, duration: number }) => void)

#### onStop((animationName: string, { subject: object, target: object, easing: string, duration: number }) => void)
