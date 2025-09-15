# Test

### info

This file is a basic Actionfile that contains testcases.


### basic
```sh
action basic.md
```

    Hello, World!

### config
```sh
action config.md
```

    Hello, World!

### override
```sh
action test.md --arg TEST_TEXT="Cruel world!"
```

    Cruel world!

### override2
```sh
action config.md --arg TEST_TEXT="Cruel world!"
```

    Cruel world!

---

## Dotfiles

Assume [`dotfiles`](https://dotfiles.gbraad.nl) is installed

### apps
```sh
action apps.md
```

### pinger
```sh
action ~/.dotapps/pinger.md --arg PINGER_HOST=192.168.1.1
```

### default run
```sh
action info
```
