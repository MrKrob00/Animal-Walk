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
- The leash pair: **the bunny (hero, Chobby Bun) holds the leash, TOFU (red panda) is on it (TOFU wears a red collar with a brass ring at the front; the leash clips to the ring. The colours are my choice, not yet confirmed), and TOFU drags the bunny along** (like DOGWALK, where the dog pulls the kid).
- Control (the player's rule): while the bunny holds the leash, the player steers TOFU. The action button makes the bunny hammer a stake in and tie the leash to it: now the player steers the bunny. Next to the stake (1.4 m) the button pulls it out and control goes back to TOFU.
  - My defaults, not yet confirmed by the player: TOFU just stands and watches the bunny while tied; run = stick pushed far or Shift; leash 3 m; heights bunny 1.6 m, TOFU 1.1 m; camera 8 m away at 52 degrees.
- Setting: a small beach island (the player changed it from winter mountains). Mostly sand with a wet strip at the waterline, grass only on the hilltops in the middle, an uneven shore, turquoise sea with a thin foam line; paper palms with coconuts, flowering bushes on the hills, rocks, dune grass, shells and starfish on the sand. Walkers keep dry feet (95% of the shore radius). The start is on the north beach so the camera looks out over the sea. Footprints take a darker shade of the ground; puffs are sand.
- Animations: the files have no usable walk/run clips (Chobby's own clip tears the mesh), so `scripts/gait.gd` poses the bones in code; the step follows the smoothed real speed. Pelvis sways and twists, chest twists back, head keeps level, nods and looks (at the partner, or around when idle), ears and tail on springs, breathing, three hammer strikes for the stake.
  - The bunny's right hand holds the leash by two-bone IK and follows it strongly (the player asked), but within what a shoulder can do: at most 30 degrees across the chest, 115 degrees back along her side (a leash behind her is reached for along the right side), 65 degrees above the horizon; the elbow bends only the natural way. Slack leash: the hand stays partly toward the leash with a soft elbow and rides the steps; taut leash: the arm straightens toward TOFU. Her right fingers close around the leash while she holds it. The arm moves slowly and smoothly on purpose (eased in over about half a second; the wrist goal follows a soft 1.1 Hz spring, so it never snaps when TOFU turns).
  - The bunny can't keep up (the player's request): dragged at a run she tires over about 4 s ("tires" in her map; TOFU never tires). Worn out: shorter frantic steps, head droops, the free left arm flails for balance, and every 1.2-2.8 s a stumble (a knee buckles, the body pitches forward, arms thrown out). Stopped while more than half tired, she bends over at the hips, a hand toward the knee, panting, until mostly rested (about 4.5 s to recover fully). Looks only: it does not change speeds or the rules. My numbers, not yet confirmed by the player.
  - When the leash end is re-tied (stake in or out), the rope is laid out again at rest (`Leash.reattach_b`), so it does not whip.
  - Chobby's deform bones hung from rigify helper bones that nothing moves: `reparent` in `Actor.BUNNY` re-hangs legs, arms, neck, chest and fingers under the spine and hands (no bone moves).
  - The player wants the chest soft and realistic, not pinned: "soft" parts in Gait follow the body through a damped spring (2.0 Hz, damping 0.27, lag at most 2.4% of height; made a little softer at the player's request). Steady walking only sways it a little; starts, steps and stops push it, and after a stop it swings on by inertia and settles. Keep it realistic, never exaggerated.
  - The step cadence was too fast for the player: strides are longer and grow with speed (bunny 1.45 m walking, 2.5 m running; TOFU 1.1 / 2.0).
  - Chobby's rest pose shows a V-sign with an arm at the face: Gait lowers the arms ("arms_down") and relaxes the fingers ("fingers": all three joints, the tip toward the real "_end" fingertip bone; otherwise the V-sign fingers stay straight).
- Models (Sketchfab unless said; all CC BY; credits in CREDITS.md). Free models only; no paid packs.
  - Hero: Chobby Bun (af9401a3403a425eae680924e8daef79) by Bom39.
  - On the leash: TOFU (75f3298a59804d3baa3d7fb9c3b5992f) by nottodayrender, concept by Luxjii. The model is CC BY, but the character design is Luxjii's and her permission is not stated; the player knows the risk and chose to use it with credit to both. It came without a skeleton: `tools/blender/rig_tofu.py` rigs it into `assets/tofu_rigged.glb`.
  - NPCs: Border Collie Scientist, Farmer Dog, Otter-Chan (AKM); Stylized Bunny, Stylized Deer (hugannh3; furred, not nude); Jacob the fox (jupifox, itch.io). The collie and farmer dog .glb files are broken (Sketchfab's auto-conversion: the body is skinned 100x off); ask the player for the "Original format" downloads.
  - Never: fan-art of other studios' characters, AI-generated models, 18+.
- The code-built wolf and fox kit were rejected ("ugly") and removed.

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
- Blender 5.2 lives in `/opt/blender` (install it again in a fresh container; the player allowed it). Scripts in `tools/blender/`.
- Model checks: `tools/inspect_models.gd` (bones, clips, triangles), `tools/lineup.gd` (all models side by side), `tools/pose_view.gd` (idle/walk/run poses, front or side), `tools/walk_clip.gd` (side clip: walk, stop, run, stop; add `drag` as the 5th argument for a long dragged run and stop; with `--write-movie`), `tools/shot.gd` (scripted play, screenshots; add `--write-movie x.png --fixed-fps 30` for a video).
- Pictures need a screen: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 --script <script>` (headless draws nothing).
- Tests are small and check one thing each; every feature gets a test.

## Traps (from the previous project)
- No global shader uniforms (on the phone everything lit by them came out black); pass values as material uniforms.
- No `discard` and as little overdraw as possible in shaders: the phone pays per pixel.
- A freed object compares `== null` but is not nil: guard with `is_instance_valid`.
- Set a node's position before `add_child` when its `_ready` reads it.
- The default font lacks ✓, arrows and stars: draw icons with `_draw()`.
- A window that pauses the game must release the touch joystick when it closes.
