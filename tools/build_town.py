"""Build the delivery town for Pip the Pizza Boy.

Same conventions as tools/build_art.py: flat box geometry, shared flat materials
from one palette, named pieces, hand-editable .tscn output.

Layout (metres, Godot Y up, island centred on the origin):
  * island 68 x 56, single walkable plane at y = 0.07 with cosmetic +/-0.03 relief
  * Marinara Way runs east-west through the middle (z = -3.2 .. 3.2)
  * Basil Street (x = -16.4 .. -10) and Olive Street (x = 10 .. 16.4) run north-south
  * eight customer houses line Marinara Way at |x| = 20.9 and 29.5
  * centre-north block is a park with a pond, centre-south block is the pizza plaza
"""
from pathlib import Path
import math, random
import argparse
from townkit import (Scene, PALETTE, ROOT, OUTPUT_ROOT, tree, bush, flower_clump, lamppost, bench,
                     hydrant, cone, bin, mailbox, hedge, IS_X0, IS_X1, IS_Z0, IS_Z1,
                     GRASS_TOP, ROAD_TOP, WALK_TOP, MARK_TOP, RIM_TOP, MAIN_Z0, MAIN_Z1,
                     MAIN_X0, MAIN_X1, BASIL_X0, BASIL_X1, OLIVE_X0, OLIVE_X1, VROAD_Z,
                     SW, SHOP_Z, FRONT_OFF, HOUSE_W, HOUSE_D, GROUND_TOP)
from world_data import (HOUSE_STYLES, get_layout, write_layout, DECORATION_SEED,
                        CROSSING_SPANS)

random.seed(DECORATION_SEED)

# keep grass tufts away from every built surface
CLEAR = []


def clear(x0, x1, z0, z1):
    CLEAR.append((min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)))


def free(x, z):
    for x0, x1, z0, z1 in CLEAR:
        if x0 <= x <= x1 and z0 <= z <= z1:
            return False
    return True


