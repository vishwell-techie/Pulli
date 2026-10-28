# Nizhalattam (நிழலாட்டம்)

**தமிழ்:** [README.ta.md](README.ta.md)

*Nizhalattam* means "shadow play". It is Pulli's platformer showcase: a
side-scrolling action game with a run-based structure, in Tamil and English,
built to push the console as far as it goes: six stories and a courtyard,
each with art of its own, seven bosses and their shadows, eight roles to
wear, rooms read ahead
behind every door, rooms built at run time, three save slots, music and
sound.

A cracked clown puppet, the **Jester** (கோமாளி, Komali), steps through the
lit cloth of a shadow-puppet theatre into the world of its stories. The other
puppets of the troupe are held there by the **Puppet King**, each forced into
a role in one story. The Jester fights through each story, wears the roles of
the puppets he beats, and brings them home, one by one.

## Playing it

Build the desktop host first (see the repository's README), then, from the
repository's root:

```bash
python3 tools/pulli.py run examples/nizhalattam
```

Packing the game with its music takes about a minute (the music is squeezed
as it is packed). To play the same package again without packing it each
time:

```bash
python3 tools/pulli.py pack examples/nizhalattam build/nizhalattam.pulli
python3 tools/pulli.py run build/nizhalattam.pulli
```

### Buttons

| Console | Keyboard | In the game |
|---|---|---|
| D-pad left / right | ← → | run; move through menus and cards |
| D-pad up | ↑ | go through a door; use the box, a stall, the tear or a chest |
| D-pad down + A | ↓ + Z | drop through a thin floor |
| A | Z | jump (hold for higher); in the air again with the double jump; off a wall with the wall jump; choose in menus |
| B | X | strike with the role worn (hold B with the Warrior for a heavy slash; with the Archer, hold to pierce); leave a menu |
| X | A | the role's skill (it then needs time to come back: the bar under the role's name) |
| Y | S | roll: a quick dodge that passes through blows |
| L / R | Q / W | change role: the role coming in strikes as it comes |
| START | Enter | pause |
| SELECT | Right Shift | in the pause, the settings; while playing, show the numbers of the Jester's movement |

In the pause, B goes back to the title; the run stays kept at its last door.

A way in (a door, the theatre's screen, the box, a stall, the halfway tear, a
challenge chest) glows while the Jester stands at it, with the button to
press above it.

### The title screen

The theatre at night: the Jester leaping on the lit cloth, the Puppet King's
shadow behind him. Below are **three save slots**. Each card shows the runs
played through, the oil kept, a bead for each puppet saved, a star when the
King has come home (and a second, blue, when his shadow is torn), and a
flame when a run is waiting at a door.

Left and right choose a slot, A plays it, X twice erases it, SELECT opens
the settings.

**Settings** (SELECT, on the title or in the pause): the language (Tamil or
English), the music's style (Carnatic or Western), the music on or off, and
the sound effects on or off. Up and down choose, left, right or A change, B
or SELECT close. The style is the player's own, whatever the language: until
one is chosen it is Carnatic in Tamil and Western in English. The settings
are the same for all three slots and are kept.

## The story

### The Jester and the troupe

In the courtyard of a temple, at night, stands a shadow-puppet booth, its
cloth screen lit from behind by a lamp. Every night the troupe plays its
stories on it. One night the puppets do not come back from the stories:
the Puppet King keeps them there, each in a role he forced on it. Only the
Jester, cracked and patched, the one who falls over for a laugh, steps
through the cloth after them.

The puppets held, and the stories they are held in:

| Story | The puppet held there |
|---|---|
| The Screen | the **Warrior** (வீரன், Veeran) |
| The Painted Forest | the **Archer** (வில், Vil) |
| The Leather Sea | the **Dancer** (ஆட்டக்காரி, Aattakkaari) |
| The Battlefield of Flags | the **Elephant** (யானை, Yaanai) |
| The Market of Masks | the **Minister** (மந்திரி, Mandhiri) |
| The Lamp Palace | the **Queen** (ராணி, Rani), and the **Puppet King** himself |

The **Puppet Master** (ஆசான், Aasaan), the old puppeteer, waits by his box in
the courtyard. He mends the Jester between runs, for oil.

### The Puppet King

