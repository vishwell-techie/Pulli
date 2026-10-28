# Manickam (மாணிக்கம்)

**தமிழ்:** [README.ta.md](README.ta.md)

*Manickam* means "ruby". It is Pulli's showcase game: a short adventure in
Tamil and English, with an opening cut-scene, six chapters, a final meeting
with the shadow serpent and a festival to end on. It is also a test of the
console: the biggest map, the fullest sprite sheet and the heaviest scenes
the platform allows, with a benchmark built in.

Kayal is not a fighter. Nothing in the game is ever hit or killed. She
dodges, she talks, and light is her only tool.

## Playing it

Build the desktop host first (see the repository's README), then, from the
repository's root:

```bash
python3 tools/pulli.py run examples/manickam        # in a window, three times the size
python3 tools/pulli.py run examples/manickam 2      # a smaller window: twice the size
```

The game starts in Tamil. Choose **Options** on the title screen to switch
to English, or to turn music and sounds off.

### Buttons

| Console | Keyboard | In the game |
|---|---|---|
| D-pad | arrow keys | walk; move through menus |
| A | Z | talk, light a lamp, turn a mirror, read on; choose in menus |
| B | X | Minmini flares; back in menus |
| X | A | ask Minmini for a hint |
| START | Enter | pause (the pause screen shows a map of the region); skip a cut-scene |
| SELECT | Right Shift | while playing, show fps, cpu, memory and sprites; while paused, back to the title |
| R | W | on the title, with the benchmark on: stress x1, x2, x4 |

On the title screen SELECT switches the benchmark on and off (see
[The benchmark](#the-benchmark)). Esc closes the window.

### The title screen

- **New game**: the opening, then chapter 0.
- **Continue**: back to the start of the chapter you were in.
- **Chapters**: replay any chapter you have reached.
- **Options**: language (தமிழ் / English), music, sounds.

### How it plays

- **Hearts.** Kayal starts with three. Slimes, thorns, falling rocks and
  Irul's dark orbs each take one, and she blinks for a moment afterwards,
  safe from more harm. When the last one goes, the dark catches her and the
  game is over: A goes back to the title, and Continue starts the chapter
  again with every heart. Each **heart lotus** she finds adds one more, up
  to seven, and fills them all. Her hearts carry on from one chapter to the
  next, and Paati's story between chapters gives one back.
- **Lamps.** Stand by an unlit lamp and press A to light it. Slimes will
  not come near a lit lamp, so lit lamps are safe places.
- **Minmini.** The firefly follows Kayal and lights the way in the dark.
  Press B and she flares: her light swells, and every slime close by shrinks
  and backs away for a few seconds. A flare needs a moment to come back.
  With the **clay lamp** from the potter, Minmini shines further and flares
  sooner.
- **Slimes** chase Kayal when they see her. Some can swim.
- **Water.** Shallow water slows Kayal down. She cannot go into deep water.
- **Thorns** hurt. In the hills, **rocks** fall where their shadows grow.
- **Keys and shrine gates.** A key opens one gate.
- **Switches** raise sunken stepping stones in the lotus lake.
- **Mirrors.** In the temple, A turns a mirror. A beam of light
  reflects off mirrors and lights a lamp it reaches, even one behind rails.
- **Things that stay found.** Ruby pieces, keys, pots, lotuses and heart
  lotuses, once picked up, stay picked up.

The game saves on its own: after each chapter, at checkpoints, and within a
minute of anything changing.

## The story

### The opening: the night before the festival

Tomorrow is Karthigai Deepam, the festival of lamps. In the temple hall of
Kayalur, Paati, the old lamp-keeper, sets her granddaughter Kayal to polish
every lamp until it shines. Above them glows the **Naga Manickam**, a ruby
that has kept the dark away since the village began.

A wind blows through the hall, and every lamp goes out. Out of the temple
tank rises **Irul**, a serpent of shadow. "So much light. There is no room
left for me." It coils round the ruby and shatters it, and seven pieces fly
out over the land.

In the dark a small light appears: **Minmini**, a firefly, who saw where
every piece fell. "Follow my light." Paati sends Kayal on her way: bring
the pieces home before the festival night.

### The chapters

| Chapter | Where | What happens |
|---|---|---|
| 0 | **Kayalur at dusk** | The village has gone dark. Light its three street lamps and keep the slimes from the pond off with Minmini's flare, then leave by the east gate. Paati says the first piece fell past the paddy fields. |
| 1 | **The paddy fields** (Vayal) | The biggest map in the game, 128 × 128 tiles. The piece lies across the river by the old well, and slimes hold the bridge until its two lamps are lit. The potter's three pots blew into the fields; find them and he gives Kayal his clay lamp. |
| 2 | **The banyan forest** (Aalamaram Kaadu) | Night, and a maze under the trees. Only Minmini's light and the lamps Kayal lights show the way. Three shrine gates stand between her and the great banyan, each opened by a key found down a side path. Taking the piece, she sees two red eyes watching from the dark. |
| 3 | **The lotus lake** (Thamarai Kulam) | Two pieces lie out on the islands. The stepping stones sank in the dark; step on the old switches and they rise. Slimes here swim. Seven lotuses grow round the lake, and Paati loves lotuses. |
| 4 | **The thorny hills** (Mullu Malai) | Thorns, and rocks falling in the canyon. The two pieces lie in dark caves, where Minmini is the only light. As Kayal takes the second, Irul brings the cave down, and she has a minute to run for the far mouth while rocks fall all round. |
| 5 | **The temple** (Kovil) | Up through the six floors of the gopuram. Each floor's way up opens when all its lamps burn; some can only be reached by a beam turned there by mirrors. The last piece is at the top, and so is Irul. |
| 6 | **Karthigai Deepam** | The festival. |

### Irul

At the top of the gopuram Irul is coiled round the great lamp. Kayal does
not fight it. In three phases she dodges its dark orbs while lighting four
lamps: by hand, then by turning mirrors to carry the light, then by hand
again after Irul has put them out. An orb that reaches lamplight is gone,
and each phase leaves Irul smaller.

Between the phases they talk. Irul asks why she climbs so high. To light
the great lamp, she says; the village needs it. Irul asks where the dark is
to go, when the festival burns brighter every year. Kayal answers that
night needs the dark too: without it no one would see the stars. She does
not hate it; she only wants the lamps back. Calmed and small, Irul goes
home to the cool and quiet under the hills, and the night is its again.

### Karthigai Deepam

The ruby is whole. Paati asks Kayal to light the great lamp, and the light
runs from lamp to lamp through Kayalur. Two rows of clay lamps light along
the street, the village comes out, and fireworks go up while the credits
rise. If Kayal found all seven lotuses, they make the temple lovelier than
ever.

### Paati's stories

After chapters 1 to 5, Kayal remembers one of Paati's stories:

1. How a serpent king, sheltered from a storm by a lamp-keeper, left the
   ruby in thanks.
2. How fireflies were once stars who loved the earth too much to stay in
   the sky.
3. Why lotuses go to the temple at Karthigai: they grow in mud, yet rise
   clean and bright.
4. How the dark rests in the hill caves by day, and the thorns keep its
   sleep quiet.
5. How night and day are sisters, and if one wins for ever the world goes
   wrong.

### Along the way

- **The potter's pots** (chapter 1): find all three for the clay lamp.
- **Lotuses for the festival** (chapter 3): seven of them.
- **Heart lotuses**: each one, one more heart.

The pause screen shows the ruby pieces found, the hearts and these.

## The files

Each kind of file has a folder of its own: the Lua in `code/`, the sheets in
`sprites/`, the backdrops the rooms and their
tileset in `maps/`, the sounds in `sfx/` and `music/`; `manifest.lua` is at the top. The game names each by its file alone.

| File | What it is |
|---|---|
| `manifest.lua` | The game's name, id and version, and how its save data is kept. |
| `main.lua` | Starts the game; its comment lists every module. |
| `core.lua` | Scenes, buttons, fades and text: the game's own small versions of four SDK helpers (below). |
| `story.lua` | Finds every word the game shows, in the language chosen. |
| `lines_ta.lua`, `lines_en.lua` | Every line of the game, in Tamil and in English, under the same keys. |
| `progress.lua` | Settings and progress, kept as one table in the save data; the numbers of the sounds and music. |
| `title.lua` | The title screen, chapter select and options. |
| `play.lua` | A chapter being played: the loading screen, the top bar, the pause screen and its map, game over, and the step from one chapter to the next. |
| `world.lua` | What every chapter shares: Kayal and Minmini, slimes, lamps, people, things to pick up, gates, switches, stepping stones, water, thorns, mirrors and beams, the camera, night, and being caught. |
| `opening.lua` | The opening cut-scene. |
| `ch0.lua` ... `ch6.lua` | The chapters, each adding what makes it different. |
| `script.lua` | Cut-scenes, written as plain functions that read in order. START skips one, and the world ends up just as if it had been watched. |
| `talk.lua` | The box people talk in. |
| `irul.lua` | Irul: a head and a chain of segments that follow it. |
| `dark.lua` | Night: black everywhere but round the lights, drawn with one `shade()` call. |
| `fx.lua` | Sparks, dust, splashes and fireworks. |
| `bench.lua` | The benchmark. |
| `sprites.png` | The whole sprite sheet, 512 × 256, the most the console holds. The title art, logo included, fills its top-left 320 × 240. |
| `sprites.tsx` | The Tiled tileset every map shares, with each tile's flags. |
| `hall.tmx` | The temple hall, for the opening. |
| `village.tmx` | Kayalur, for chapter 0 and the festival. |
| `vayal.tmx`, `forest.tmx`, `lake.tmx`, `hills.tmx`, `temple.tmx` | Chapters 1 to 5. |
| `top.tmx` | The top of the gopuram, where Irul waits. |
| `music/` | Ten tracks, one for each place and mood, written on Carnatic ragas. |
| `sfx/` | Thirty sound effects. |

Packing the game turns `sprites.png` into `sprites.kolam`, each `.tmx` into
an `.ooru` map, and `music/` and `sfx/` into sound banks, and adds the
SDK's `move` helper. The READMEs are left out.

### The maps

The maps are made in [Tiled](https://www.mapeditor.org) with 8 × 8 tiles.
Layer 0 is the ground. Layer 1 is drawn in front of everyone (tree tops)
and also carries **markers**: the sprites of row 15 of the sheet,
which say where Kayal starts and where people, slimes, pieces, keys,
switches, exits and the rest go. The game reads them and takes them off
when a map loads.

Each tile's flags are set in `sprites.tsx`:

| Flag | Value | Meaning |
|---|---|---|
| solid | 1 | a wall |
| water | 2 | shallow water: slow going |
| hurts | 4 | thorns |
| deep | 8 | deep water: only swimmers |
| dark | 16 | night here, but for the lights |
| lamp | 32 | a lamp, lit or not |
| mirror | 64 | a mirror that turns |
| beam | 128 | sends out a beam of light; the tile's flips set its direction |

## Made to fit

Lua memory is the console's tightest limit: 256 KB, and on a 64-bit desktop
the same game takes nearly twice the memory it does on the console, where
the limit is checked. A module, once loaded, is never let go, so by the
festival every chapter a player has been through is still in memory. The
game is written to fit:

- `core.lua` keeps four SDK helpers' worth of code (scenes, buttons, fades,
  text) in a few larger functions.
- Each language's words are one long string rather than a table of
  strings, and only the language in use is loaded. Tamil is packed to one
  byte a letter once loaded.
- Sparks are slots in five plain arrays, not a table each.
- Slimes chase straight and slide along walls instead of finding paths.
- The festival's clay lamps and crowd are worked out from a few numbers
  each frame instead of being kept as tables.

The water in the lotus lake ripples by **colour cycling**: three blues of
the palette trade colours a few times a second, so every water tile moves
without one being redrawn. The festival draws the whole map in the darker
half of the palette with `pal()`.

## The benchmark

Press SELECT on the title screen: a marker shows that the benchmark is on.
Starting a game then runs the benchmark instead: seven fixed stages, the
game's heaviest kinds of scene, each for a set number of frames with no
input needed.

| Stage | What it draws |
|---|---|
| sprites | 128 moving sprites over a full screen of tiles |
| sparks | bursts of sparks |
| night | a screen of darkness cut by moving lights |
| irul | three serpents and a storm of orbs |
| map | the biggest map, both layers, scrolling |
| text | Tamil text |
| sound | every sound channel busy over the music |

After each stage one line goes to `dbg()`, the terminal on a desktop and
USB serial on a board:

```
bench <stage> frames=<n> cpu_avg=<%> cpu_max=<%> fps_min=<n> mem_peak=<KB>
```

`cpu` is the share of a 60 fps frame the stage used; over 100 means it ran
slower than 60 fps. With the benchmark on, R on the title raises the
stress to x2 and x4, past the platform's budgets, to find where a machine
gives out. The random numbers are seeded the same way every time, so every
machine runs the same frames and the results can be compared. A port with
no clock reports cpu and fps as "n/a".

## Tests

`tests/test_examples.py` plays the game without a window. It checks:

- the opening, and skipping it;
- every chapter starting;
- pausing, and the overlay on SELECT;
- flaring in the dark forest for a minute without running out of memory;
- being caught, the game over screen and the way back to the title;
- hearts carrying on between chapters, and Paati's story giving one back;
- the festival and its fireworks fitting in memory with every chapter
  loaded;
- the benchmark running all its stages.