# --------------------------------------------------------------------------- island
def island():
    s = Scene('TownIsland')
    # cutaway earth block, exactly the original land tile treatment, scaled up
    width, depth = IS_X1 - IS_X0, IS_Z1 - IS_Z0
    s.box('Earth_block', (0, -.5, 0), (width, .86, depth), 'soil')
    s.box('Grass_top', (0, -.04, 0), (width, .18, depth), 'grass')
    s.box('Earth_lower', (0, -.94, 0), (width - .3, .16, depth - .3), 'soil_light')
    for i in range(int(width / 1.45)):
        x = IS_X0 + 1.0 + i * 1.45
        if i % 3:
            s.box('Soil_pixel', (x, -.44 - (i % 3) * .16, 28.01), (.55, .15, .03), 'soil_light')
    for i in range(int(depth / 1.45)):
        z = IS_Z0 + 1.0 + i * 1.45
        if i % 3 == 1:
            s.box('Soil_side_pixel', (34.01, -.45 - (i % 2) * .2, z), (.03, .15, .55), 'soil_light')
    # tidy paving rim all the way round the island edge
    s.plate('Rim_north', IS_X0 + .8, IS_X1 - .8, IS_Z0, IS_Z0 + .8, 'paving_light', RIM_TOP)
    s.plate('Rim_south', IS_X0 + .8, IS_X1 - .8, IS_Z1 - .8, IS_Z1, 'paving_light', RIM_TOP)
    s.plate('Rim_west', IS_X0, IS_X0 + .8, IS_Z0 + .8, IS_Z1 - .8, 'paving_light', RIM_TOP)
    s.plate('Rim_east', IS_X1 - .8, IS_X1, IS_Z0 + .8, IS_Z1 - .8, 'paving_light', RIM_TOP)

    # ---------------------------------------------------------------- roads
    s.plate('Marinara_asphalt', MAIN_X0, MAIN_X1, MAIN_Z0, MAIN_Z1, 'road', ROAD_TOP)
    s.plate('Basil_asphalt_n', BASIL_X0, BASIL_X1, -VROAD_Z, MAIN_Z0, 'road', ROAD_TOP)
    s.plate('Basil_asphalt_s', BASIL_X0, BASIL_X1, MAIN_Z1, VROAD_Z, 'road', ROAD_TOP)
    s.plate('Olive_asphalt_n', OLIVE_X0, OLIVE_X1, -VROAD_Z, MAIN_Z0, 'road', ROAD_TOP)
    s.plate('Olive_asphalt_s', OLIVE_X0, OLIVE_X1, MAIN_Z1, VROAD_Z, 'road', ROAD_TOP)
    clear(MAIN_X0, MAIN_X1, MAIN_Z0, MAIN_Z1)
    clear(BASIL_X0 - SW, BASIL_X1 + SW, -VROAD_Z, VROAD_Z)
    clear(OLIVE_X0 - SW, OLIVE_X1 + SW, -VROAD_Z, VROAD_Z)

    # ---------------------------------------------------------------- sidewalks
    s.plate('Walk_main_s', MAIN_X0, MAIN_X1, MAIN_Z1, MAIN_Z1 + SW, 'paving', WALK_TOP)
    s.plate('Walk_main_n', MAIN_X0, MAIN_X1, MAIN_Z0 - SW, MAIN_Z0, 'paving', WALK_TOP)
    for a, b, tag in [(BASIL_X0 - SW, BASIL_X0, 'basil_w'), (BASIL_X1, BASIL_X1 + SW, 'basil_e'),
                      (OLIVE_X0 - SW, OLIVE_X0, 'olive_w'), (OLIVE_X1, OLIVE_X1 + SW, 'olive_e')]:
        s.plate('Walk_%s_n' % tag, a, b, -VROAD_Z, MAIN_Z0 - SW, 'paving', WALK_TOP)
        s.plate('Walk_%s_s' % tag, a, b, MAIN_Z1 + SW, VROAD_Z, 'paving', WALK_TOP)
    # curb line + expansion joints
    for z in (MAIN_Z0, MAIN_Z1):
        s.plate('Curb', MAIN_X0, MAIN_X1, z - .09, z + .09, 'paving_light', WALK_TOP + .012)
    for tag, a, b in [('basil', BASIL_X0, BASIL_X1), ('olive', OLIVE_X0, OLIVE_X1)]:
        for x in (a - .09, b + .09):
            s.plate('Curb_%s' % tag, x - .09, x + .09, -VROAD_Z, MAIN_Z0, 'paving_light', WALK_TOP + .012)
            s.plate('Curb_%s' % tag, x - .09, x + .09, MAIN_Z1, VROAD_Z, 'paving_light', WALK_TOP + .012)
    for i in range(15):
        x = -30.0 + i * 4.3
        s.plate('Walk_joint_s', x, x + .1, MAIN_Z1, MAIN_Z1 + SW, 'paving_light', WALK_TOP + .008)
        s.plate('Walk_joint_n', x, x + .1, MAIN_Z0 - SW, MAIN_Z0, 'paving_light', WALK_TOP + .008)

    # ---------------------------------------------------------------- markings
    for x in range(-30, 31, 3):
        if -18.6 < x < -7.8 or 7.8 < x < 18.6:
            continue
        for z in (-1.65, 1.65):
            s.rect_mark('Lane_dash', x, x + 1.4, z - .075, z + .075, 'ivory', MARK_TOP)
    for z in range(-25, 26, 3):
        if -5.4 < z < 5.4:
            continue
        for x in (BASIL_X0 + 3.2, OLIVE_X0 + 3.2):
            s.rect_mark('Lane_dash_ns', x - .075, x + .075, z, z + 1.4, 'ivory', MARK_TOP)
    for x0, x1 in [(MAIN_X0, -18.2), (-8.2, 8.2), (18.2, MAIN_X1)]:
        for z in (MAIN_Z0 + .22, MAIN_Z1 - .22):
            s.rect_mark('Road_edge', x0, x1, z - .07, z + .07, 'ivory', MARK_TOP)
    # pedestrian crossings aligned with the sidewalk corridors
    for x0, x1 in CROSSING_SPANS:
        for i in range(6):
            z = -2.8 + i * 1.12
            s.rect_mark('Crosswalk', x0 + .05, x1 - .05, z, z + .56, 'ivory', MARK_TOP)

    # ---------------------------------------------------------------- plaza block
    s.plate('Forecourt', -8.2, 8.2, MAIN_Z1 + SW, 8.95, 'paving_light', WALK_TOP)
    s.plate('Forecourt_trim', -8.2, 8.2, 8.95, 9.15, 'paving', WALK_TOP + .008)
    for i in range(9):
        x = -7.6 + i * 1.9
        s.rect_mark('Forecourt_paver', x, x + .85, 5.4, 6.25, 'paving', WALK_TOP + .006)
    s.plate('Service_yard', -8.2, 8.2, 13.2, 18.0, 'paving', WALK_TOP - .01)
    s.plate('Service_path', -1.2, 1.2, 12.4, 13.4, 'paving', WALK_TOP - .01)
    # parking bays on the south kerb in front of the shop
    for x in (-3.9, -1.3, 1.3, 3.9):
        s.rect_mark('Bay_line', x - .06, x + .06, .75, MAIN_Z1 - .1, 'ivory', MARK_TOP)
    s.rect_mark('Bay_back', -3.9, 3.9, .68, .8, 'ivory', MARK_TOP)
    for x in (17.8, 20.2, 22.6):
        s.rect_mark('Bay_line_n', x - .06, x + .06, MAIN_Z0 + .1, -.75, 'ivory', MARK_TOP)
    s.rect_mark('Bay_back_n', 17.8, 22.6, -.8, -.68, 'ivory', MARK_TOP)

    # ---------------------------------------------------------------- park block
    clear(-8.2, 8.2, 3.2, 18.6)
    P_X0, P_X1, P_Z0, P_Z1 = -4.6, 4.6, -17.4, -11.4
    s.plate('Park_path', -1.1, 1.1, P_Z1, MAIN_Z0 - SW, 'paving_light', WALK_TOP + .004)
    s.plate('Park_apron', -3.4, 3.4, P_Z1 - 1.4, P_Z1, 'paving_light', WALK_TOP)
    s.plate('Pond_water', P_X0, P_X1, P_Z0, P_Z1, 'glass', .062, thick=.05)
    # Water is a visible hazard and a solid world surface, not decorative floor.
    s.collider('Pond_water_barrier', ((P_X0 + P_X1) / 2, .62, (P_Z0 + P_Z1) / 2),
               (P_X1 - P_X0, 1.1, P_Z1 - P_Z0))
    for x0, x1, z0, z1 in [(P_X0 - .45, P_X1 + .45, P_Z0 - .45, P_Z0),
                           (P_X0 - .45, P_X1 + .45, P_Z1, P_Z1 + .45),
                           (P_X0 - .45, P_X0, P_Z0, P_Z1),
                           (P_X1, P_X1 + .45, P_Z0, P_Z1)]:
        s.plate('Pond_rim', x0, x1, z0, z1, 'paving', WALK_TOP)
    for x in (1.1, 1.55, 2.0):
        s.box('Pier_plank', (x, .11, P_Z1 + 1.0), (.42, .07, 1.5), 'crust')
    for i in range(3):
        s.box('Lily_pad', (P_X0 + 1.4 + i * 2.1, .075, P_Z0 + 1.6 + (i % 2) * 1.9),
              (.62, .03, .52), 'leaf')
        s.box('Lily_flower', (P_X0 + 1.4 + i * 2.1, .1, P_Z0 + 1.6 + (i % 2) * 1.9),
              (.16, .07, .16), 'white')
    for x, z in [(P_X0 + .5, P_Z0 + .6), (P_X1 - .7, P_Z1 - .8)]:
        s.box('Pond_rock', (x, .1, z), (.7, .22, .6), 'metal')
    for x, z in [(P_X0 + 1.0, P_Z1 - .2), (P_X1 - 1.2, P_Z0 + .3), (P_X1 - .3, P_Z1 - 1.6),
                 (P_X0 + .2, P_Z0 + 2.6)]:
        for j in range(3):
            s.box('Reed', (x + j * .2, .34, z), (.05, .68, .05), 'leaf')

    # ---------------------------------------------------------------- grass tufts
    for i in range(150):
        x = random.uniform(IS_X0 + 1.2, IS_X1 - 1.2)
        z = random.uniform(IS_Z0 + 1.2, IS_Z1 - 1.2)
        if not free(x, z):
            continue
        s.box('Grass_voxel', (x, .09, z), (.16, .08, .24),
              'grass_light' if i % 2 else 'grass_dark')

    # one ground collision plane for the whole island + a fence of invisible walls
    s.collider('Ground_collision', (0, GROUND_TOP - .3, 0), (width, .6, depth))
    for name, loc, size in [('Edge_n', (0, 1.6, IS_Z0 + .3), (68, 3.2, .6)),
                            ('Edge_s', (0, 1.6, IS_Z1 - .3), (68, 3.2, .6)),
                            ('Edge_w', (IS_X0 + .3, 1.6, 0), (.6, 3.2, 56)),
                            ('Edge_e', (IS_X1 - .3, 1.6, 0), (.6, 3.2, 56))]:
        s.collider(name, loc, size)
    s.save(Path('assets/town_island.tscn'))
    print('island: %d pieces' % s.count)


