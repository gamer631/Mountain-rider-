extends Node3D

# Mountain Rider 3D - procedural low-poly mountain driving for mobile and desktop.
const SAVE_FILE := "user://mountain_rider.cfg"
const WORLD_LENGTH := 3600.0
const REGIONS := [
    {"name":"TERAI PLAINS", "detail":"Open grasslands and foothill roads", "ground":0.0},
    {"name":"CHITWAN", "detail":"Sal forests and the Narayani river", "ground":0.15},
    {"name":"POKHARA", "detail":"Lakeside valley beneath the Annapurna range", "ground":0.35},
    {"name":"ANNAPURNA", "detail":"Terraced hills and high mountain passes", "ground":1.0},
    {"name":"MUSTANG", "detail":"Arid cliffs and Himalayan desert", "ground":1.5},
    {"name":"EVEREST REGION", "detail":"Snow peaks, prayer flags and alpine trails", "ground":2.1},
    {"name":"KATHMANDU VALLEY", "detail":"Historic temples and Himalayan foothills", "ground":0.4}
]
const CARS := [
    {"name":"Trail Jeep","price":0,"power":16.0,"grip":1.0,"top":30.0,"color":Color("#e65336")},
    {"name":"Rally Buggy","price":350,"power":21.0,"grip":0.9,"top":38.0,"color":Color("#e7b83f")},
    {"name":"Mountain Truck","price":700,"power":14.0,"grip":1.3,"top":26.0,"color":Color("#398bd0")},
    {"name":"Ridge Racer","price":1200,"power":24.0,"grip":0.85,"top":42.0,"color":Color("#8b62c9")}
]
var rng := RandomNumberGenerator.new()
var state := "menu"
var selected := 0
var unlocked := [true,false,false,false]
var wallet := 0
var best := 0.0
var distance := 0.0
var speed := 0.0
var fuel := 100.0
var coins := 0
var gas := false
var brake := false
var pitch := 0.0
var bounce := 0.0
var bounce_speed := 0.0
var wheel_spin := 0.0
var car: Node3D
var car_body: MeshInstance3D
var wheels: Array[MeshInstance3D] = []
var camera: Camera3D
var title: Label
var info: Label
var hud: Label
var fuel_bar: ProgressBar
var start_btn: Button
var garage_btn: Button
var prev_btn: Button
var next_btn: Button
var select_btn: Button
var retry_btn: Button
var home_btn: Button
var gas_btn: Button
var brake_btn: Button
var pause_btn: Button

func _ready() -> void:
    rng.randomize()
    _load_save()
    _make_environment()
    _make_terrain()
    _make_scenery()
    _make_car()
    _make_ui()
    get_viewport().size_changed.connect(_resize)
    _resize()
    _reset_run()
    _update_ui()

func _region_index(z: float) -> int:
    return clampi(int(floor(maxf(0.0, z) / (WORLD_LENGTH / float(REGIONS.size())))), 0, REGIONS.size() - 1)

func _height(z: float) -> float:
    var region := _region_index(z)
    var profile := float(REGIONS[region]["ground"])
    return profile * 1.8 + sin(z * 0.004 + 1.1) * (0.55 + profile * 0.42) + sin(z * 0.010) * (0.35 + profile * 0.22) + sin(z * 0.027) * (0.18 + profile * 0.12)