At the top of the Lamp Palace the Puppet King fights in three acts, one for
each act of a play. Each time he is beaten he lets one puppet go, the one the
player chooses, and it goes home to the box. Each puppet saved is one more
move he takes for himself in his third act: the more puppets are home, the
stronger he fights. With all six home, there is no one left for him to give
up but himself: beaten once more, the King comes home too.

### The pages

Six pages of the King's story are hidden in the stories, one in each. They
are read in the order they are found, whichever story each was in, and they
tell who the King was: carved first, before all the others, to be the hero,
painted in gold and sky blue; then, when the troupe needed someone to lose,
painted over in black by the carver's student, who later taught a boy the
craft. That boy is the Puppet Master. No ending depends on the pages.

### The endings

**Ending A.** When the King comes home, the Puppet Master scrapes at his
paint and finds the old colours under it: a hero's. On the festival's last
night the troupe plays, and for one night the King is the hero. The Jester
falls over for a laugh, as always, and it is the biggest laugh of the season.

From then on the game is **hard**, for good (below).

**Ending B.** In hard mode the King's shadow waits at the top of the palace:
the last of the anger he was painted with. When it tears, the Puppet Master
carves the Jester a role of his own, and the troupe plays a new play, the
first in fifty years, with the King and the clown in it together.

Both endings play as scenes on the theatre's cloth, a line under each panel.

## How a run goes

1. **The Courtyard.** The Jester starts by the Puppet Master's box. At the
   box, oil buys repairs that last, places for roles carried from the start,
   and the choice of those roles; the pages found can be read again there,
   and a seed can be typed. The theatre's lit screen is the one door: up at
   it, and the run begins.
2. **The Screen** is always first, a lesson a room: walking and jumping,
   striking, dodging, the skill, a first real fight, the stall, the pits,
   and the Warrior.
3. **Four stories** follow in an order the run's **seed** decides: the
   Painted Forest, the Leather Sea, the Battlefield of Flags and the Market
   of Masks. Each is six rooms and a boss's room.
4. **The halfway tear.** After the third story a rip in the cloth lets the
   Jester change the roles he carries, once a run.
5. **The Lamp Palace** is always last: six rooms, the Queen, then the Puppet
   King's three acts.
6. The King beaten in his third act lets a puppet go home (or comes home
   himself), and the run ends at the box.

**Falling.** When the Jester's health runs out, the run ends: he wakes on the
Puppet Master's box. The run's mai, charms and lent roles are lost; oil,
repairs, saved puppets and pages are kept. A fall into a pit only costs 10
health and puts him back on the last safe ledge. A fall inside a challenge
room puts him back at its door, and the run goes on.

**Kept at every door.** A run is kept each time the Jester goes through a
door. Switch the console off, and when the slot is played again the game
asks whether to take the run up where it was.

**Seeds.** Every run has a five-digit seed, shown in the pause and at the
end. A seed typed at the box plays that run again (the same order of
stories, the same stalls, the same challenge rooms), but keeps nothing.

## The Jester

### His body

| | |
|---|---|
| Health | 100 (+15 a repair, three repairs) |
| Run | 1.6 pixels a frame, full speed in four frames |
| Jump | 4.5 tiles held, about 1.5 tapped: letting go of A cuts the climb |
| Coyote time | 6 frames: he can still jump just after running off a ledge |
| Jump buffer | 6 frames: A pressed just before landing still jumps |
| Roll | 18 frames, passing through blows for 10 of them |
| Wall | slides slowly down a wall he holds into |
| Hit | 60 frames untouchable after a blow; a blow throws him back |

Repairs add the **double jump**, the **wall jump** (A while sliding down a
wall: up and away from it) and a **second roll** straight after the first.

### Roles

The Jester always carries his own role, and up to two more. A beaten puppet
**lends** its role for the rest of the run (with both places full, choose
one to give up for it). A **saved** puppet's role can be carried from the
start of every run, in a place bought at the box. **L** and **R** change
role, and the role coming in strikes as it comes.

