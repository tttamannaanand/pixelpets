# Pixel Pets

Thea, Ivan and Kai, as tiny pixel pets that live on your Mac.

They live along the top of your screen, just under the menu bar (or, with "Hop onto windows" on, on the tops of your windows too), watch your cursor, nap when you're away, and react when you click or pick them up.

| | |
|---|---|
| **Thea** | dark tabby, black stripes, amber eyes. Do not touch: click her and she flattens her ears, puffs up, hisses and swipes at you, claws out. Hisses at Kai if he gets too close. |
| **Ivan** | grey tabby, green eyes. Click her and she meows, then sits and licks her paw. Grooms a lot, and sometimes flops flat. |
| **Kai** | black puppy, floppy ears. Click him and he wags like mad with his tongue out. Tugs his red rope, and chases the cats. |

## Use it

Click the pet in your menu bar to:
- show or hide each pet
- call everyone to your cursor
- turn on nap time (quiet mode)
- let them hop onto your windows
- change the size
- start at login

Click a pet to pet it. Drag a pet to pick it up and drop it anywhere. Right-click a pet for the menu.

## Build it

```bash
./build.sh          # draws the sprites and builds build/Pixel Pets.app
```

- `sprites.py` draws every sprite from shapes and the pets' colours (Python + Pillow).
- `app/main.swift` is the whole app (Swift, AppKit, no dependencies).
- `make_icon.py` makes the app icon.