func _mat(c: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = 0.95
    return m

func _make_environment() -> void:
    var world := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    var sky := Sky.new()
    var sm := ProceduralSkyMaterial.new()
    sm.sky_top_color = Color("#2876a5")
    sm.sky_horizon_color = Color("#c2dce5")
    sm.ground_bottom_color = Color("#344b42")
    sm.ground_horizon_color = Color("#a9beb4")
    sky.sky_material = sm
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color("#b8cbd2")
    env.ambient_light_energy = 0.8
    env.fog_enabled = true
    env.fog_light_color = Color("#b8d1d9")
    env.fog_density = 0.0016
    world.environment = env
    add_child(world)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48,-28,0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    add_child(sun)
    camera = Camera3D.new()
    camera.current = true
    add_child(camera)

func _make_terrain() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var cols := 36
    var rows := 360
    var width := 60.0
    for iz in range(rows):
        var z0 := -80.0 + float(iz) * WORLD_LENGTH / rows
        var z1 := z0 + WORLD_LENGTH / rows
        for ix in range(cols):
            var x0 := -width/2.0 + float(ix) * width / cols
            var x1 := x0 + width / cols
            var a := Vector3(x0,_height(z0),z0)
            var b := Vector3(x1,_height(z0),z0)
            var c := Vector3(x0,_height(z1),z1)
            var d := Vector3(x1,_height(z1),z1)
            _terrain_vertex(st,a); _terrain_vertex(st,c); _terrain_vertex(st,b)
            _terrain_vertex(st,b); _terrain_vertex(st,c); _terrain_vertex(st,d)
    st.generate_normals()
    var terrain := MeshInstance3D.new()
    terrain.mesh = st.commit()
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 1.0
    terrain.material_override = material
    add_child(terrain)

func _terrain_vertex(st: SurfaceTool, v: Vector3) -> void:
    var region := _region_index(v.z)
    var grass := [Color("#a4a05b"), Color("#547b43"), Color("#67934f"), Color("#71865a"), Color("#a27b54"), Color("#7f8e91"), Color("#70865b")][region]
    var color := Color("#77766b") if absf(v.x) < 5.5 else (Color("#a08b6c") if absf(v.x) < 6.8 else grass)
    if absf(v.x) < 5.5 and int(v.z / 10.0) % 2 == 0:
        color = Color("#817e73")
    st.set_color(color)
    st.add_vertex(v)

func _make_scenery() -> void:
    for i in range(18):
        var side := -1.0 if i % 2 == 0 else 1.0
        var peak := MeshInstance3D.new()
        var cone := CylinderMesh.new()
        cone.top_radius = 0.0
        cone.bottom_radius = rng.randf_range(25.0,38.0)
        cone.height = rng.randf_range(48.0,72.0)
        cone.radial_segments = 5
        peak.mesh = cone
        peak.position = Vector3(side * rng.randf_range(48.0,70.0),22.0,float(i)*215.0)
        peak.material_override = _mat(Color("#718b91") if i%2==0 else Color("#839a9c"))
        add_child(peak)
        var cap := MeshInstance3D.new()
        var cap_mesh := PrismMesh.new()
        cap_mesh.size = Vector3(13,9,13)
        cap.mesh = cap_mesh
        cap.position = peak.position + Vector3(0,28,0)
        cap.material_override = _mat(Color("#e8eff0"))
        add_child(cap)
    for i in range(95):
        var z := rng.randf_range(-20.0,WORLD_LENGTH-30.0)
        var x := (-1.0 if i%2==0 else 1.0) * rng.randf_range(9.0,25.0)
        var y := _height(z)
        if i%5==0:
            var rock := MeshInstance3D.new()
            var sphere := SphereMesh.new()
            sphere.radius = rng.randf_range(0.5,1.0)
            sphere.height = sphere.radius*1.4
            rock.mesh = sphere
            rock.position = Vector3(x,y+0.3,z)
            rock.scale = Vector3(1.5,0.8,1.0)
            rock.material_override = _mat(Color("#777e7b"))
            add_child(rock)
        else:
            var trunk := MeshInstance3D.new()
            var tm := CylinderMesh.new()
            tm.top_radius=0.1; tm.bottom_radius=0.2; tm.height=1.8
            trunk.mesh=tm
            trunk.position=Vector3(x,y+0.9,z)
            trunk.material_override=_mat(Color("#604b37"))
            add_child(trunk)
            for tier in range(3):
                var tree := MeshInstance3D.new()
                var foliage := CylinderMesh.new()
                foliage.top_radius=0.0
                foliage.bottom_radius=1.25-float(tier)*0.22
                foliage.height=2.1
                foliage.radial_segments=6
                tree.mesh=foliage
                tree.position=Vector3(x,y+1.8+float(tier)*1.05,z)
                tree.material_override=_mat([Color("#285b42"),Color("#34704a"),Color("#3d8051")][tier])
                add_child(tree)
    _make_nepal_landmarks()
    _make_roadside_details()

func _make_nepal_landmarks() -> void:
    var span := WORLD_LENGTH / float(REGIONS.size())
    for i in range(REGIONS.size()):
        var z := (float(i) + 0.52) * span
        var side := -1.0 if i % 2 == 0 else 1.0
        var pos := Vector3(side * 16.0, _height(z), z)
        var sign := Label3D.new()
        sign.text = str(REGIONS[i]["name"])
        sign.font_size = 48
        sign.pixel_size = 0.012
        sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
        sign.position = pos + Vector3(0, 4.0, 0)
        sign.modulate = Color("#fff0c9")
        add_child(sign)
        if i == 1:
            _make_watch_tower(pos)
            _make_bridge(Vector3(-pos.x, _height(z + 18), z + 18))
        elif i == 2:
            _make_stupa(pos, 0.9)
            _make_lake(Vector3(-pos.x, _height(z + 15) - 0.15, z + 15))
        elif i == 3:
            _make_terraces(pos)
            _make_prayer_flags(Vector3(-pos.x, _height(z + 12), z + 12))
        elif i == 4 or i == 5:
            _make_chorten(pos)
            _make_prayer_flags(Vector3(-pos.x, _height(z + 12), z + 12))
        elif i == 6:
            _make_pagoda(pos)
            _make_stupa(Vector3(-pos.x, _height(z + 18), z + 18), 1.1)

func _make_roadside_details() -> void:
    for i in range(90):
        var z := float(i) * 39.0 + 10.0
        for side in [-1.0, 1.0]:
            _box(self, Vector3(0.12, 0.7, 0.12), Vector3(side * 6.7, _height(z) + 0.35, z), Color("#e2d6b9"))

func _make_watch_tower(pos: Vector3) -> void:
    _box(self, Vector3(2.8, 0.25, 2.8), pos + Vector3(0, 3.4, 0), Color("#79583b"))
    for x in [-1.1, 1.1]:
        for z in [-1.1, 1.1]:
            _box(self, Vector3(0.16, 3.3, 0.16), pos + Vector3(x, 1.7, z), Color("#62452f"))
    _box(self, Vector3(3.3, 0.18, 3.3), pos + Vector3(0, 5.2, 0), Color("#9b6840"))

func _make_bridge(pos: Vector3) -> void:
    _box(self, Vector3(15.0, 0.22, 1.2), pos + Vector3(0, 1.4, 0), Color("#806344"))
    for side in [-1.0, 1.0]:
        for i in range(8):
            _box(self, Vector3(0.12, 1.0, 0.12), pos + Vector3(-6.5 + float(i) * 1.85, 1.9, side * 0.58), Color("#b08a5e"))
        _box(self, Vector3(0.09, 0.09, 15.0), pos + Vector3(0, 2.55, side * 0.58), Color("#555d60"))

func _make_lake(pos: Vector3) -> void:
    var lake := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(20, 18)
    lake.mesh = plane
    lake.position = pos
    var water := _mat(Color("#4c9eae"))
    water.roughness = 0.22
    water.metallic = 0.12
    lake.material_override = water
    add_child(lake)

func _make_terraces(pos: Vector3) -> void:
    for i in range(7):
        var width := 9.0 - float(i) * 0.7
        _box(self, Vector3(width, 0.22, 1.0), pos + Vector3(0, float(i) * 0.65, float(i) * 1.65), Color("#77965a") if i % 2 == 0 else Color("#a18a5b"))

func _make_prayer_flags(pos: Vector3) -> void:
    var pole := MeshInstance3D.new()
    var pm := CylinderMesh.new()
    pm.top_radius = 0.035
    pm.bottom_radius = 0.055
    pm.height = 4.2
    pole.mesh = pm
    pole.position = pos + Vector3(0, 2.1, 0)
    pole.material_override = _mat(Color("#6d5238"))
    add_child(pole)
    var colors := [Color("#2879bd"), Color("#f0d64b"), Color("#e34e43"), Color("#f4f0df"), Color("#4b9c5c")]
    for i in range(5):
        _box(self, Vector3(0.8, 0.34, 0.025), pos + Vector3(0.46, 3.8 - float(i) * 0.42, 0), colors[i])

func _make_stupa(pos: Vector3, scale_factor: float) -> void:
    var base := MeshInstance3D.new()
    var bm := CylinderMesh.new()
    bm.top_radius = 1.25 * scale_factor
    bm.bottom_radius = 1.55 * scale_factor
    bm.height = 0.7 * scale_factor
    base.mesh = bm
    base.position = pos + Vector3(0, 0.35 * scale_factor, 0)
    base.material_override = _mat(Color("#eee4ce"))
    add_child(base)
    var dome := MeshInstance3D.new()
    var dm := SphereMesh.new()
    dm.radius = scale_factor
    dm.height = 1.45 * scale_factor
    dome.mesh = dm
    dome.position = pos + Vector3(0, 1.25 * scale_factor, 0)
    dome.material_override = _mat(Color("#f3ead6"))
    add_child(dome)
    var spire := MeshInstance3D.new()
    var sm := CylinderMesh.new()
    sm.top_radius = 0.05
    sm.bottom_radius = 0.48 * scale_factor
    sm.height = 1.5 * scale_factor
    spire.mesh = sm
    spire.position = pos + Vector3(0, 2.6 * scale_factor, 0)
    spire.material_override = _mat(Color("#d6a94e"))
    add_child(spire)

func _make_chorten(pos: Vector3) -> void:
    _box(self, Vector3(2.0, 1.2, 2.0), pos + Vector3(0, 0.6, 0), Color("#eee3ce"))
    var roof := MeshInstance3D.new()
    var cone := CylinderMesh.new()
    cone.top_radius = 0.0
    cone.bottom_radius = 1.65
    cone.height = 1.0
    cone.radial_segments = 4
    roof.mesh = cone
    roof.position = pos + Vector3(0, 1.7, 0)
    roof.material_override = _mat(Color("#bd8a42"))
    add_child(roof)

func _make_pagoda(pos: Vector3) -> void:
    for i in range(3):
        var y := float(i) * 1.25
        var width := 4.4 - float(i) * 0.9
        _box(self, Vector3(width * 0.65, 1.05, width * 0.65), pos + Vector3(0, y + 0.55, 0), Color("#9d6541"))
        var roof := MeshInstance3D.new()
        var rm := CylinderMesh.new()
        rm.top_radius = 0.0
        rm.bottom_radius = width * 0.72
        rm.height = 0.7
        rm.radial_segments = 4
        roof.mesh = rm
        roof.position = pos + Vector3(0, y + 1.2, 0)
        roof.material_override = _mat(Color("#343d42") if i % 2 == 0 else Color("#8a3930"))
        add_child(roof)

func _make_car() -> void:
    car=Node3D.new()
    add_child(car)
    car_body=_box(car,Vector3(2.5,0.72,4.0),Vector3(0,1.2,0),CARS[selected]["color"])
    _box(car,Vector3(1.8,0.9,1.9),Vector3(0,1.95,-0.15),Color("#a9d1df"))
    _box(car,Vector3(2.6,0.16,4.1),Vector3(0,1.58,0),Color("#252b30"))
    _box(car,Vector3(0.4,0.16,0.12),Vector3(-0.72,1.35,2.05),Color("#fff1bd"),true)
    _box(car,Vector3(0.4,0.16,0.12),Vector3(0.72,1.35,2.05),Color("#fff1bd"),true)
    var tire := CylinderMesh.new()
    tire.top_radius=0.66; tire.bottom_radius=0.66; tire.height=0.42; tire.radial_segments=16
    for x in [-1.15,1.15]:
        for z in [-1.3,1.3]:
            var w:=MeshInstance3D.new()
            w.mesh=tire
            w.rotation_degrees.z=90
            w.position=Vector3(x,0.68,z)
            w.material_override=_mat(Color("#20262a"))
            car.add_child(w)
            wheels.append(w)
            var hub:=MeshInstance3D.new()
            var hm:=CylinderMesh.new()
            hm.top_radius=0.26; hm.bottom_radius=0.26; hm.height=0.44
            hub.mesh=hm
            hub.rotation_degrees.z=90
            hub.position=Vector3(x*1.01,0.68,z)
            hub.material_override=_mat(Color("#aebbc0"))
            car.add_child(hub)

func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow:=false) -> MeshInstance3D:
    var n:=MeshInstance3D.new()
    var mesh:=BoxMesh.new()
    mesh.size=size
    n.mesh=mesh
    n.position=pos
    var m:=_mat(color)
    if glow:
        m.emission_enabled=true
        m.emission=color
        m.emission_energy_multiplier=0.35
    n.material_override=m
    parent.add_child(n)
    return n