| Role | B | X (skill) | Coming in | Its gift |
|---|---|---|---|---|
| **Jester** | three quick slaps; a spinning slap in the air | **pratfall**: flat on the floor, untouchable; shadows close by trip | a cartwheel | rolls come back twice as fast |
| **Warrior** | a three-hit sword combo; hold B for a heavy slash | **shield bash** | an overhead slash | takes 15% less from every blow |
| **Archer** | an arrow, aimed with up or down; hold to pierce | **rain of arrows** on a spot ahead | leaps back, loosing three down | each arrow that strikes makes the next fly further |
| **Dancer** | spinning kicks, each carrying him on | **bells**: a dash through the shadows, stunning them | a whirl all round | each roll leaves a ring that strikes |
| **Elephant** | slow, wide trunk sweeps; the third a slam | **charge**: carries the shadows to the wall | a ground pound | no blow throws him back |
| **Minister** | an ink dart that slows what it strikes | **decoy**: a paper Jester the shadows go for | drops an ink snare | his snares last longer |
| **Queen** | lamp-fire, the third wide | **lamp shield**: turns the next three blows aside | a ring of fire | mends slowly while the shield holds |
| **Puppet King** (once he is home) | wide swings of the sceptre | **summons**: two shadow soldiers fight beside him for 8 s | a cape sweep that turns blows from the front aside | every shadow torn brings the next summons sooner |

## The stories

Each story has its own colours, tiles, backdrop and shadows. Every shadow
**warns** before it strikes (it winds up, flashes, glows or cries), and every
boss shows each move the first time with a warning twice as long.

| Story | Its shadows | Its boss |
|---|---|---|
| **The Screen** | the cut-paper soldier (guards his front; strike from behind or while he rests), straw dummies, inkblots (split in two), scraps (swoop) | the **Warrior**: three slashes, a heavy slash gathered and shining, a dash behind his shield |
| **The Painted Forest** | vine-hands (rise from the leaves and hold him), leaf-moths, banyan wisps (drift through walls, fade) | the **Archer**: aimed arrows and volleys; leaps away when close |
| **The Leather Sea** | crab-shields (claw up in front), wave-cutters (ride the quay), gulls (dive); boats to ride across the water | the **Dancer**: spinning kicks, a stunning dash, a whirl when close |
| **The Battlefield of Flags** | archer lines (draw and loose together), flag-bearers (shadows near the flag take half a blow), war drums (a shockwave along the ground: jump it) | the **Elephant**: charges wall to wall (dizzy after), pounds the ground |
| **The Market of Masks** | mask thieves (snatch mai; caught, pay back double), jugglers (lob knives from their perches), twin masks (sun and moon, swapping places) | the **Minister**: ink darts, ink snares, paper decoys of himself (only he drips ink) |
| **The Lamp Palace** | lamp guards (long spears), mirror shades (the Jester's own shadow, doing what he does a moment later), cinders (burst) | the **Queen**: lamp-fire, a lamp shield that three blows break, a ring of fire; then the **Puppet King** |

**The Puppet King's three acts:** in the first he swings his sceptre, sweeps
up his cape (a blow from the front is turned back on the Jester) and calls
soldiers in from the wings; in the second lamps fall from above (a shadow on
the floor shows where) and he throws his crown, which comes back; in the
third he fights with the moves he has taken, one from each puppet saved.

### Shadow bosses and hard mode

Once a puppet is saved, the King casts a **shadow** of it in its place: in
later runs that story's boss is the puppet's shadow, drawn dark, with a
stronger set of moves, and it lends no role.

| Shadow of | Its stronger moves |
|---|---|
| the Warrior | five slashes, not three; a leaping slash from a distance |
| the Archer | three arrows at once, fanned; a rain of arrows that follows the Jester |
| the Dancer | afterimages: each kick, whirl and dash strikes again a beat later |
| the Elephant | turns at the wall and charges again; stones fall after a pound |
| the Minister | his decoys throw darts too; five snares, lasting longer |
| the Queen | a ring of fire that closes in from far out |

**Hard mode** begins once the King is home, and lasts. Shadows have half as
much health again and hit half as hard again, more of them come, and every
boss is a shadow. At the top of the palace the **King's shadow** fights the
three acts with the puppets' moves, and when it summons, one of the saved
puppets' shadows steps out of the wings with its soldiers, does its move
once, and tears away. Tearing it in the third act is **Ending B**.

## Mai, oil, charms and repairs

**Mai** (மை, ink) is for the run: torn shadows leave drops of ink (bosses a
great deal). It is spent at the **stall** found in each story, and lost
when the run ends.

| At a stall | Mai |
|---|---|
| Mend 25 health (35, 45 with the repair) | 30 |
| Sharpen the role worn: its blows 20% stronger, for the run | 80 |
| A charm (two carried, three with the repair) | 60 to 100 |

Each stall stocks two of the five charms (three with the repair), chosen by
the run's seed and the story:

| Charm | What it does |
|---|---|
| Bell anklet | a roll leaves a ring that strikes |
| Thread spool | pits cost nothing |
| Torn page | the first blow that lands in each room does double |
| Lamp soot | a shadow torn by a blow burns those near it |
| Drum skin | blows stop the world longer, and strike harder |

**Oil** is kept: bosses leave it (from 8 for the Warrior to 25 for the King),
and challenge chests. It is spent at the **Puppet Master's box** on repairs
that last; each takes hold from the next run.

| Repair | Oil |
|---|---|
| More health (+15) | 10, 20, 40 |
| The double jump | 25 |
| Start each run with +50 mai | 10, 20, 30 |
| A place for a role carried from the start | 20, 45 |
| The wall jump | 25 |
| A second roll | 40 |
| Mend 10 more at the stalls | 15, 30 |
| A place for a third charm | 50 |
| Stalls stock one more charm | 30 |

## Secrets and challenge rooms

High on a ledge in each story's stall room, out of reach of a single jump,
waits a door with blue curtains. Only the double jump reaches it. Behind it
is a **challenge room**, built as the Jester steps in, from the run's seed
and the skills he has:

- level ground, steps and pits sized to what he can climb and jump, with the
  story's shadows along the way;
- with the double jump, a step only it climbs, and wider pits;
- with the wall jump, a cliff ten tiles high, climbed by bouncing between it
  and a wall hanging before it;
- with the second roll, a long pit under a low roof, crossed with two rolls.

Every skill he has is wanted somewhere in the room, and nothing he lacks is
asked of him. The shadows there leave nothing when torn. The **chest** at the
far end opens once a run: oil, mai or a charm; in hard mode, while the
story's page is not found, the page and nothing else (in hard mode the pages
lie in the challenge rooms, not where they lay before). Falling in a
challenge room does not end the run: the Jester is back at its door.

