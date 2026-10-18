"""Build original, editable Godot geometry. Run from any working directory."""
from pathlib import Path
import math, random
import argparse

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = ROOT
random.seed(17)
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

def v(vals): return ', '.join(f'{x:.5f}' for x in vals)
def color(h): return ', '.join(f'{int(h[i:i+2],16)/255:.5f}' for i in (0,2,4))

class Scene:
 def __init__(self,name):
  self.name=name; self.res=['[sub_resource type="SystemFont" id="SignFont"]\nfont_names = PackedStringArray("sans-serif")\nfont_weight = 800\n']; self.nodes=[]; self.count=0; self.mats={}; self.meshes={}
  self.node(name,'Node3D',None)
 def node(self,name,typ,parent='.',props=''):
  self.nodes.append(f'[node name="{name}" type="{typ}"'+(f' parent="{parent}"' if parent is not None else '')+']\n'+props)
 def mat(self,c):
  if c not in self.mats:
   ident='Mat_'+c; self.mats[c]=ident
   self.res.append(f'[sub_resource type="StandardMaterial3D" id="{ident}"]\nalbedo_color = Color({color(PALETTE[c])}, 1)\nroughness = 0.85\n')
  return self.mats[c]
 def mesh(self,typ,size,c):
  key=(typ,tuple(size),c)
  if key not in self.meshes:
   ident=f'Mesh_{len(self.meshes)}';self.meshes[key]=ident
   props=f'material = SubResource("{self.mat(c)}")\n'
   if typ=='BoxMesh': props+=f'size = Vector3({v(size)})\n'
   else: props+=f'top_radius = {size[0]}\nbottom_radius = {size[0]}\nheight = {size[1]}\nradial_segments = {int(size[2])}\nrings = 1\n'
   self.res.append(f'[sub_resource type="{typ}" id="{ident}"]\n'+props)
  return self.meshes[key]
 def part(self,name,loc,size,c,parent='.',rot=None,typ='BoxMesh'):
  self.count+=1; name=f'{name}_{self.count:03}'
  props=f'position = Vector3({v(loc)})\n'
  if rot: props+=f'rotation = Vector3({v([math.radians(x) for x in rot])})\n'
  props+=f'mesh = SubResource("{self.mesh(typ,size,c)}")\n'
  self.node(name,'MeshInstance3D',parent,props)
  return name
 def box(self,*a,**kw):return self.part(*a,**kw)
 def cyl(self,name,loc,r,h,c,rot=None,n=12,parent='.'):
  return self.part(name,loc,(r,h,n),c,parent,rot,'CylinderMesh')
 def text(self,name,txt,loc,size,c,rot=None):
  ident='Text_'+str(self.count); self.count+=1
  self.res.append(f'[sub_resource type="TextMesh" id="{ident}"]\nmaterial = SubResource("{self.mat(c)}")\nfont = SubResource("SignFont")\ntext = "{txt}"\nfont_size = 64\npixel_size = {size/64}\ndepth = 0.008\n')
  props=f'position = Vector3({v(loc)})\nmesh = SubResource("{ident}")\n'
  if rot: props+=f'rotation = Vector3({v([math.radians(x) for x in rot])})\n'
  self.node(name,'MeshInstance3D','.',props)
 def collider(self,name,loc,size):
  ident='Collision_'+name
  self.res.append(f'[sub_resource type="BoxShape3D" id="{ident}"]\nsize = Vector3({v(size)})\n')
  self.node(name,'StaticBody3D','.',f'position = Vector3({v(loc)})\n')
  self.node('Shape','CollisionShape3D',name,f'shape = SubResource("{ident}")\n')
 def save(self,file):
  target=OUTPUT_ROOT/file; target.parent.mkdir(parents=True,exist_ok=True)
  target.write_text('[gd_scene load_steps='+str(len(self.res)+1)+' format=3]\n\n'+'\n'.join(self.res)+'\n'+'\n'.join(self.nodes),encoding='utf-8')