# --------------------------------------------------------------------------- houses
HOUSES = HOUSE_STYLES
LIGHTS = ['tile_light', 'tile', 'mint', 'tile', 'tile_light', 'tile', 'mint_light', 'tile_light']


def house(s, h):
    f = 1 if h['north'] else -1                 # door faces +Z when north
    fz = -FRONT_OFF if h['north'] else FRONT_OFF
    side = -1 if h['num'] % 4 == 2 else 1       # which side of the house the van pad is on
    name = 'House_%02d' % h['num']
    address = f"{h['num']} Marinara Way"
    address_meta = next(row for row in get_layout()['addresses'] if row['id'] == address)
    s.node(name, 'Node3D', '.',
           f'position = Vector3({h["x"]:.5f}, 0.00000, {fz:.5f})\n'
           f'metadata/address = "{address}"\n'
           f'metadata/address_id = "{address}"\n'
           f'metadata/district_id = "downtown"\n'
           f'metadata/lot_id = "lot:marinara:{h["num"]:02d}"\n'
           f'metadata/label = "{h["label"]}"\n'
           f'metadata/number = {h["num"]}\n'
           f'metadata/north = {str(h["north"]).lower()}\n')
    P = name
    W, D = HOUSE_W, HOUSE_D
    cz = -f * D / 2

    # shell ------------------------------------------------------------------
    s.box('Foundation', (0, .17, cz), (W + .2, .34, D + .2), h['plinth'], parent=P)
    s.box('Wall', (0, 1.73, cz), (W, 2.86, D), h['wall'], parent=P)
    s.box('Eave', (0, 3.26, cz), (W + .5, .2, D + .5), h['trim'], parent=P)
    if h['style'] == 'gable':
        for r in range(7):
            z = cz + (r - 3) * 1.06
            yy = 3.36 + (3 - abs(r - 3)) * .22
            c = 'tile_light' if (r + h['num']) % 4 == 0 else h['roof']
            s.box('Roof_row', (0, yy, z), (W + .5, .2, 1.06), c, parent=P)
        s.box('Ridge', (0, 4.03, cz), (W + .55, .16, .34), LIGHTS[HOUSES.index(h)], parent=P)
    elif h['style'] == 'hip':
        for i, (sx, sz, yy) in enumerate([(W + .5, D + .5, 3.36), (W - 1.2, D - 1.2, 3.62),
                                          (W - 2.8, D - 2.8, 3.88), (W - 4.4, D - 4.4, 4.14)]):
            s.box('Hip_slab', (0, yy, cz), (sx, .22, sz), h['roof'] if i % 2 else LIGHTS[HOUSES.index(h)],
                  parent=P)
        s.box('Hip_cap', (0, 4.4, cz), (1.8, .2, 1.2), h['roof'], parent=P)
    else:  # flat roof with parapet and a little tank
        s.box('Flat_slab', (0, 3.24, cz), (W, .16, D), 'paving', parent=P)
        for dx, dz, sx, sz in [(0, D / 2 + .15, W + .5, .3), (0, -D / 2 - .15, W + .5, .3),
                               (W / 2 + .15, 0, .3, D + .5), (-W / 2 - .15, 0, .3, D + .5)]:
            s.box('Parapet', (dx, 3.5, cz + dz), (sx, .4, sz), h['trim'], parent=P)
        s.cyl('Roof_tank', (0.4 * W / 2 - 1.0, 3.9, cz + 1.4), .5, .8, 'teal', n=10, parent=P)
    if h['chimney']:
        s.box('Chimney', (1.9, 3.9, cz - 1.7 * f), (.6, 1.6, .65), 'cream', parent=P)
        s.box('Chimney_cap', (1.9, 4.78, cz - 1.7 * f), (.8, .16, .85), 'red_dark', parent=P)

    # front door, step, path -------------------------------------------------
    s.box('Door_frame', (0, 1.2, f * .07), (1.34, 2.32, .16), 'teal', parent=P)
    s.box('Door', (0, 1.18, f * .16), (1.12, 2.12, .1), h['door'], parent=P)
    s.box('Door_kick', (0, .42, f * .22), (.96, .3, .03), h['trim'], parent=P)
    s.box('Door_handle', (.36, 1.16, f * .24), (.09, .26, .09), 'gold', parent=P)
    s.box('Door_step', (0, .1, f * .62), (1.7, .2, 1.1), 'paving_light', parent=P)
    z0, z1 = sorted((f * .95, f * 3.4))
    for i in range(4):
        zz = z0 + i * .61
        s.plate('Path_slab', -.75, .75, zz, zz + .56, 'paving_light', WALK_TOP - .004,
                thick=.05, parent=P)
    s.text('Number', str(h['num']), (.95, 2.36, f * .12), .21, 'red_dark',
           rot=None if f > 0 else (0, 180, 0), parent=P)
    s.box('Number_plaque', (.95, 2.36, f * .08), (.62, .38, .06), 'ivory', parent=P)
    s.box('Lamp_mount', (-1.15, 1.95, f * .09), (.16, .26, .12), 'teal', parent=P)
    s.box('Porch_lamp', (-1.15, 1.95, f * .19), (.2, .22, .2), 'gold', parent=P)
    s.box('Lamp_hood', (-1.15, 2.09, f * .19), (.26, .08, .26), 'teal', parent=P)
    if h['porch']:
        s.box('Porch_roof', (0, 2.62, f * .82), (3.1, .14, 1.6), h['trim'], parent=P)
        for dx in (-1.4, 1.4):
            s.box('Porch_post', (dx, 1.3, f * 1.5), (.16, 2.6, .16), 'teal', parent=P)

    # windows ---------------------------------------------------------------
    for dx in (-2.35, 2.35):
        s.box('Win_recess', (dx, 1.68, f * .07), (1.56, 1.56, .14), 'teal', parent=P)
        s.box('Win_glass', (dx, 1.68, f * .15), (1.32, 1.32, .06), 'glass', parent=P)
        s.box('Win_mullion', (dx, 1.68, f * .2), (.08, 1.4, .06), 'ivory', parent=P)
        s.box('Win_crossbar', (dx, 1.68, f * .2), (1.38, .08, .06), 'ivory', parent=P)
        s.box('Win_glint', (dx - .34, 1.92, f * .21), (.14, .58, .02), 'glass_light', parent=P)
        s.box('Win_sill', (dx, .92, f * .2), (1.72, .14, .34), 'ivory', parent=P)
    for dx in (-3.76, 3.76):
        s.box('Side_win_frame', (dx, 1.72, cz), (.12, 1.44, 1.64), 'teal', parent=P)
        s.box('Side_win_glass', (dx + .05 * (1 if dx > 0 else -1), 1.72, cz), (.05, 1.2, 1.4),
              'glass', parent=P)
        s.box('Side_sill', (dx + .12 * (1 if dx > 0 else -1), 1.0, cz), (.24, .13, 1.8), 'ivory', parent=P)
    s.box('Flower_box_l', (2.35, 1.02, f * .36), (1.6, .3, .34), 'red_dark', parent=P)
    for i in range(5):
        s.box('Planted', (2.35 - .6 + i * .3, 1.24 + (i % 2) * .06, f * .38), (.22, .24, .26),
              'leaf_light' if i % 2 else 'leaf', parent=P)
        if i % 2 == 0:
            s.box('Bloom', (2.35 - .6 + i * .3, 1.4, f * .4), (.13, .12, .13),
                  'flower' if i % 4 else 'white', parent=P)

    # yard: parking pad, mailbox, hedges, garden -----------------------------
    px = side * 2.75
    zz0, zz1 = sorted((f * .45, f * 3.45))
    s.plate('Park_pad', px - 1.85, px + 1.85, zz0, zz1, 'road', WALK_TOP - .006, parent=P)
    s.plate('Pad_line', px - 1.8, px - 1.7, zz0 + .15, zz1 - .15, 'ivory', WALK_TOP + .004,
            thick=.02, parent=P)
    s.plate('Pad_line', px + 1.7, px + 1.8, zz0 + .15, zz1 - .15, 'ivory', WALK_TOP + .004,
            thick=.02, parent=P)
    mailbox(s, -side * 3.3, f * 2.6, facing=f, parent=P)
    bush(s, -side * 1.5, f * 3.9, parent=P)
    for i in range(5):
        s.box('Bed_flower', (-side * 4.0 + i * .35 * (1 if side < 0 else -1), .3, f * 1.0),
              (.28, .32, .3), 'leaf_light' if i % 2 else 'leaf', parent=P)
        if i % 2 == 0:
            s.box('Bed_bloom', (-side * 4.0 + i * .35 * (1 if side < 0 else -1), .5, f * 1.0),
                  (.14, .14, .14), 'flower', parent=P)
    for sx in (-1, 1):
        for k in range(3):
            zz = -f * (5.0 + k * 3.1)
            hedge(s, sx * 4.15, sx * 4.62, zz, zz - f * 2.6, parent=P, h=.62)
    if h['fence']:
        fx = -4.4
        for i in range(13):
            x = fx + i * .73
            s.box('Fence_picket', (x, .61, -f * 14.6), (.15, 1.14, .17), 'ivory', parent=P)
            s.box('Picket_cap', (x, 1.2, -f * 14.6), (.2, .1, .21), 'cream', parent=P)
        for y in (.42, .86):
            s.box('Fence_rail', (0, y, -f * 14.68), (8.9, .13, .12), 'cream', parent=P)
        s.collider('Fence_barrier', (0, .58, -f * 14.62), (9.0, 1.16, .22), parent=P)
    tree(s, side * 2.9, -f * 11.0, 2.9, parent=P)
    if h['garden']:
        z0, z1 = sorted((-f * 8.4, -f * 11.8))
        s.plate('Veg_bed', -4.2, -1.6, z0, z1, 'soil', .12, thick=.14, parent=P)
        for r in range(4):
            for c in range(4):
                s.box('Crop', (-3.9 + c * .7, .28, z0 + .45 + r * .85), (.42, .26, .42),
                      'leaf_light' if (r + c) % 2 else 'leaf', parent=P)

    # collision + navigation markers ----------------------------------------
    s.collider('House_body', (0, 1.65, cz), (W + .3, 3.3, D + .3), parent=P)
    s.marker('Door', (0, 0, f * 1.0), parent=P,
             meta={'kind': 'door', 'world_id': address_meta['ped_door_id'], 'address_id': address})
    s.marker('Park', (px, 0, f * 2.0), parent=P,
             meta={'kind': 'park', 'world_id': address_meta['parking_id'],
                   'address_id': address, 'yaw': (90.0 if side > 0 else -90.0)})
    if f > 0:
        clear(h['x'] - 4.8, h['x'] + 4.8, fz - 15.6, fz + .4)
    else:
        clear(h['x'] - 4.8, h['x'] + 4.8, fz - .4, fz + 15.6)


