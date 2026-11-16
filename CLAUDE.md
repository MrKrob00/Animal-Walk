# Working rules for this project

Animal Walk: a game in Godot 4.8 (GL Compatibility) for PC and phones (Android first).
The idea, the hero and the rules of the game are still to be described by the player: ask, do not invent.
This file holds the rules and the player's decisions with their reasons. Update it in the SAME commit as a change of behaviour.

## Working with the player
- The player writes Russian; answer in Russian. Be short and concrete. Code, comments and docs may be in Russian or English (keep one per file).
- The player is the designer. **Ask before any design decision the player did not state** (a look, a rule of the game, a number that changes how it plays). A question with two or three concrete options is fine. Do not "improve" what was described.
- Do exactly what is asked, nothing next to it. A forwarded wish list is not a task: discuss and propose first.
- Before changing an existing mechanic, find out why it is the way it is (here, in docs/, in the code); if it is not written, ask.
- Report honestly: what was measured, what only the phone can confirm, what was not tested.
- Show the result: a screenshot or a short video of every visible change.

## The player's decisions so far
- Inspired by DOGWALK (Blender Studio): keep its look and juice, but our own game. Their CC BY assets are NOT used; we build our own paper-craft look (option "A").
- A leash pair: a big anthro animal leads a little one. For now a wolf (hero) and a fox kit (the player said "take popular furry species").
- Setting: winter mountains. NPCs: not decided yet.
- Character models: the code-built ones in `scripts/critter.gd` are a placeholder the player rejected ("ugly"). Not low-poly: medium quality is fine.
- Models picked from Sketchfab (all CC BY, credit in CREDITS.md when added):
  - NPCs: Border Collie Scientist (76bbf1fdc7e44a7fa1d7ddf1b6860271), Farmer Dog (d7bfa8ca8bdd4df08562099ea605d1f2), Otter-Chan (3b3800d3fe4143c882dde553f9005666) — all by AKM; Stylized Bunny (7c3f75fb982d41958f1759ed1b3f1f38) and Stylized Deer (0dfcaeec76d64678af59e4952a9f2762) by hugannh3. Jacob the fox (jupifox, itch.io) is allowed as an NPC too.
  - Hero: maybe Chobby Bun (af9401a3403a425eae680924e8daef79), not final.
  - On the leash: still searching; fallback is Stylized Deer.
  - Never: fan-art of other studios' characters, AI-generated models, 18+.
  - Free models only (the player said so); no paid packs.

## Git
- Push straight to `main` (no branches, no pull requests): `git fetch origin main`, `git rebase FETCH_HEAD`, `git push origin HEAD:main`.
- Author: `MrKrob00 <170074121+MrKrob00@users.noreply.github.com>`. Never put a private e-mail into the repository.

## Taste (the player's preferences)
- Quiet, soft, non-ringing sounds; nothing shrill. Few notifications and toasts: show, don't tell.
- Real models and sounds, not placeholders (free CC0 packs: Kenney, KayKit, Quaternius; credits in CREDITS.md).
- Juice: things react when touched (a bounce, a puff, a sound), the camera shows what just opened.
- Phone first: the frame must stay smooth on a budget phone (Adreno 610). Measure, do not guess.
- Original game: the genre and mechanics may follow other cozy games, but no names, characters, art, music or maps copied from them.

## Running Godot here
- Godot 4.8 beta 1 (standard, not .NET). Headless tests: `godot --headless --path . --script tests/<suite>.gd`.
- Pictures need a screen: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --script <script>` (headless draws nothing).
- Tests are small and check one thing each; every feature gets a test.

## Traps (from the previous project)
- No global shader uniforms (on the phone everything lit by them came out black); pass values as material uniforms.
- No `discard` and as little overdraw as possible in shaders: the phone pays per pixel.
- A freed object compares `== null` but is not nil: guard with `is_instance_valid`.
- Set a node's position before `add_child` when its `_ready` reads it.
- The default font lacks ✓, arrows and stars: draw icons with `_draw()`.
- A window that pauses the game must release the touch joystick when it closes.