def pizza(s,loc,r,axis='z'):
 x,y,z=loc; rot=(90,0,0) if axis=='z' else (0,0,90)
 s.cyl('Golden_crust',(x,y,z),r,.12,'crust',rot)
 offset=.071
 s.cyl('Tomato_sauce',(x+(offset if axis=='x' else 0),y,z+(offset if axis=='z' else 0)),r*.85,.025,'red',rot)
 s.cyl('Mozzarella',(x+(.09 if axis=='x' else 0),y,z+(.09 if axis=='z' else 0)),r*.77,.025,'cheese',rot)
 for a,b in [(-.32,.27),(.3,.32),(0,-.28),(-.4,-.2),(.38,-.25)]:
  s.cyl('Pepperoni',(x+(.11 if axis=='x' else a*r),y+b*r,z+(a*r if axis=='x' else .11)),r*.145,.022,'red_dark',rot,n=8)
 for a,b in [(-.1,.5),(.15,.07),(-.38,-.45)]:
  s.box('Basil',(x+(.13 if axis=='x' else a*r),y+b*r,z+(a*r if axis=='x' else .13)),(.035,r*.18,r*.12) if axis=='x' else (r*.12,r*.18,.035),'leaf',rot=(0,0,25))

def shop():
 s=Scene('PizzaShop')
 s.box('Foundation',(0,.12,0),(6.2,.24,4.5),'teal')
 # A real shell: split the front around the entrance so both Pip and the
 # camera can pass through. These are visual wall pieces; matching colliders
 # are authored below rather than one solid box across the building.
 s.box('Front_wall_left',(-1.8,1.72,2.02),(2.4,3.2,.16),'cream')
 s.box('Front_wall_right',(1.8,1.72,2.02),(2.4,3.2,.16),'cream')
 s.box('Front_wall_lintel',(0,2.94,2.02),(1.2,.76,.16),'cream')
 s.box('Back_wall',(0,1.72,-2.02),(6,3.2,.16),'cream')
 for side in [-1,1]:
  s.box('Side_wall',(side*2.92,1.72,0),(.16,3.2,4.2),'cream')
 s.box('Lower_plinth',(0,.45,.02),(6.08,.45,4.25),'red_dark')
 # Warm interior with enough clear floor for a capsule turn from the door.
 s.box('Shop_floor',(0,.205,0),(5.65,.07,3.84),'paving_light')
 # Stepped terracotta roof, deliberately block built.
 s.box('Eave',(0,3.3,0),(6.6,.22,4.7),'red_dark')
 for row in range(7):
  z=-2.22+row*.65
  for col in range(12):
   x=-2.98+col*.54
   height=3.46+(3-abs(row-3))*.16
   s.box('Terracotta_roof_tile',(x,height,z),(.53,.2,.69),'tile_light' if (row+col)%4==0 else 'tile')
 s.box('Ridge',(0,4.02,-.27),(6.65,.18,.26),'tile_light')
 s.box('Chimney',(2.15,4.25,-1.15),(.54,1,.6),'cream')
 s.box('Chimney_cap',(2.15,4.78,-1.15),(.74,.16,.8),'red_dark')
 # Front windows, frames and reflections.
 for x in [-1.88,1.88]:
  s.box('Window_recess',(x,1.65,2.13),(1.65,1.67,.1),'teal')
  s.box('Opaque_glass',(x,1.68,2.2),(1.42,1.4,.08),'glass')
  s.box('Window_mullion',(x,1.68,2.26),(.08,1.5,.07),'ivory')
  s.box('Window_crossbar',(x,1.56,2.26),(1.5,.07,.07),'ivory')
  s.box('Glass_glint',(x-.43,1.92,2.255),(.16,.68,.018),'glass_light')
  s.box('Glass_glint_small',(x-.19,2.12,2.255),(.08,.29,.018),'glass_light')
  s.box('Sill',(x,.88,2.25),(1.85,.15,.32),'ivory')
 # Three visual frame members preserve the opening through the storefront.
 s.box('Door_frame_left',(-.55,1.32,2.14),(.10,2.40,.16),'teal')
 s.box('Door_frame_right',(.55,1.32,2.14),(.10,2.40,.16),'teal')
 s.box('Door_frame_top',(0,2.48,2.14),(1.2,.16,.16),'teal')
 # No closed slab across the entrance: OPEN means Pip can walk in.
 s.box('Door_open_leaf',(-.57,1.28,1.58),(.88,2.2,.08),'mint',rot=(0,90,0))
 s.box('Door_open_glass',(-.57,1.62,1.58),(.63,1.15,.035),'glass',rot=(0,90,0))
 s.box('Door_open_handle',(-.52,1.22,1.39),(.08,.22,.08),'gold')
 s.box('Door_step',(0,.17,2.48),(1.8,.28,.65),'paving_light')
 # Keep the OPEN plaque above the walk-through, not across the doorway sightline.
 s.box('Open_plaque',(0,2.42,2.35),(.58,.25,.04),'cream')
 s.text('Open_text','OPEN',(0,2.42,2.38),.16,'red_dark')
 # Staffed service counter and a visible kitchen/oven backdrop.
 s.box('Counter_body',(0,.79,-.58),(3.35,1.06,.58),'teal')
 s.box('Counter_inset',(0,.82,-.265),(2.95,.75,.035),'cream')
 s.box('Counter_top',(0,1.37,-.58),(3.58,.13,.78),'bark')
 s.box('Counter_front_trim',(0,1.13,-.275),(3.26,.10,.07),'gold')
 s.box('Counter_shelf',(0,1.46,-.62),(1.05,.08,.62),'ivory')
 s.node('ReadyStock','Node3D','.', 'visible = false\n')
 for i in range(3):
  group=f'ReadyBox{i}'
  s.node(group,'Node3D','ReadyStock',f'position = Vector3(0, {1.53+i*.12:.5f}, -0.62)\n')
  parent='ReadyStock/'+group
  s.box('Ready_pizza_box',(0,0,0),(.74,.11,.52),'cream',parent=parent)
  s.box('Ready_box_lid',(0,.058,0),(.77,.025,.55),'ivory',parent=parent)
  s.box('Ready_box_stripe',(0,.073,.283),(.44,.04,.018),'red',parent=parent)
 s.box('Oven',(1.75,.99,-1.62),(1.36,1.42,.66),'red_dark')
 s.box('Oven_face',(1.75,1.08,-1.27),(1.08,.82,.07),'teal')
 s.box('Oven_mouth',(1.75,1.07,-1.225),(.82,.52,.025),'ink')
 s.box('Oven_glow',(1.75,.91,-1.205),(.56,.08,.02),'gold')
 s.box('Prep_shelf',(-1.75,1.12,-1.62),(1.36,.13,.62),'bark')
 s.box('Prep_rail',(-1.75,1.36,-1.72),(1.42,.09,.12),'teal')
 s.text('Pickup_sign','ORDER PICKUP',(0,2.42,-1.88),.22,'teal')
 s.node('Counter_light','OmniLight3D','.',
  'position = Vector3(0, 2.45, -0.45)\nlight_color = Color(1, 0.74, 0.43, 1)\nlight_energy = 1.35\nomni_range = 5.5\nshadow_enabled = false\n')
 # Stable markers used by the interaction, staff placement and legacy callers.
 s.node('CounterAccess','Node3D','.', 'position = Vector3(0, 0, -0.05)\nmetadata/world_id = "poi:counter_access"\n')
 s.node('StaffStation','Node3D','.', 'position = Vector3(0, 0, -1.42)\nmetadata/world_id = "poi:staff_station"\n')
 s.node('ShopEntrance','Node3D','.', 'position = Vector3(0, 0, 2.72)\nmetadata/world_id = "entrance:pizza_shop"\nmetadata/kind = "entrance"\n')
 # Signboard and striped individual awning slats.
 s.box('Sign_frame',(0,2.99,2.18),(5.78,.68,.18),'teal')
 s.box('Sign_panel',(0,2.99,2.29),(5.55,.49,.09),'ivory')
 s.text('Shop_name',"PIP'S PIZZA",(0,2.99,2.355),.43,'red_dark')
 for i in range(18):
  x=-2.975+i*.35; c='red' if i%2==0 else 'ivory'
  s.box('Striped_canopy',(x,2.57,2.52),(.35,.11,.97),c,rot=(12,0,0))
  s.box('Awning_valance',(x,2.37,2.99),(.35,.25,.1),c)
 for x in [-2.9,2.9]:
  s.box('Awning_bracket',(x,2.34,2.4),(.07,.08,.65),'teal')
 # Large iconic rooftop pizza medallion.
 for x in [-.52,.52]: s.box('Sign_post',(x,4.08,.34),(.13,.8,.13),'teal')
 pizza(s,(0,4.64,.41),.78)
 # Visible side facade includes a small window and service sign, no interior.
 s.box('Side_window_frame',(3.035,1.85,-.25),(.12,1.5,1.75),'teal')
 s.box('Side_window',(3.105,1.85,-.25),(.04,1.27,1.49),'glass')
 for z in [-.62,.12]: s.box('Side_mullion',(3.14,1.85,z),(.06,1.35,.07),'ivory')
 s.box('Side_sill',(3.15,1.12,-.25),(.28,.13,1.9),'ivory')
 for x in [-2.75,2.75]:
  s.box('Wall_lamp_mount',(x,2,2.23),(.18,.32,.2),'teal')
  s.box('Wall_lamp',(x,2.09,2.4),(.23,.26,.22),'gold')
  s.box('Lamp_cap',(x,2.25,2.4),(.29,.08,.28),'teal')
 # Planters sit alongside the entrance.
 for x in [-1.9,1.9]:
  s.box('Flower_box',(x,.68,2.49),(1.36,.32,.35),'red_dark')
  for i in range(7):
   xx=x-.53+i*.175
   s.box('Planter_foliage',(xx,.92+(i%2)*.07,2.5),(.24,.29,.27),'leaf_light' if i%2 else 'leaf')
   if i%2==0: s.box('Flower',(xx,1.09,2.56),(.12,.12,.1),'flower' if i%4 else 'white')
 s.collider('Front_left_collision',(-1.8,1.72,2.02),(2.4,3.2,.16))
 s.collider('Front_right_collision',(1.8,1.72,2.02),(2.4,3.2,.16))
 s.collider('Front_lintel_collision',(0,2.94,2.02),(1.2,.76,.16))
 s.collider('Back_collision',(0,1.72,-2.02),(6,3.2,.16))
 s.collider('Left_collision',(-2.92,1.72,0),(.16,3.2,4.2))
 s.collider('Right_collision',(2.92,1.72,0),(.16,3.2,4.2))
 s.collider('Counter_collision',(0,.79,-.58),(3.35,1.06,.58))
 # Ceiling trim is visual only so the camera can remain readable indoors.
 s.save(Path('assets/pizza_shop.tscn'))