def houses():
    s = Scene('TownHouses', with_font=True)
    for h in HOUSES:
        house(s, h)
    s.save(Path('assets/town_houses.tscn'))
    print('houses: %d pieces' % s.count)


# --------------------------------------------------------------------------- props
def bus_stop(s, x, z):
    for dx in (-1.35, 1.35):
        s.box('Shelter_post', (x + dx, 1.25, z), (.14, 2.5, .14), 'teal')
    s.box('Shelter_roof', (x, 2.56, z - .1), (3.3, .15, 1.5), 'ivory')
    s.box('Shelter_fascia', (x, 2.44, z + .6), (3.3, .26, .1), 'red')
    s.box('Shelter_glass', (x, 1.35, z - .62), (3.0, 1.9, .06), 'glass')
    s.box('Shelter_glass_trim', (x, 2.28, z - .62), (3.1, .12, .1), 'teal')
    bench(s, x, z + .1, 'x')
    s.box('Stop_sign_post', (x + 1.9, 1.3, z + .4), (.12, 2.6, .12), 'teal')
    s.box('Stop_sign', (x + 1.9, 2.5, z + .4), (.7, .5, .08), 'ivory')
    s.text('Stop_text', 'BUS', (x + 1.9, 2.5, z + .46), .22, 'red_dark')