## How it is made

### Rooms

The rooms are maps of 8 × 8 tiles made in Tiled (`.tmx`); `pulli pack` turns
each into an `.ooru` map. Layer 0 is the room. Its **objects**, on the
object layer `things`, are where the Jester starts, doors, shadows, bosses,
the stall, the box, the tear, pages and secret doors, each a point whose
class says what it is. `rooms.lua` reads them with `map.objects("things")`
when a room loads and places what they say. A challenge room is laid out as
the Jester steps in, so `challenge.lua` gives its things (its doors,
shadows and chest) the same way.

Each tile's flags are set in `sprites.tsx`: **1**, solid; **2**, a thin floor
(stood on from above, jumped through from below, dropped through with down +
A). Each place has its own tile sheet (`screen.kolam`, `forest.kolam`, ...)
with the same tile numbers, so one tileset serves every room.

Rooms follow one rule: **the way to every door can be climbed with nothing
but a held jump, and with room to spare**: no climb on the way is more than
three tiles, no pit more than six. Higher and wider places are welcome off
the path (rails, perches, the pages that need the double jump, the secret
doors) but never block a run. A test walks every room to check it.

A **story's doors** lead on in its order; its last door leads "next", which
the run's order turns into the next story, the halfway tear, or the end.

### Memory: what is read, and what is let go

The Lua heap is 256 KB, and the game is built to stay well inside it:

- **Code is kept only where it is used.** A story's own shadows
  (`forest.lua`, `sea.lua`, ...) are read in its rooms only; a boss's code in
  his room only; the stall, the box, the role picker, a challenge room's
  builder in their rooms only. Leaving, the code is let go (`unrequire`).
- **A story's rooms and words** (`rooms_forest.lua`, ...) are read while the
  Jester is in the story or at a door into it.
- **A role's code** (`role_vil.lua`, ...) is read while it is carried.
- **The title, the take-up prompt, the endings, the pages** are read while
  they show, then let go.
- **Nothing is made while playing**: shadows, arrows, sparks and scraps are
  kept in pools and few long arrays.
- **Read ahead behind every door.** Going through a door the screen fades;
  behind the fade the next room is loaded, and the rooms beyond its doors,
  their sheets, their code and their music are read ahead (`preload`), so
  nothing is read while the Jester plays.

A challenge room is laid out in the map itself, not in a table of cells, so
building one costs the heap almost nothing.

### Drawing