def van():
 s=Scene('PizzaVan')
 s.box('Chassis',(0,.52,0),(1.83,.22,3.55),'ink')
 s.box('Body',(0,1.12,0),(1.92,1.05,3.55),'mint')
 s.box('Cargo_top',(0,1.94,-.52),(1.92,1.15,2.47),'cream')
 s.box('Roof',(0,2.56,-.48),(2.03,.15,2.65),'ivory')
 s.box('Cab_top',(0,1.92,1.13),(1.85,.8,.98),'mint')
 s.box('Cab_roof',(0,2.38,1.12),(1.98,.15,1.16),'ivory')
 s.box('Windshield',(0,2,1.64),(1.57,.53,.045),'glass')
 s.box('Windshield_bar',(0,2,1.68),(.065,.57,.04),'ivory')
 s.box('Windshield_reflection',(-.53,2.05,1.677),(.11,.36,.016),'glass_light')
 s.box('Front_hood',(0,1.52,1.61),(1.86,.19,.46),'mint_light')
 s.box('Grille',(0,.96,1.8),(.82,.23,.05),'teal')
 for x in [-.6,.6]:
  s.box('Headlight',(x,1.19,1.8),(.34,.24,.06),'ivory')
  s.box('Indicator',(x*1.3,1.17,1.8),(.1,.2,.065),'gold')
 s.box('Front_bumper',(0,.72,1.85),(2.04,.16,.18),'ivory')
 s.box('Front_plate',(0,.75,1.956),(.5,.13,.025),'teal')
 s.text('Plate','PIP 01',(0,.756,1.975),.09,'ivory')
 for side in [-1,1]:
  x=side*.98
  s.box('Side_window',(x,2,1.06),(.035,.51,.76),'glass')
  s.box('Cab_door_edge',(x,1.26,.62),(.035,.89,.04),'teal')
  s.box('Door_handle',(x*1.025,1.58,.81),(.07,.06,.23),'ivory')
  s.box('Mirror_arm',(x*1.09,1.83,1.61),(.24,.06,.06),'teal')
  s.box('Wing_mirror',(x*1.19,1.92,1.61),(.12,.23,.18),'teal')
  s.box('Livery_stripe',(x,1.29,-.48),(.035,.17,2.4),'red')
  for z in [-1.12,1.12]:
   s.box('Wheel_arch',(side*.99,.67,z),(.1,.64,.82),'teal')
   s.cyl('Octagonal_tyre',(side*1.025,.49,z),.43,.24,'rubber',(0,0,90),n=12)
   s.cyl('Wheel_hub',(side*1.16,.49,z),.23,.035,'ivory',(0,0,90),n=8)
   s.cyl('Hub_center',(side*1.185,.49,z),.1,.045,'red',(0,0,90),n=8)
 s.box('Logo_panel',(1.005,1.95,-.55),(.055,.92,1.9),'ivory')
 pizza(s,(1.06,2.01,-.63),.39,'x')
 s.text('Side_brand',"PIP'S",(1.11,1.91,.07),.22,'red_dark',rot=(0,90,0))
 s.text('Side_pizza','PIZZA',(1.11,1.69,.07),.16,'teal',rot=(0,90,0))
 for x in [-.48,.48]: s.box('Rear_door',(x,1.8,-1.795),(.9,1.25,.045),'glass')
 s.box('Cargo_hatch_trim',(0,1.8,-1.835),(1.91,1.34,.045),'teal')
 s.box('Cargo_hatch_inner',(0,1.8,-1.865),(1.76,1.19,.04),'glass')
 s.box('Cargo_hatch_split',(0,1.8,-1.892),(.055,1.15,.018),'ivory')
 s.box('Cargo_latch',(0,1.43,-1.9),(.16,.12,.045),'gold')
 s.text('Cargo_label','CARGO',(0,1.28,-1.9),.11,'red_dark',rot=(0,180,0))
 for x in [-.78,.78]: s.box('Taillight',(x,.98,-1.83),(.16,.34,.08),'red')
 # Compact rooftop delivery marker.
 s.box('Roof_sign_base',(0,2.7,-.65),(.99,.13,.58),'red')
 s.box('Roof_sign',(0,2.93,-.65),(.85,.37,.22),'ivory')
 s.text('Delivery_text','PIZZA',(0,2.94,-.525),.2,'red_dark')
 s.collider('Van_collision',(0,1.35,0),(1.95,2.5,3.65))
 s.save(Path('assets/pizza_van.tscn'))