def park_props(s):
    bench(s, -3.2, -19.0, 'x')
    bench(s, 0.0, -10.3, 'x')
    for x, z in [(-6.6, -9.6), (6.6, -9.6), (-6.6, -20.4), (6.6, -20.4)]:
        lamppost(s, x, z)
    for x, z, hh in [(-6.6, -14.6, 3.0), (6.6, -14.6, 2.8), (-6.6, -22.8, 3.0),
                     (6.6, -22.8, 3.1), (-1.8, -23.6, 2.6), (4.4, -8.6, 2.5)]:
        tree(s, x, z, hh)
    for x, z in [(-7.4, -6.4), (7.4, -6.4), (-7.4, -24.4), (7.4, -24.4)]:
        bush(s, x, z)
    for x, z in [(-5.2, -7.6), (5.2, -7.6), (-5.6, -19.2), (5.8, -11.0), (2.0, -24.6)]:
        flower_clump(s, x, z)
    s.box('Picnic_top', (3.0, .78, -18.6), (1.5, .12, 2.0), 'crust')
    for dx in (-.6, .6):
        s.box('Picnic_bench', (3.0 + dx, .5, -18.6), (.34, .1, 2.0), 'crust')
        for dz in (-.8, .8):
            s.box('Picnic_leg', (3.0 + dx, .25, -18.6 + dz), (.12, .5, .12), 'teal')