func _make_ui() -> void:
    var layer:=CanvasLayer.new()
    add_child(layer)
    var root:=Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    layer.add_child(root)
    title=_label(root,30,0.5,0.08,0.5,0.08,-250,0,250,52,HORIZONTAL_ALIGNMENT_CENTER)
    info=_label(root,17,0.5,0.17,0.5,0.17,-280,0,280,48,HORIZONTAL_ALIGNMENT_CENTER)
    hud=_label(root,16,0.03,0.02,0.75,0.02,0,0,0,40,HORIZONTAL_ALIGNMENT_LEFT)
    fuel_bar=ProgressBar.new()
    fuel_bar.min_value=0; fuel_bar.max_value=100; fuel_bar.show_percentage=false
    fuel_bar.anchor_left=0.03; fuel_bar.anchor_top=0.075; fuel_bar.anchor_right=0.35; fuel_bar.anchor_bottom=0.075
    fuel_bar.offset_bottom=16
    root.add_child(fuel_bar)
    start_btn=_button(root,"START DRIVE",0.5,0.57,-130,-28,130,28)
    garage_btn=_button(root,"GARAGE",0.5,0.69,-130,-28,130,28)
    retry_btn=_button(root,"DRIVE AGAIN",0.5,0.58,-130,-28,130,28)
    home_btn=_button(root,"MAIN MENU",0.5,0.70,-130,-28,130,28)
    prev_btn=_button(root,"◀ PREVIOUS",0.28,0.72,-105,-27,105,27)
    next_btn=_button(root,"NEXT ▶",0.72,0.72,-105,-27,105,27)
    select_btn=_button(root,"SELECT VEHICLE",0.5,0.84,-130,-28,130,28)
    pause_btn=_button(root,"Ⅱ",0.95,0.04,-34,-24,34,24)
    brake_btn=_button(root,"BRAKE",0.04,0.92,0,-52,145,0)
    gas_btn=_button(root,"ACCELERATE",0.96,0.92,-145,-52,0,0)
    start_btn.pressed.connect(_start)
    garage_btn.pressed.connect(func(): state="garage"; _update_ui())
    retry_btn.pressed.connect(_start)
    home_btn.pressed.connect(func(): state="menu"; _update_ui())
    prev_btn.pressed.connect(func(): _change_car(-1))
    next_btn.pressed.connect(func(): _change_car(1))
    select_btn.pressed.connect(_select_car)
    pause_btn.pressed.connect(_pause)
    brake_btn.button_down.connect(func(): brake=true)
    brake_btn.button_up.connect(func(): brake=false)
    gas_btn.button_down.connect(func(): gas=true)
    gas_btn.button_up.connect(func(): gas=false)