def pip():
 s=Scene('Pip')
 # Individual parts under named pivots make later rigging straightforward.
 s.node('Body','Node3D','.')
 for side in [-1,1]:
  x=side*.17
  s.node('LeftLeg' if side<0 else 'RightLeg','Node3D','.',f'position = Vector3({x}, 0.64, 0)\n')
  p='LeftLeg' if side<0 else 'RightLeg'
  s.box('Trouser',(0,-.24,0),(.265,.49,.29),'teal',parent=p)
  s.box('Sock',(0,-.49,.02),(.24,.1,.27),'ivory',parent=p)
  s.box('Sneaker',(0,-.57,.09),(.3,.16,.43),'red_dark',parent=p)
  s.box('Sneaker_sole',(0,-.635,.1),(.31,.055,.44),'ivory',parent=p)
  s.box('Lace',(0,-.505,.18),(.18,.025,.07),'ivory',parent=p)
 s.box('Shirt',(0,.94,0),(.69,.62,.36),'ivory',parent='Body')
 s.box('Apron',(0,.84,.205),(.5,.49,.055),'red',parent='Body')
 s.box('Apron_top',(0,1.13,.203),(.3,.24,.055),'red',parent='Body')
 s.box('Apron_pocket',(0,.84,.242),(.27,.14,.035),'red_dark',parent='Body')
 for x in [-.18,.18]: s.box('Apron_strap',(x,1.17,.21),(.07,.23,.04),'red',parent='Body')
 s.box('Neck',(0,1.3,0),(.22,.2,.24),'skin',parent='Body')
 for x in [-.13,.13]: s.box('Collar',(x,1.24,.23),(.17,.13,.06),'white',parent='Body',rot=(0,0,25 if x<0 else -25))
 # One hand holds a takeaway box. The other rests at his side.
 for side in [-1,1]:
  p='LeftArm' if side<0 else 'RightArm';x=side*.43
  s.node(p,'Node3D','.',f'position = Vector3({x}, 1.15, 0)\n')
  s.box('Sleeve',(0,-.1,0),(.23,.3,.34),'red',parent=p)
  if side<0:
   s.box('Forearm',(0,-.28,.17),(.19,.17,.44),'skin_light',parent=p)
   s.box('Hand',(0,-.23,.36),(.21,.16,.2),'skin_light',parent=p)
  else:
   s.box('Arm',(0,-.33,0),(.18,.27,.23),'skin',parent=p)
   s.box('Hand',(0,-.48,.025),(.21,.19,.24),'skin_light',parent=p)
 s.box('Pizza_box',(-.43,1.025,.46),(.64,.13,.6),'cream')
 s.box('Pizza_box_lid',(-.43,1.105,.46),(.67,.04,.63),'ivory')
 s.box('Box_red_stripe',(-.43,1.03,.769),(.48,.06,.012),'red')
 s.cyl('Box_logo',(-.43,1.131,.46),.16,.009,'red',n=8)
 s.cyl('Box_cheese',(-.43,1.139,.46),.115,.009,'cheese',n=8)
 s.node('Head','Node3D','.', 'position = Vector3(0, 1.62, 0)\n')
 s.box('Head',(0,0,0),(.65,.59,.53),'skin_light',parent='Head')
 s.box('Hair_back',(0,.1,-.23),(.68,.42,.13),'hair',parent='Head')
 for x in [-.33,.33]:
  s.box('Ear',(x,-.035,0),(.13,.2,.18),'skin',parent='Head')
  s.box('Sideburn',(x,.12,.14),(.07,.2,.14),'hair',parent='Head')
 s.box('Fringe',(-.12,.19,.277),(.36,.12,.065),'hair',parent='Head')
 s.box('Fringe_step',(.085,.13,.277),(.12,.13,.065),'hair',parent='Head')
 for x in [-.16,.16]:
  s.box('Eye',(x,-.015,.278),(.065,.085,.025),'ink',parent='Head')
  s.box('Eye_spark',(x-.01,.006,.294),(.022,.025,.009),'white',parent='Head')
  s.box('Cheek',(x*1.35,-.1,.278),(.095,.05,.012),'pink',parent='Head')
 s.box('Nose',(0,-.07,.3),(.09,.09,.095),'skin',parent='Head')
 s.box('Smile',(0,-.17,.276),(.15,.028,.018),'hair',parent='Head')
 s.box('Cap',(0,.3,-.015),(.73,.19,.61),'red',parent='Head')
 s.box('Cap_top',(0,.412,-.04),(.53,.065,.43),'red_light',parent='Head')
 s.box('Cap_brim',(0,.24,.34),(.73,.075,.33),'red',parent='Head')
 s.box('Cap_badge',(0,.32,.299),(.17,.125,.02),'ivory',parent='Head')
 s.box('Badge_cheese',(0,.32,.314),(.08,.07,.015),'gold',parent='Head')
 s.save(Path('assets/pip.tscn'))

