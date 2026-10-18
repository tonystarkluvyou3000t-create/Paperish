extends RefCounted
## Bit masks shared by actors and exit probes. No NPC/traffic layers yet.
## World: layer WORLD, mask WORLD (static geometry).
## Pip: layer PLAYER, mask WORLD | VEHICLE; seated Pip has layer NONE.
## Van: layer VEHICLE, mask WORLD. Its visual asset's static body is disabled.
const NONE := 0
const WORLD := 1
const PLAYER := 2
const VEHICLE := 4
