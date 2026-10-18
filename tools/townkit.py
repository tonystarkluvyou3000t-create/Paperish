"""Shared authoring kit for the Pip the Pizza Boy town art.

Same conventions as tools/build_art.py: flat box/cylinder geometry, shared flat
materials taken from one palette, named pieces, hand-editable .tscn output.
"""
from pathlib import Path
import math, random
import os
from world_data import (BOUNDS, GROUND_TOP, MAIN_Z0, MAIN_Z1, MAIN_X0, MAIN_X1,
                        BASIL_X0, BASIL_X1, OLIVE_X0, OLIVE_X1, VROAD_Z,
                        SIDEWALK_WIDTH, SHOP_Z, FRONT_OFF, HOUSE_W, HOUSE_D,
                        ROAD_TOP, WALK_TOP, MARK_TOP, RIM_TOP)

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = Path(os.environ.get("PIP_TOWN_OUTPUT", str(ROOT))).resolve()

PALETTE = {
 'cream':'F8E5BC', 'ivory':'FFF3D7', 'red':'C84436', 'red_light':'ED6248',
 'red_dark':'8C302E', 'tile':'D65F46', 'tile_light':'EC8060', 'mint':'68B7A0',
 'mint_light':'9AD2B7', 'teal':'326B69', 'glass':'79BAC2', 'glass_light':'C8E9DC',
 'ink':'283F49', 'rubber':'344048', 'metal':'B3C6BC', 'gold':'F4BB4D',
 'cheese':'FFDC75', 'crust':'D99345', 'skin':'E6AE7D', 'skin_light':'F7C99B',
 'hair':'623D32', 'soil':'A66D4E', 'soil_light':'C18B5D', 'grass':'88AE65',
 'grass_light':'A5C47B', 'grass_dark':'709653', 'leaf':'5A9560', 'leaf_light':'88B775',
 'bark':'82553E', 'paving':'DBCCAA', 'paving_light':'E9DCBF', 'road':'788987',
 'road_light':'899894', 'white':'FFF8E5', 'pink':'E99080', 'flower':'E8BB60'
}

# ---------------------------------------------------------------- layout numbers
IS_X0, IS_X1 = BOUNDS["min_x"], BOUNDS["max_x"]
IS_Z0, IS_Z1 = BOUNDS["min_z"], BOUNDS["max_z"]
GRASS_TOP = 0.05
SW = SIDEWALK_WIDTH


def v(vals): return ', '.join(f'{x:.5f}' for x in vals)
def color(h): return ', '.join(f'{int(h[i:i+2],16)/255:.5f}' for i in (0,2,4))