def land():
 s=Scene('Land')
 s.box('Earth_block',(0,-.5,0),(15,.86,12.5),'soil')
 s.box('Grass_top',(0,-.04,0),(15,.18,12.5),'grass')
 s.box('Earth_lower',(0,-.94,0),(14.7,.16,12.2),'soil_light')
 # Small exposed soil voxels along the cutaway edge.
 for i in range(27):
  x=-7.1+i*.55
  if i%3: s.box('Soil_pixel',(x,-.38-(i%3)*.16,6.26),(.29,.15,.035),'soil_light')
 for i in range(20):
  z=-5.9+i*.6
  if i%3: s.box('Soil_side_pixel',(7.51,-.39-(i%2)*.2,z),(.035,.15,.31),'soil_light')
 s.box('Parking_pad',(3.8,.065,1.25),(5.6,.12,7.7),'road')
 s.box('Walkway',(-1.6,.09,.7),(7.9,.16,7.8),'paving')
 # Front pavement and curb are individually editable blocks.
 for i in range(25):
  x=-7.2+i*.6
  s.box('Front_curb',(x,.11,5.31),(.57,.21,.29),'paving_light')
 for i in range(11):
  for j in range(3):
   x=-5.7+i*.64;z=2.5+j*.79
   s.box('Paver',(x,.181,z),(.6,.026,.74),'paving_light' if (i+j)%4 else 'paving')
 for z in [-1.7,1.35,4.35]: s.box('Parking_line',(4,.135,z),(4.3,.014,.075),'ivory')
 s.box('Parking_stop',(5.89,.22,.05),(.2,.25,1.27),'paving_light')
 # Trees: clustered cubes, with light-facing voxel variation.
 def tree(x,z,h):
  s.box('Tree_trunk',(x,h*.43,z),(.34,h*.86,.37),'bark')
  s.box('Branch',(x+.25,h*.71,z),(.65,.19,.2),'bark')
  for dx,dy,dz,dim,c in [(-.4,0,0,1.1,'leaf'),(.42,.13,.12,1.1,'leaf_light'),(0,.64,-.12,1.14,'leaf_light'),(0,.1,-.5,1.15,'leaf'),(.05,.12,.53,1,'leaf_light')]:
   s.box('Voxel_canopy',(x+dx,h+dy,z+dz),(dim,dim*.85,dim),c)
 tree(-6.05,-3.6,2.75);tree(5.95,-4.35,3.1);tree(-6.2,2,2.35)
 # Fence around rear boundary.
 for x in [-7+i*.5 for i in range(29)]:
  s.box('Fence_picket',(x,.61,-5.62),(.14,1.13,.16),'ivory')
  s.box('Picket_cap',(x,1.2,-5.62),(.19,.1,.2),'cream')
 for y in [.4,.85]: s.box('Fence_rail',(0,y,-5.7),(14.2,.13,.12),'cream')
 for x,z in [(-5.3,-4.7),(4.8,-4.6),(-5.7,3.9),(6.7,4.1),(-4.8,4.6)]:
  for j in range(3):
   s.box('Shrub',(x+j*.25,.3+j%2*.12,z),(.5,.52,.55),'leaf_light' if j%2 else 'leaf')
 for i in range(65):
  x=random.uniform(-7.1,7.1);z=random.uniform(-5.2,4.9)
  if -5.6<x<6.7 and -4.8<z<4.65: continue
  s.box('Grass_voxel',(x,.1,z),(.16,.08,.24),'grass_light' if i%2 else 'grass_dark')
 # Small flowering clumps and mushrooms at the perimeter.
 for x,z in [(-6.5,4.3),(-5.1,4.8),(6.65,3.5),(5.3,-5),(-4.6,-5)]:
  for j in range(3):
   xx=x+j*.16;s.box('Flower_stem',(xx,.23,z),(.045,.3,.045),'leaf')
   s.box('Wildflower',(xx,.4+(j%2)*.05,z),(.13,.1,.13),'white' if j%2 else 'flower')
 s.collider('Ground_collision',(0,-.12,0),(15,.25,12.5))
 s.collider('Walkway_collision',(-1.6,.09,.7),(7.9,.16,7.8))
 s.collider('Parking_collision',(3.8,.065,1.25),(5.6,.12,7.7))
 s.save(Path('assets/land.tscn'))