func _label(parent: Control, size: int, al: float, at: float, ar: float, ab: float, l: float, t: float, r: float, b: float, align: int) -> Label:
    var n:=Label.new()
    n.horizontal_alignment=align
    n.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
    n.add_theme_font_size_override("font_size",size)
    n.add_theme_color_override("font_color",Color.WHITE)
    n.add_theme_color_override("font_shadow_color",Color("#17252acc"))
    n.add_theme_constant_override("shadow_offset_x",2)
    n.add_theme_constant_override("shadow_offset_y",2)
    n.anchor_left=al; n.anchor_top=at; n.anchor_right=ar; n.anchor_bottom=ab
    n.offset_left=l; n.offset_top=t; n.offset_right=r; n.offset_bottom=b
    parent.add_child(n)
    return n

func _button(parent: Control, text_value: String, ax: float, ay: float, l: float, t: float, r: float, b: float) -> Button:
    var n:=Button.new()
    n.text=text_value
    n.anchor_left=ax; n.anchor_right=ax; n.anchor_top=ay; n.anchor_bottom=ay
    n.offset_left=l; n.offset_top=t; n.offset_right=r; n.offset_bottom=b
    n.add_theme_font_size_override("font_size",17)
    n.add_theme_color_override("font_color",Color.WHITE)
    var style:=StyleBoxFlat.new()
    style.bg_color=Color("#203c4cee")
    style.corner_radius_top_left=14; style.corner_radius_top_right=14
    style.corner_radius_bottom_left=14; style.corner_radius_bottom_right=14
    style.border_width_left=1; style.border_width_right=1; style.border_width_top=1; style.border_width_bottom=1
    style.border_color=Color("#ffffff66")
    n.add_theme_stylebox_override("normal",style)
    parent.add_child(n)
    return n