def plaza_props(s):
    for x, z in [(-6.6, 6.1), (-5.7, 7.4), (6.6, 6.1)]:
        cone(s, x, z)
    for x in (-7.6, 7.6):
        s.box('Planter', (x, .38, 6.4), (1.1, .56, 1.1), 'red_dark')
        for i in range(3):
            s.box('Planter_leaf', (x - .3 + i * .3, .78, 6.4 + (i % 2) * .12),
                  (.34, .4, .34), 'leaf_light' if i % 2 else 'leaf')
        s.box('Planter_bloom', (x, .98, 6.32), (.16, .16, .16), 'flower')
    for x, z in [(7.4, 5.9), (-7.4, 5.9)]:
        bin(s, x, z)
    # service yard behind the shop
    s.box('Dumpster', (5.4, .55, 15.6), (1.7, 1.1, 1.1), 'teal')
    s.box('Dumpster_lid', (5.4, 1.16, 15.6), (1.78, .12, 1.18), 'ink')
    s.box('Dumpster_skirt', (5.4, .12, 15.6), (1.8, .24, 1.2), 'ink')
    for i in range(3):
        s.box('Crate', (-4.6 + i * .78, .33, 14.6 + (i % 2) * .5), (.72, .66, .72), 'crust')
    for i in range(4):
        s.box('Spare_box', (-2.0, .28 + i * .15, 16.4), (.66, .13, .66),
              'cream' if i % 2 else 'ivory')
    for x, z in [(-6.8, 16.9), (6.9, 17.4)]:
        bin(s, x, z)