def props():
 s=Scene('StreetDetails')
 # A-board menu, intentionally just exterior dressing.
 s.box('Menu_back',(-3.98,.83,2.3),(.83,1.31,.14),'bark',rot=(-10,0,-5))
 s.box('Menu_board',(-3.98,.88,2.41),(.68,1.02,.05),'teal',rot=(-10,0,-5))
 s.text('Menu_title','TODAY',(-3.98,1.18,2.49),.16,'ivory')
 s.text('Menu_pizza','PIZZA',(-3.98,.95,2.52),.18,'gold')
 s.text('Menu_price','$5',(-3.98,.67,2.56),.23,'ivory')
 for x in [-4.3,-3.66]: s.box('Menu_leg',(x,.38,2.18),(.09,.65,.15),'bark',rot=(-15,0,0))
 # Bench on left of the shop.
 for z in [-.53,-.3,-.07]: s.box('Bench_seat',(-5.45,.61,z),(1.85,.13,.18),'crust')
 for y in [.93,1.18]: s.box('Bench_back',(-5.45,y,-.65),(1.85,.18,.1),'crust')
 for x in [-6.13,-4.77]:
  for z in [-.56,-.05]: s.box('Bench_foot',(x,.34,z),(.12,.6,.13),'teal')
  s.box('Bench_upright',(x,.89,-.69),(.1,.8,.12),'teal')
 # Takeaway stack beside shop.
 for i in range(3):
  s.box('Takeaway_box',(-3.45,.29+i*.14,-1.4),(.65,.12,.65),'cream')
  s.box('Box_lid',(-3.45,.36+i*.14,-1.4),(.68,.03,.68),'ivory')
 s.save(Path('assets/street_details.tscn'))