func _resize() -> void:
    if camera==null:
        return
    var s:=get_viewport().get_visible_rect().size
    var portrait:=s.y>s.x
    camera.position=Vector3(0,11 if portrait else 8,-23 if portrait else -15)
    camera.fov=76 if portrait else 68
    camera.look_at(Vector3(0,1.5,5),Vector3.UP)
    if brake_btn!=null:
        brake_btn.offset_top=-58 if portrait else -48
        gas_btn.offset_top=-58 if portrait else -48

func _load_save() -> void:
    var cfg:=ConfigFile.new()
    if cfg.load(SAVE_FILE)==OK:
        wallet=int(cfg.get_value("progress","coins",0))
        best=float(cfg.get_value("progress","best",0.0))
        unlocked=cfg.get_value("progress","unlocked",[true,false,false,false])
        selected=clampi(int(cfg.get_value("progress","selected",0)),0,CARS.size()-1)

func _save() -> void:
    var cfg:=ConfigFile.new()
    cfg.set_value("progress","coins",wallet)
    cfg.set_value("progress","best",best)
    cfg.set_value("progress","unlocked",unlocked)
    cfg.set_value("progress","selected",selected)
    cfg.save(SAVE_FILE)

func _reset_run() -> void:
    distance=0; speed=0; fuel=100; coins=0; pitch=0; bounce=0; bounce_speed=0; wheel_spin=0
    gas=false; brake=false
    car.position=Vector3(0,_height(0)+0.15,0)
    car.rotation=Vector3.ZERO