def verdict_bench(s, x, z):  # small bench outside the shop door
    bench(s, x, z, 'x')


def lampposts(s):
    for x in (-25.0, -13.0, 7.0, 13.0, 25.0):
        lamppost(s, x, MAIN_Z1 + 1.3)
    for x in (-19.0, -3.0, 3.0, 19.0, 27.0):
        lamppost(s, x, MAIN_Z0 - 1.3)


def road_sign(s, x, z, txt, size=.21):
    s.box('Sign_post', (x, 1.4, z), (.13, 2.8, .13), 'teal')
    s.box('Sign_board', (x, 2.42, z), (2.05, .5, .09), 'ivory')
    s.box('Sign_edge', (x, 2.42, z - .03), (2.15, .58, .05), 'red_dark')
    s.text('Sign_text', txt, (x, 2.42, z + .06), size, 'red_dark')


def props():
    s = Scene('TownProps', with_font=True)
    lampposts(s)
    park_props(s)
    plaza_props(s)
    for x, z in [(-19.2, 5.7), (-9.0, -5.7), (9.0, 5.7), (19.2, -5.7)]:
        hydrant(s, x, z)
    bus_stop(s, 20.5, -4.2)
    road_sign(s, -22.6, -4.6, "PIP'S PIZZA  >", .2)
    verdict_bench(s, -4.2, -4.4)
    verdict_bench(s, 4.4, 20.0)
    for x, z, hh in [(-31.6, -24.6, 3.0), (31.6, -24.6, 3.2), (-31.6, 24.6, 2.8),
                     (31.6, 24.6, 3.0), (-25.6, 21.0, 2.9), (25.6, 21.0, 3.1),
                     (-22.4, -25.0, 2.7), (22.4, -25.2, 3.0), (-19.8, -12.4, 2.9),
                     (19.8, 12.4, 2.8), (-19.8, 12.4, 3.0), (19.8, -12.4, 2.7)]:
        tree(s, x, z, hh)
    for x, z in [(-33.0, -14.0), (-33.0, 8.0), (33.0, -8.0), (33.0, 16.0), (-9.6, 24.0),
                 (9.6, 24.0), (-28.0, 4.6), (28.0, -4.6)]:
        bush(s, x, z)
    for x, z in [(-30.0, 6.0), (-26.0, -6.0), (26.0, 6.0), (30.0, -6.0), (-2.6, 24.4),
                 (2.6, 24.4), (-8.6, -24.0), (8.6, -24.0)]:
        flower_clump(s, x, z)
    s.save(Path('assets/town_props.tscn'))
    print('props: %d pieces' % s.count)