Each frame starts from the place's still background (`backdrop`, a 320 × 240
picture), then is drawn in passes, a sprite sheet each: the room's tiles,
then the actors (the Jester, the shadows, the things in the room) from
`actors.kolam`, and the big bosses from their own sheets (`vil.kolam`,
`rani.kolam`, ...). Each place sets its own twelve colours (20-31) and their
shades; the characters' twenty (0-19) are the same everywhere. A shadow boss
is the same sprite drawn through a dark palette.

### Music and sound

The music is a Carnatic theatre band: tanpura drone, harmonium, nadaswaram or
flute lead with gamakas, a veena answering, mridangam, thavil or kanjira on a
tala, cymbals, temple bells and a conch. Each place has its own track, in its
own raga; the bosses have one, the King his, the title and the endings
theirs. Every track is a seamless loop of 30 to 40 seconds at 44.1 kHz
stereo; a new one comes in over the old, and the next story's is read ahead
behind its door. Three tracks at a time (one fading out, one playing, one
read ahead) fit in the 6 MB a game may hold.

Twenty-six sound effects (`sfx/`, named in `sound.lua`) mark jumps,
landings, blows, tearing paper, rolls, the shops, pickups, and a bell before
each boss move.

The music has sixteen scenes, a track for each in each style: the title,
the Courtyard, each story and its boss, the King, the endings (`rooms.lua`,
`CLIP`). Until a scene has a Western track of its own, Western plays the
Carnatic one; while the new tracks are being made, the bosses share one track
and the Queen's and the Western ones are not in yet. Prototypes of four
scenes in both styles are in `prototype/` (not packed).

The songs are kept as text (`music/*.json`, made and edited in Pattarai's
Isai); their WAVs are made from them, never committed:
`node tools/pattarai/make-wavs.mjs examples/nizhalattam`. Without the WAVs
the game plays silent (`music()` then does nothing).

### Saves