func _start() -> void:
    _reset_run()
    state="playing"
    _update_ui()

func _change_car(step: int) -> void:
    selected=posmod(selected+step,CARS.size())
    car_body.material_override=_mat(CARS[selected]["color"])
    _update_ui()

func _select_car() -> void:
    var price=int(CARS[selected]["price"])
    if unlocked[selected]:
        state="menu"
    elif wallet>=price:
        wallet-=price
        unlocked[selected]=true
        state="menu"
        _save()
    else:
        info.text="Not enough coins"
    _update_ui()

func _pause() -> void:
    if state=="playing":
        state="paused"
    elif state=="paused":
        state="playing"
    _update_ui()

func _finish() -> void:
    wallet+=coins
    best=maxf(best,distance)
    state="crashed"
    _save()
    _update_ui()

func _physics_process(delta: float) -> void:
    if state!="playing":
        return
    var data: Dictionary=CARS[selected]
    if gas or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        speed+=float(data["power"])*delta
        fuel=maxf(0,fuel-2.1*delta)
    if brake or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        speed-=24*delta
    speed=clampf(speed,0,float(data["top"]))
    speed=move_toward(speed,0,0.8*delta)
    distance+=speed*delta*1.7
    wheel_spin+=speed*delta/0.66
    var slope:=atan((_height(distance+0.8)-_height(distance-0.8))/1.6)
    pitch=lerp_angle(pitch,-slope,minf(1,delta*(5+float(data["grip"])*2)))
    var ground:=_height(distance)+0.15
    bounce_speed+=(ground-car.position.y)*30*delta
    bounce_speed*=pow(0.15,delta)
    bounce+=bounce_speed*delta
    car.position=Vector3(0,ground+bounce,distance)
    car.rotation.x=pitch
    for w in wheels:
        w.rotation.x=wheel_spin
    var size:=get_viewport().get_visible_rect().size
    var portrait:=size.y>size.x
    var cam_target:=car.position+Vector3(0,11 if portrait else 8,-23 if portrait else -15)
    camera.position=camera.position.lerp(cam_target,minf(1,delta*3))
    camera.look_at(car.position+Vector3(0,1.2,5),Vector3.UP)
    # Pickups are placed at regular intervals along the road.
    var checkpoint:=int(distance/32.0)
    if checkpoint>0 and absf(distance-float(checkpoint)*32.0)<speed*delta*1.8+0.5:
        if checkpoint%8==0:
            fuel=minf(100,fuel+18)
        else:
            coins+=1
    if distance>=WORLD_LENGTH-20 or fuel<=0:
        _finish()
    _update_hud()