# --------------------------------------------------------------------------- assembly
def town_scene():
    ext = ''
    for i, f in enumerate(['town_island', 'town_houses', 'town_props', 'pizza_shop',
                           'street_details'], 1):
        ext += f'[ext_resource type="PackedScene" path="res://assets/{f}.tscn" id="{i}"]\n'
    nodes = '''[node name="Town" type="Node3D"]

[node name="Island" parent="." instance=ExtResource("1")]

[node name="Houses" parent="." instance=ExtResource("2")]

[node name="Props" parent="." instance=ExtResource("3")]

[node name="PizzaShop" parent="." instance=ExtResource("4")]
position = Vector3(0, 0.08, 11)
rotation = Vector3(0, 3.14159, 0)

[node name="PickupPoint" type="Node3D" parent="PizzaShop"]
position = Vector3(0, 0, -0.05)
metadata/world_id = "poi:pizza_pickup"

[node name="StreetDetails" parent="." instance=ExtResource("5")]
position = Vector3(5.5, 0, -21)

[node name="VanSpawn" type="Node3D" parent="."]
position = Vector3(0, 0.2, 1.85)
metadata/yaw = 90.0
metadata/world_id = "spawn:van"

[node name="PlayerSpawn" type="Node3D" parent="."]
position = Vector3(3.4, 0.15, 6.4)
metadata/yaw = -35.0
metadata/world_id = "spawn:player"

[node name="WorldMarkers" type="Node3D" parent="."]

[node name="PizzaPlaza" type="Node3D" parent="WorldMarkers"]
position = Vector3(0, 0.1, 11)
metadata/world_id = "poi:pizza_plaza"

[node name="ShopFrontApproach" type="Node3D" parent="WorldMarkers"]
position = Vector3(0, 0.1, 7)
metadata/world_id = "poi:shop_front_approach"

[node name="CentralPark" type="Node3D" parent="WorldMarkers"]
position = Vector3(0, 0.1, -14.4)
metadata/world_id = "poi:central_park"

[node name="VehicleService" type="Node3D" parent="WorldMarkers"]
position = Vector3(0, 0.1, 16)
metadata/world_id = "poi:vehicle_service"
'''
    out = '[gd_scene load_steps=6 format=3]\n\n' + ext + '\n' + nodes
    target = OUTPUT_ROOT / 'scenes/town.tscn'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(out, encoding='utf-8')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Build deterministic generated town scenes.')
    parser.add_argument('--output', type=Path, default=OUTPUT_ROOT,
                        help='output root; supports isolated staging builds')
    args = parser.parse_args()
    import townkit
    OUTPUT_ROOT = args.output.resolve()
    townkit.OUTPUT_ROOT = OUTPUT_ROOT
    island()
    houses()
    props()
    town_scene()
    write_layout(args.output.resolve() / 'data/world/world_layout.json')
    print(f'Built the delivery town: island, {len(get_layout()["addresses"])} addresses, props, layout and town scene.')