class Scene:
    """Tiny .tscn writer: dedupes materials and meshes exactly like build_art.py."""
    def __init__(self, name, with_font=False):
        self.name = name
        self.res = []
        if with_font:
            self.res.append('[sub_resource type="SystemFont" id="SignFont"]\n'
                            'font_names = PackedStringArray("sans-serif")\nfont_weight = 800\n')
        self.nodes = []
        self.count = 0
        self.mats = {}
        self.meshes = {}
        self.node(name, 'Node3D', None)

    def node(self, name, typ, parent='.', props=''):
        p = f'[node name="{name}" type="{typ}"' + (f' parent="{parent}"' if parent is not None else '') + ']\n' + props
        self.nodes.append(p)

    def mat(self, c):
        if c not in self.mats:
            ident = 'Mat_' + c
            self.mats[c] = ident
            self.res.append(f'[sub_resource type="StandardMaterial3D" id="{ident}"]\n'
                            f'albedo_color = Color({color(PALETTE[c])}, 1)\nroughness = 0.85\n')
        return self.mats[c]

    def mesh(self, typ, size, c):
        key = (typ, tuple(size), c)
        if key not in self.meshes:
            ident = f'Mesh_{len(self.meshes)}'
            self.meshes[key] = ident
            props = f'material = SubResource("{self.mat(c)}")\n'
            if typ == 'BoxMesh':
                props += f'size = Vector3({v(size)})\n'
            elif typ == 'CylinderMesh':
                props += (f'top_radius = {size[0]}\nbottom_radius = {size[0]}\n'
                          f'height = {size[1]}\nradial_segments = {int(size[2])}\nrings = 1\n')
            self.res.append(f'[sub_resource type="{typ}" id="{ident}"]\n' + props)
        return self.meshes[key]

    def part(self, name, loc, size, c, parent='.', rot=None, typ='BoxMesh'):
        self.count += 1
        n = f'{name}_{self.count:03}'
        props = f'position = Vector3({v(loc)})\n'
        if rot:
            props += f'rotation = Vector3({v([math.radians(x) for x in rot])})\n'
        props += f'mesh = SubResource("{self.mesh(typ, size, c)}")\n'
        self.node(n, 'MeshInstance3D', parent, props)
        return n

    def box(self, *a, **kw): return self.part(*a, **kw)

    def cyl(self, name, loc, r, h, c, rot=None, n=12, parent='.'):
        return self.part(name, loc, (r, h, n), c, parent, rot, 'CylinderMesh')

    def plate(self, name, x0, x1, z0, z1, c, top, thick=0.06, parent='.'):
        """Axis-aligned slab given by its plan rect and top height."""
        x0, x1 = min(x0, x1), max(x0, x1)
        z0, z1 = min(z0, z1), max(z0, z1)
        return self.box(name, ((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2),
                        (x1 - x0, thick, z1 - z0), c, parent=parent)

    def rect_mark(self, name, x0, x1, z0, z1, c, top, thick=0.012, parent='.'):
        return self.plate(name, x0, x1, z0, z1, c, top, thick, parent)

    def text(self, name, txt, loc, size, c, rot=None, parent='.'):
        ident = 'Text_' + str(self.count)
        self.count += 1
        self.res.append(f'[sub_resource type="TextMesh" id="{ident}"]\n'
                        f'material = SubResource("{self.mat(c)}")\nfont = SubResource("SignFont")\n'
                        f'text = "{txt}"\nfont_size = 64\npixel_size = {size/64}\ndepth = 0.008\n')
        props = f'position = Vector3({v(loc)})\nmesh = SubResource("{ident}")\n'
        if rot:
            props += f'rotation = Vector3({v([math.radians(x) for x in rot])})\n'
        self.node(name, 'MeshInstance3D', parent, props)

    def collider(self, name, loc, size, parent='.'):
        ident = 'Collision_' + name
        self.res.append(f'[sub_resource type="BoxShape3D" id="{ident}"]\nsize = Vector3({v(size)})\n')
        self.node(name, 'StaticBody3D', parent, f'position = Vector3({v(loc)})\n')
        shape_parent = name if parent == '.' else parent + '/' + name
        self.node('Shape', 'CollisionShape3D', shape_parent, f'shape = SubResource("{ident}")\n')

    def marker(self, name, loc, parent='.', meta=None):
        props = f'position = Vector3({v(loc)})\n'
        for k, val in (meta or {}).items():
            if isinstance(val, bool):
                encoded = str(val).lower()
            elif isinstance(val, (int, float)):
                encoded = str(val)
            else:
                encoded = '"' + str(val).replace('"', '\\"') + '"'
            props += f'metadata/{k} = {encoded}\n'
        self.node(name, 'Node3D', parent, props)

    def save(self, file):
        out = '[gd_scene load_steps=' + str(len(self.res) + 1) + ' format=3]\n\n'
        out += '\n'.join(self.res) + '\n' + '\n'.join(self.nodes)
        target = OUTPUT_ROOT / file
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(out, encoding='utf-8')


# ------------------------------------------------------------- reusable set pieces
def tree(s, x, z, h=3.0, parent='.'):
    """Blocky voxel tree, same silhouette as the original land tile."""
    s.box('Tree_trunk', (x, h * .43, z), (.34, h * .86, .37), 'bark', parent=parent)
    s.box('Branch', (x + .25, h * .71, z), (.65, .19, .2), 'bark', parent=parent)
    for dx, dy, dz, dim, c in [(-.4, 0, 0, 1.1, 'leaf'), (.42, .13, .12, 1.1, 'leaf_light'),
                               (0, .64, -.12, 1.14, 'leaf_light'), (0, .1, -.5, 1.15, 'leaf'),
                               (.05, .12, .53, 1, 'leaf_light')]:
        s.box('Voxel_canopy', (x + dx, h + dy, z + dz), (dim, dim * .85, dim), c, parent=parent)


def bush(s, x, z, parent='.', n=3):
    for j in range(n):
        s.box('Shrub', (x + j * .25, .28 + j % 2 * .12, z), (.5, .52, .55),
              'leaf_light' if j % 2 else 'leaf', parent=parent)


def flower_clump(s, x, z, parent='.', n=3):
    for j in range(n):
        xx = x + j * .16
        s.box('Flower_stem', (xx, .2, z), (.045, .3, .045), 'leaf', parent=parent)
        s.box('Wildflower', (xx, .37 + (j % 2) * .05, z), (.13, .1, .13),
              'white' if j % 2 else 'flower', parent=parent)


def lamppost(s, x, z, parent='.'):
    s.box('Lamp_base', (x, .14, z), (.34, .24, .34), 'paving', parent=parent)
    s.box('Lamp_post', (x, 1.9, z), (.15, 3.6, .15), 'teal', parent=parent)
    s.box('Lamp_neck', (x, 3.66, z), (.22, .16, .22), 'teal', parent=parent)
    s.box('Lamp_glass', (x, 3.86, z), (.36, .34, .36), 'gold', parent=parent)
    s.box('Lamp_cap', (x, 4.08, z), (.46, .14, .46), 'teal', parent=parent)


def bench(s, x, z, axis='x', parent='.'):
    ln, dp = (1.8, .52) if axis == 'x' else (.52, 1.8)
    s.box('Bench_seat', (x, .55, z), (ln, .13, dp), 'crust', parent=parent)
    bo = -0.21 if axis == 'x' else 0.0
    bz = bo if axis == 'x' else (-.21 if axis == 'z' else 0)
    if axis == 'x':
        s.box('Bench_back', (x, .92, z - .24), (ln, .42, .12), 'crust', parent=parent)
        for dx in (-.72, .72):
            s.box('Bench_leg', (x + dx, .3, z), (.14, .5, .44), 'teal', parent=parent)
    else:
        s.box('Bench_back', (x - .24, .92, z), (.12, .42, ln), 'crust', parent=parent)
        for dz in (-.72, .72):
            s.box('Bench_leg', (x, .3, z + dz), (.44, .5, .14), 'teal', parent=parent)


def hydrant(s, x, z, parent='.'):
    s.cyl('Hydrant_body', (x, .34, z), .16, .58, 'red', n=8, parent=parent)
    s.cyl('Hydrant_cap', (x, .68, z), .13, .12, 'red_dark', n=8, parent=parent)
    s.box('Hydrant_arm', (x, .44, z), (.44, .12, .12), 'red_dark', parent=parent)


def cone(s, x, z, parent='.'):
    s.box('Cone_base', (x, .03, z), (.5, .06, .5), 'red', parent=parent)
    s.cyl('Cone_body', (x, .3, z), .17, .55, 'red_light', n=8, parent=parent)
    s.box('Cone_band', (x, .32, z), (.3, .09, .3), 'ivory', parent=parent)


def bin(s, x, z, parent='.'):
    s.cyl('Bin_body', (x, .45, z), .33, .9, 'teal', n=8, parent=parent)
    s.cyl('Bin_rim', (x, .93, z), .36, .1, 'ink', n=8, parent=parent)
    s.box('Bin_lid', (x, .99, z), (.72, .08, .72), 'ink', parent=parent)


def mailbox(s, x, z, facing=1, parent='.'):
    s.box('Mail_post', (x, .58, z), (.11, 1.16, .11), 'teal', parent=parent)
    s.box('Mail_box', (x, 1.3, z), (.36, .3, .56), 'ivory', parent=parent)
    s.box('Mail_roof', (x, 1.47, z), (.42, .07, .62), 'red', parent=parent)
    s.box('Mail_flag', (x + .2 * facing, 1.42, z), (.06, .22, .1), 'red', parent=parent)


def hedge(s, x0, x1, z0, z1, parent='.', h=.6):
    s.plate('Hedge', x0, x1, z0, z1, 'leaf', h, thick=h, parent=parent)
    s.plate('Hedge_top', x0 + .07, x1 - .07, z0 + .07, z1 - .07, 'leaf_light', h + .07,
            thick=.08, parent=parent)