func _update_hud() -> void:
    var region_name := str(REGIONS[_region_index(distance)]["name"])
    hud.text="%s   •   COINS %d   •   %d m   •   %d km/h" % [region_name,coins,int(distance),int(speed*3.6)]
    fuel_bar.value=fuel

func _update_ui() -> void:
    var active:=state=="playing" or state=="paused"
    title.visible=state!="playing"
    info.visible=state!="playing"
    hud.visible=active
    fuel_bar.visible=active
    start_btn.visible=state=="menu"
    garage_btn.visible=state=="menu"
    retry_btn.visible=state=="crashed"
    home_btn.visible=state=="crashed" or state=="paused"
    prev_btn.visible=state=="garage"
    next_btn.visible=state=="garage"
    select_btn.visible=state=="garage"
    gas_btn.visible=state=="playing"
    brake_btn.visible=state=="playing"
    pause_btn.visible=active
    if state=="menu":
        title.text="MOUNTAIN RIDER  •  NEPAL EXPEDITION"
        info.text="Drive across Nepal  •  Terai to the Himalayas  •  Offline"
    elif state=="garage":
        title.text=str(CARS[selected]["name"])
        info.text="Wallet: %d coins   •   Vehicle %d of %d" % [wallet,selected+1,CARS.size()]
        select_btn.text="SELECT VEHICLE" if unlocked[selected] else "UNLOCK  •  %d COINS" % int(CARS[selected]["price"])
    elif state=="crashed":
        title.text="RUN COMPLETE"
        info.text="Distance: %d m   •   Coins: %d   •   Best: %d m" % [int(distance),coins,int(best)]
    elif state=="paused":
        title.text="PAUSED"
        info.text="Tap pause to continue"
    _update_hud()

func _process(_delta: float) -> void:
    if state!="playing":
        var portrait:=get_viewport().get_visible_rect().size.y>get_viewport().get_visible_rect().size.x
        var target:=Vector3(0,12,-25) if portrait else Vector3(0,8,-17)
        camera.position=camera.position.lerp(target,0.025)
        camera.look_at(Vector3(0,1.5,3),Vector3.UP)