def main_scene():
 ext=''
 for i,file in enumerate(['land','pizza_shop','pizza_van','pip','street_details'],1):
  ext+=f'[ext_resource type="PackedScene" path="res://assets/{file}.tscn" id="{i}"]\n'
 ext+='[ext_resource type="Script" path="res://tools/preview_capture.gd" id="6"]\n'
 sub='''[sub_resource type="Environment" id="Env"]
background_mode = 1
background_color = Color(0.66, 0.79, 0.81, 1)
ambient_light_source = 3
ambient_light_color = Color(1, 0.92, 0.78, 1)
ambient_light_energy = 0.38
reflected_light_source = 2
tonemap_mode = 0
'''
 nodes='''[node name="PizzaCorner" type="Node3D"]
script = ExtResource("6")

[node name="Land" parent="." instance=ExtResource("1")]

[node name="PizzaShop" parent="." instance=ExtResource("2")]
position = Vector3(-1.35, 0.18, -1.65)

[node name="PizzaVan" parent="." instance=ExtResource("3")]
position = Vector3(3.9, 0.15, 1.25)
rotation = Vector3(0, -0.17, 0)

[node name="Pip" parent="." instance=ExtResource("4")]
position = Vector3(-0.9, 0.2, 3.1)
rotation = Vector3(0, 0.25, 0)

[node name="StreetDetails" parent="." instance=ExtResource("5")]

[node name="Environment" type="WorldEnvironment" parent="."]
environment = SubResource("Env")

[node name="Sun" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-55, -32, 0)
light_color = Color(1, 0.91, 0.77, 1)
light_energy = 0.9
shadow_enabled = true
directional_shadow_max_distance = 45.0
shadow_bias = 0.03

[node name="Fill" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-35, 135, 0)
light_color = Color(0.73, 0.87, 1, 1)
light_energy = 0.2

[node name="Camera" type="Camera3D" parent="."]
position = Vector3(15, 12, 19)
rotation_degrees = Vector3(-24.24, 38.29, 0)
projection = 1
size = 19.8
current = true
far = 100.0
'''
 target=OUTPUT_ROOT/'scenes/pizza_corner.tscn'; target.parent.mkdir(parents=True,exist_ok=True)
 target.write_text('[gd_scene load_steps=8 format=3]\n\n'+ext+'\n'+sub+'\n'+nodes,encoding='utf-8')

if __name__=='__main__':
 parser=argparse.ArgumentParser(description='Build original editable Godot art.')
 parser.add_argument('--output',type=Path,default=OUTPUT_ROOT,help='output root; supports isolated staging')
 OUTPUT_ROOT=parser.parse_args().output.resolve()
 shop();van();pip();land();props();main_scene()
 print('Built five original Godot assets and the assembled exterior scene.')