Three slots (`slot1` to `slot3`), and for all of them the language (`lang`) and
the settings (`settings`: the music's style, music and sound effects on or off).
A slot holds the oil, the runs played through and fallen, the repairs, the
puppets saved and the roles chosen to carry, whether the King is home and his
shadow torn, the pages found, and the run kept at its last door (its seed,
order, room, health, mai, charms, roles, the chests opened).

## The files

Each kind of file has a folder of its own: the Lua in `code/`, the sheets in
`sprites/`, the backdrops (`bg_*`) in `backdrops/`, the rooms and their
tileset in `maps/`, the sounds in `sfx/` and `music/`; `manifest.lua` and
`palette.hex` are at the top. The game names each by its file alone.

### Code

| File | What it is |
|---|---|
| `manifest.lua` | The game's name, id and version, and how its save is kept. |
| `main.lua` | Starts the game and runs a frame: the title, the slots, play, the pause, cards, the endings, falling; the top bar; the drawing passes. Its comment lists every module. |
| `body.lua` | How the Jester moves: running, jumping (the double and wall jumps), rolling, sliding down walls, thin floors, boats, being struck, pits. |
| `fight.lua` | His roles and his blows: the combo, air blows, heavy blows, skills, changing role; the freeze and the shake when a blow lands; charms that change blows. |
| `role_veeran.lua` ... `role_king.lua` | The seven roles he can borrow or carry, one file each (the Jester's own is in `fight.lua`). |
| `shots.lua` | Arrows and ink darts in flight, his and the shadows'. |
| `shadows.lua` | The shadows: the soldier, dummy, inkblot and scrap; tearing; the shadow bosses' dark palette; hard mode's health. |
| `forest.lua`, `sea.lua`, `flags.lua`, `masks.lua`, `palace.lua` | Each story's own shadows (and the sea's boats). |
| `veeran.lua`, `vil.lua`, `aattakkaari.lua`, `yaanai.lua`, `mandhiri.lua`, `rani.lua` | The six bosses, each with its shadow's stronger moves. |
| `king.lua` | The Puppet King in three acts, and his shadow. |
| `rooms.lua` | Rooms and doors: loading a room and its objects, reading ahead, which code and words a room keeps, fades, secret doors, the music, the light at a way in. |
| `rooms_screen.lua` ... `rooms_palace.lua` | Each story's rooms (where their doors lead, their hints, their boss) and its words in both languages. |
| `challenge.lua` | A challenge room: built from the seed and the Jester's skills; its chest. |
| `run.lua` | What is kept between runs and what a run carries; the seed and the stories' order; keeping a run at a door. |
| `resume.lua` | Taking up a kept run when a slot is played. |
| `title.lua` | The title screen and its three slots. |
| `box.lua` | The Puppet Master's box: repairs, roles to carry, the pages, a seed. |
| `stall.lua` | A story's stall: mending, sharpening, charms. |
| `pick.lua` | Choosing roles: at the box, at the tear, when a role is lent with both places full, and the puppet the King lets go. |
| `shelf.lua` | What the box, the stall and the picker are drawn with: a panel and cards. |
| `ending.lua` | The two endings, as scenes. |
| `pages.lua` | The six pages of the King's story, in both languages. |
| `sound.lua` | The sound effects by name. |
| `fx.lua` | Scraps, sparks, and the drops of ink. |
| `lines.lua`, `lines_en.lua`, `lines_ta.lua` | Every word the game shows outside the stories, in English and Tamil, under the same keys. |
| `colours.lua`, `places.lua`, `icons.lua` | The colours by name, each place's twelve colours, and the icons' sprite numbers. |

### Pictures

| File | What it is |
|---|---|
| `actors.png` | The Jester and his roles' frames, the shadows, the Warrior, the stall, the box, the icons. |
| `vil.png`, `aatta.png`, `yaanai.png`, `mandhiri.png`, `rani.png`, `king.png` | Each boss twice the Jester's size, and the Jester's frames for that boss's role. |
| `screen.kolam`, `forest.kolam`, `sea.kolam`, `flags.kolam`, `masks.kolam`, `palace.kolam`, `court.kolam`, `sprites.kolam` | The tile sheets: one a place, and the grey test sheet. |
| `bg_*.kolam` | The backdrops, 320 × 240: the Courtyard, each story, and the title. |
| `palette.hex` | The 64 colours. |
| `sprites.tsx` | The Tiled tileset every room shares, with each tile's flags. |

`.png` files are turned into `.kolam` sheets by `pulli pack`; the `.kolam`
files here are already in the console's form.

### Rooms

| File | What it is |
|---|---|
| `map.tmx` | The Courtyard: the box, and the theatre's screen. |
| `s1.tmx` ... `s7.tmx`, `boss.tmx` | The Screen, a lesson a room, and the Warrior's room. |
| `f1.tmx` ... `f6.tmx`, `fboss.tmx` | The Painted Forest, and the Archer's glade. |
| `k1.tmx` ... `k6.tmx`, `kboss.tmx` | The Leather Sea, and the Dancer's deck. |
| `b1.tmx` ... `b6.tmx`, `bboss.tmx` | The Battlefield of Flags, and the Elephant's field. |
| `m1.tmx` ... `m6.tmx`, `mboss.tmx` | The Market of Masks, and the Minister's court. |
| `p1.tmx` ... `p6.tmx`, `pboss.tmx`, `p7.tmx` ... `p9.tmx` | The Lamp Palace, the Queen's hall, and the King's stage, an act a room. |
| `tear.tmx` | The halfway tear. |
| `challenge.tmx` | Walls only: each challenge room is built in it. |
| `test.tmx`, `climb.tmx`, `arena.tmx` | Grey rooms for tuning the Jester's movement and fights; no door leads to them, the tests go there. |

### Sound

| Folder | What it is |
|---|---|
| `sfx/` | The 26 sound effects, numbered in the order `sound.lua` names them. |
| `music/` | The eleven tracks: the title, the Courtyard, each story, the bosses, the King, the endings. Songs as `.json`; their `.wav` files are made by `tools/pattarai/make-wavs.mjs`. |

The pictures, the rooms and the sound are made by scripts kept with the
project's private material; the files here are what they make. `pulli pack`
turns the `.png`, `.tmx` and `.wav` files into the console's formats, and
leaves the READMEs out.

## Tests

`tests/test_examples.py` plays the game in the headless host and checks it:
the Jester's movement (jump heights, thin floors, walls, pits, rolls, the
double and wall jumps); every role and charm; every shadow and boss, their
warnings, and each shadow boss's stronger moves; hard mode; the King's acts,
his shadow and both endings; the stall, the box and the repairs; the pages;
saves, slots and a run kept at a door; reading ahead behind every door;
every room's doors reached with three-tile climbs; challenge rooms for every
mix of skills, walked and played; the music's choice of track; the sound
effects; that every line is there in both languages; and a **budget for the
Lua heap in every story**, so that growth shows up early.

```bash
cmake -S . -B build -G Ninja && ninja -C build && (cd build && ctest --output-on-failure)
```
