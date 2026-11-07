# Pixel Pets

Thea, Ivan and Kai, as tiny pixel pets that live on your Mac.

They live along the top of your screen, just under the menu bar (or, with "Hop onto windows" on, on the tops of your windows too), watch your cursor, nap when you're away, and react when you click or pick them up.

| | |
|---|---|
| **Thea** | dark tabby, black stripes, amber eyes. Do not touch: click her and she flattens her ears, puffs up, hisses and swipes at you, claws out. Hisses at Kai if he gets too close. |
| **Ivan** | grey tabby, green eyes. Click her and she meows, then sits and licks her paw. Grooms a lot, and sometimes flops flat. |
| **Kai** | black puppy, floppy ears. Click him and he wags like mad with his tongue out. Brings his red rope over to your cursor to play, and chases the cats. |

**Feeding time:** pick it from the menu and a bowl for each pet drops near your cursor: fish for the cats, a bone for Kai. They run over and eat it bite by bite, then the cats wash and Kai wags.

**Cuddle naps:** when one cat is asleep, the other may climb up and curl up on top of her, like Ivan does with Thea. Wake the bottom cat and the top one slides off. "Cuddle nap" in the menu starts one.

Every so often a pink pencil, a coffee mug or a ball of yarn turns up on the ledge. The cats will find it, and knock it off. Sounds (Thea's hiss, Ivan's mew and purr, Kai's boof) are synthesised from scratch by `make_sounds.py` and can be turned off in the menu.

## Use it

Click the pet in your menu bar to:
- show or hide each pet
- call everyone to your cursor
- feeding time
- a cuddle nap
- turn sounds on or off
- leave something on the ledge for the cats
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
