extends Node2D

# Mountain Rider - self-contained offline 2D hill-driving game.
# All artwork is drawn in code; no network connection or external assets required.

const VIEW := Vector2(960.0, 540.0)
const GRAVITY := 1050.0
const SAVE_FILE := "user://mountain_rider.cfg"
const CAR_DATA := [
    {"name":"Trail Jeep", "price":0, "power":1.00, "grip":1.00, "color":Color("#e65336"), "top":560.0},
    {"name":"Rally Buggy", "price":350, "power":1.25, "grip":0.92, "color":Color("#e7b83f"), "top":650.0},
    {"name":"Mountain Truck", "price":700, "power":0.90, "grip":1.35, "color":Color("#398bd0"), "top":490.0},
    {"name":"Ridge Racer", "price":1200, "power":1.52, "grip":0.90, "color":Color("#8b62c9"), "top":720.0}
]

var screen_size := VIEW
var game_state := "menu"
var selected_car := 0
var unlocked := [true, false, false, false]
var bank_coins := 0
var best_distance := 0.0
var world_x := 0.0
var distance_m := 0.0
var run_coins := 0
var fuel := 100.0
var velocity_x := 0.0
var body_y := 0.0
var velocity_y := 0.0
var car_angle := 0.0
var angular_velocity := 0.0
var wheel_rotation := 0.0
var grounded := true
var gas_down := false
var brake_down := false
var touch_gas := false
var touch_brake := false
var pickups: Array[Dictionary] = []
var toast := ""
var toast_time := 0.0
var button_rects: Dictionary = {}

func _ready() -> void:
    get_viewport().size_changed.connect(_on_resize)
    _on_resize()
    _load_progress()
    _reset_run()
    set_process(true)
    set_physics_process(true)

func _on_resize() -> void:
    screen_size = get_viewport_rect().size
    queue_redraw()

func _load_progress() -> void:
    var cfg := ConfigFile.new()
    if cfg.load(SAVE_FILE) == OK:
        bank_coins = int(cfg.get_value("progress", "coins", 0))
        best_distance = float(cfg.get_value("progress", "best", 0.0))
        unlocked = cfg.get_value("progress", "unlocked", [true, false, false, false])
        selected_car = clampi(int(cfg.get_value("progress", "selected", 0)), 0, CAR_DATA.size() - 1)

func _save_progress() -> void:
    var cfg := ConfigFile.new()
    cfg.set_value("progress", "coins", bank_coins)
    cfg.set_value("progress", "best", best_distance)
    cfg.set_value("progress", "unlocked", unlocked)
    cfg.set_value("progress", "selected", selected_car)
    cfg.save(SAVE_FILE)

func _reset_run() -> void:
    world_x = 0.0
    distance_m = 0.0
    run_coins = 0
    fuel = 100.0
    velocity_x = 0.0
    velocity_y = 0.0
    car_angle = 0.0
    angular_velocity = 0.0
    wheel_rotation = 0.0
    body_y = _ground_y(0.0) - 54.0
    grounded = true
    gas_down = false
    brake_down = false
    touch_gas = false
    touch_brake = false
    pickups.clear()
    for i in range(1, 220):
        var px := float(i) * 255.0 + randf_range(-35.0, 35.0)
        var kind := "fuel" if i % 6 == 0 else "coin"
        pickups.append({"x": px, "y": _ground_y(px) - randf_range(90.0, 145.0), "kind": kind, "taken": false})

func _ground_y(x: float) -> float:
    return 385.0 - 72.0 * sin(x * 0.0048) - 35.0 * sin(x * 0.011 + 1.2) - 17.0 * sin(x * 0.025)

func _ground_slope(x: float) -> float:
    return atan((_ground_y(x + 4.0) - _ground_y(x - 4.0)) / 8.0)

func _physics_process(delta: float) -> void:
    if game_state != "playing":
        return
    var car: Dictionary = CAR_DATA[selected_car]
    var accelerating := gas_down or touch_gas or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D)
    var reversing := brake_down or touch_brake or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
    if accelerating and fuel > 0.0:
        velocity_x += 480.0 * float(car["power"]) * delta
        fuel = maxf(0.0, fuel - 3.4 * delta)
    if reversing:
        velocity_x -= 370.0 * delta
    velocity_x = clampf(velocity_x, -160.0, float(car["top"]))
    velocity_x *= 1.0 - 0.20 * delta
    world_x = maxf(0.0, world_x + velocity_x * delta)
    distance_m = world_x / 10.0
    wheel_rotation += velocity_x * delta / 22.0
    var slope := _ground_slope(world_x)
    var ground_contact := minf(_ground_y(world_x - 29.0), _ground_y(world_x + 29.0)) - 43.0
    if body_y >= ground_contact and velocity_y >= 0.0:
        body_y = lerpf(body_y, ground_contact, minf(1.0, 18.0 * delta))
        velocity_y = 0.0
        grounded = true
        angular_velocity += wrapf(slope - car_angle, -PI, PI) * (8.0 + float(car["grip"]) * 3.0) * delta
        angular_velocity *= pow(0.16, delta)
    else:
        grounded = false
        velocity_y += GRAVITY * delta
        body_y += velocity_y * delta
        if accelerating:
            angular_velocity -= 1.05 * delta
        if reversing:
            angular_velocity += 1.05 * delta
        angular_velocity *= pow(0.992, delta)
    car_angle += angular_velocity * delta
    car_angle = wrapf(car_angle, -PI, PI)
    for item in pickups:
        if item["taken"]:
            continue
        if absf(float(item["x"]) - world_x) < 38.0 and absf(float(item["y"]) - body_y) < 82.0:
            item["taken"] = true
            if item["kind"] == "coin":
                run_coins += 1
            else:
                fuel = minf(100.0, fuel + 30.0)
                _show_toast("Fuel +30%")
    if distance_m > best_distance:
        best_distance = distance_m
    if absf(car_angle) > 2.45 or body_y > 650.0:
        _finish_run()
    elif fuel <= 0.0 and velocity_x < 28.0:
        _finish_run()
    queue_redraw()

func _finish_run() -> void:
    if game_state != "playing":
        return
    bank_coins += run_coins
    game_state = "crashed"
    _save_progress()

func _show_toast(message: String) -> void:
    toast = message
    toast_time = 1.5

func _process(delta: float) -> void:
    if toast_time > 0.0:
        toast_time -= delta
        if toast_time <= 0.0:
            toast = ""
    queue_redraw()

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_ESCAPE:
            if game_state == "playing" or game_state == "garage" or game_state == "crashed":
                game_state = "menu"
            get_viewport().set_input_as_handled()
    if event is InputEventScreenTouch:
        if event.pressed:
            _handle_press(event.position)
        else:
            touch_gas = false
            touch_brake = false
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            _handle_press(event.position)
        else:
            touch_gas = false
            touch_brake = false

func _handle_press(pos: Vector2) -> void:
    var scale := screen_size / VIEW
    var p := pos / scale
    if game_state == "playing":
        if p.x > 690.0 and p.y > 410.0:
            touch_gas = true
        elif p.x < 270.0 and p.y > 410.0:
            touch_brake = true
        elif p.y < 58.0 and p.x < 130.0:
            game_state = "menu"
        return
    if game_state == "menu":
        if Rect2(330, 290, 300, 72).has_point(p):
            _reset_run()
            game_state = "playing"
        elif Rect2(330, 380, 300, 65).has_point(p):
            game_state = "garage"
    elif game_state == "garage":
        if Rect2(30, 25, 150, 55).has_point(p):
            game_state = "menu"
        elif Rect2(180, 345, 280, 70).has_point(p):
            selected_car = (selected_car - 1 + CAR_DATA.size()) % CAR_DATA.size()
        elif Rect2(500, 345, 280, 70).has_point(p):
            selected_car = (selected_car + 1) % CAR_DATA.size()
        elif Rect2(330, 435, 300, 65).has_point(p):
            var price := int(CAR_DATA[selected_car]["price"])
            if unlocked[selected_car]:
                _save_progress()
                game_state = "menu"
                _show_toast("Vehicle selected")
            elif bank_coins >= price:
                bank_coins -= price
                unlocked[selected_car] = true
                _save_progress()
                _show_toast("Vehicle unlocked!")
            else:
                _show_toast("Not enough coins")
    elif game_state == "crashed":
        if Rect2(330, 315, 300, 70).has_point(p):
            _reset_run()
            game_state = "playing"
        elif Rect2(330, 400, 300, 60).has_point(p):
            game_state = "menu"

func _draw() -> void:
    var s := screen_size / VIEW
    draw_set_transform(Vector2.ZERO, 0.0, s)
    _draw_sky()
    if game_state == "playing" or game_state == "crashed":
        _draw_world()
        _draw_hud()
        if game_state == "crashed":
            _draw_crash_overlay()
    elif game_state == "garage":
        _draw_garage()
    else:
        _draw_menu()
    if toast_time > 0.0 and toast != "":
        draw_rect(Rect2(365, 92, 230, 48), Color("#172b3ddd"), true)
        _draw_text(toast, Vector2(480, 123), 21, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_sky() -> void:
    draw_rect(Rect2(0, 0, 960, 540), Color("#83d1f4"), true)
    draw_circle(Vector2(805, 92), 42, Color("#ffe98a"))
    for i in range(4):
        var x := fposmod(float(i) * 290.0 - world_x * 0.10, 1200.0) - 100.0
        _draw_cloud(Vector2(x, 92.0 + float(i % 2) * 48.0))
    for layer in range(2):
        var col := Color("#a4c9b0") if layer == 0 else Color("#7eb19a")
        var points := PackedVector2Array([Vector2(0, 390)])
        for x in range(0, 981, 12):
            var wx := float(x) + world_x * (0.18 if layer == 0 else 0.28)
            points.append(Vector2(x, 275.0 + float(layer) * 43.0 + sin(wx * 0.004) * 48.0 + sin(wx * 0.012) * 19.0))
        points.append(Vector2(960, 390))
        draw_colored_polygon(points, col)

func _draw_cloud(p: Vector2) -> void:
    draw_circle(p, 19, Color("#ffffffd9"))
    draw_circle(p + Vector2(22, -8), 25, Color("#ffffffd9"))
    draw_circle(p + Vector2(49, 1), 18, Color("#ffffffd9"))

func _draw_world() -> void:
    var ground_points := PackedVector2Array([Vector2(0, 540)])
    for x in range(0, 981, 5):
        ground_points.append(Vector2(x, _ground_y(world_x + float(x) - 170.0)))
    ground_points.append(Vector2(960, 540))
    draw_colored_polygon(ground_points, Color("#78bd4c"))
    var ridge := PackedVector2Array()
    for x in range(0, 981, 5):
        ridge.append(Vector2(x, _ground_y(world_x + float(x) - 170.0)))
    draw_polyline(ridge, Color("#367c39"), 7.0, true)
    for x in range(0, 981, 24):
        var y := _ground_y(world_x + float(x) - 170.0)
        draw_line(Vector2(x, y + 12), Vector2(x + 8, y + 17), Color("#d5a35e"), 2.0)
    _draw_pickups()
    _draw_car(Vector2(170, body_y), car_angle, CAR_DATA[selected_car]["color"])

func _draw_pickups() -> void:
    for item in pickups:
        if item["taken"]:
            continue
        var x := float(item["x"]) - world_x + 170.0
        if x < -30.0 or x > 990.0:
            continue
        var p := Vector2(x, float(item["y"]))
        if item["kind"] == "coin":
            draw_circle(p, 13, Color("#d88b13"))
            draw_circle(p, 10, Color("#ffcf35"))
            _draw_text("$", p + Vector2(0, 6), 16, Color("#9b6409"), HORIZONTAL_ALIGNMENT_CENTER)
        else:
            draw_rect(Rect2(p - Vector2(11, 13), Vector2(22, 27)), Color("#e54839"), true)
            draw_rect(Rect2(p - Vector2(5, 8), Vector2(10, 13)), Color("#fff2c5"), true)
            draw_rect(Rect2(p - Vector2(8, 17), Vector2(16, 5)), Color("#f8c83e"), true)

func _draw_car(p: Vector2, rot: float, car_color: Color) -> void:
    draw_set_transform(p, rot)
    _draw_ellipse(Vector2(0, 9), Vector2(47, 8), Color("#31513c55"))
    draw_colored_polygon(PackedVector2Array([Vector2(-43,-17),Vector2(-35,-31),Vector2(28,-31),Vector2(43,-17),Vector2(40,0),Vector2(-40,0)]), car_color)
    draw_colored_polygon(PackedVector2Array([Vector2(-24,-29),Vector2(-12,-50),Vector2(18,-50),Vector2(34,-29)]), car_color.lightened(0.13))
    draw_colored_polygon(PackedVector2Array([Vector2(-8,-45),Vector2(15,-45),Vector2(27,-31),Vector2(-17,-31)]), Color("#bdeaff"))
    draw_line(Vector2(2,-46), Vector2(2,-31), Color("#547d91"), 2.0)
    draw_rect(Rect2(31,-20,8,7), Color("#fff0a5"), true)
    draw_rect(Rect2(-42,-18,7,7), Color("#ffb0a0"), true)
    for wx in [-27.0, 27.0]:
        draw_circle(Vector2(wx, 1), 14, Color("#202b32"))
        draw_circle(Vector2(wx, 1), 7, Color("#aebbc0"))
        draw_circle(Vector2(wx, 1), 3, Color("#59656c"))
    draw_line(Vector2(-31,-5), Vector2(31,-5), Color("#652d28"), 2.0)
    draw_set_transform(Vector2.ZERO)

func _draw_hud() -> void:
    _panel(Rect2(16, 14, 330, 58), Color("#18334acc"))
    _draw_text("COINS  %d" % run_coins, Vector2(32, 50), 20, Color("#ffdc55"))
    _draw_text("DIST  %d m" % int(distance_m), Vector2(175, 50), 20, Color.WHITE)
    _panel(Rect2(690, 14, 250, 58), Color("#18334acc"))
    _draw_text("FUEL", Vector2(706, 49), 17, Color.WHITE)
    draw_rect(Rect2(765, 34, 155, 18), Color("#263e47"), true)
    draw_rect(Rect2(767, 36, 151 * fuel / 100.0, 14), Color("#53d879") if fuel > 25 else Color("#ef5a48"), true)
    _draw_button(Rect2(16, 88, 105, 45), "MENU", Color("#344c61"))
    _draw_button(Rect2(24, 444, 190, 76), "BRAKE  ◀", Color("#344c61"))
    _draw_button(Rect2(746, 444, 190, 76), "GAS  ▶", Color("#d94e37"))

func _draw_menu() -> void:
    _draw_text("MOUNTAIN RIDER", Vector2(480, 145), 48, Color("#18394a"), HORIZONTAL_ALIGNMENT_CENTER)
    _draw_text("Climb higher. Collect coins. Keep your wheels down!", Vector2(480, 190), 19, Color("#284e5c"), HORIZONTAL_ALIGNMENT_CENTER)
    _draw_car(Vector2(480, 260), -0.08, CAR_DATA[selected_car]["color"])
    _panel(Rect2(350, 205, 260, 45), Color("#ffffff99"))
    _draw_text("BEST  %d m     COINS  %d" % [int(best_distance), bank_coins], Vector2(480, 234), 18, Color("#18394a"), HORIZONTAL_ALIGNMENT_CENTER)
    _draw_button(Rect2(330, 300, 300, 70), "START DRIVE", Color("#e65336"))
    _draw_button(Rect2(330, 388, 300, 62), "GARAGE  🚙", Color("#2c7890"))
    _draw_text("Offline game  •  Arrow keys / A-D or touch controls", Vector2(480, 500), 16, Color("#284e5c"), HORIZONTAL_ALIGNMENT_CENTER)

func _draw_garage() -> void:
    _draw_button(Rect2(30, 25, 150, 55), "← BACK", Color("#344c61"))
    _draw_text("VEHICLE GARAGE", Vector2(480, 105), 39, Color("#18394a"), HORIZONTAL_ALIGNMENT_CENTER)
    var car: Dictionary = CAR_DATA[selected_car]
    _draw_car(Vector2(480, 245), -0.05, car["color"])
    _panel(Rect2(275, 295, 410, 40), Color("#ffffffaa"))
    _draw_text(str(car["name"]), Vector2(480, 323), 25, Color("#18394a"), HORIZONTAL_ALIGNMENT_CENTER)
    _draw_text("Coins: %d    Power: %.2fx    Grip: %.2fx" % [bank_coins, car["power"], car["grip"]], Vector2(480, 365), 17, Color("#284e5c"), HORIZONTAL_ALIGNMENT_CENTER)
    _draw_button(Rect2(180, 385, 280, 65), "◀ PREVIOUS", Color("#2c7890"))
    _draw_button(Rect2(500, 385, 280, 65), "NEXT ▶", Color("#2c7890"))
    var price := int(car["price"])
    var action := "SELECTED — PLAY" if unlocked[selected_car] else "UNLOCK  •  %d COINS" % price
    _draw_button(Rect2(330, 465, 300, 60), action, Color("#e65336") if unlocked[selected_car] or bank_coins >= price else Color("#667781"))
    _draw_text("Vehicle %d / %d" % [selected_car + 1, CAR_DATA.size()], Vector2(480, 460), 15, Color("#284e5c"), HORIZONTAL_ALIGNMENT_CENTER)

func _draw_crash_overlay() -> void:
    draw_rect(Rect2(0, 0, 960, 540), Color("#071923bb"), true)
    _draw_text("RUN OVER!", Vector2(480, 180), 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    _draw_text("Distance: %d m     Coins collected: %d" % [int(distance_m), run_coins], Vector2(480, 230), 22, Color("#ffdf75"), HORIZONTAL_ALIGNMENT_CENTER)
    _draw_text("Best: %d m     Wallet: %d" % [int(best_distance), bank_coins], Vector2(480, 265), 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    _draw_button(Rect2(330, 315, 300, 65), "TRY AGAIN", Color("#e65336"))
    _draw_button(Rect2(330, 400, 300, 58), "MAIN MENU", Color("#2c7890"))

func _panel(rect: Rect2, color: Color) -> void:
    draw_rect(rect, color, true)
    draw_rect(rect, Color("#ffffff44"), false, 2.0)

func _draw_button(rect: Rect2, label: String, color: Color) -> void:
    draw_rect(rect, color, true)
    draw_rect(rect, Color("#ffffff66"), false, 2.0)
    _draw_text(label, rect.position + Vector2(rect.size.x / 2.0, rect.size.y / 2.0 + 7.0), 21, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_text(value: String, pos: Vector2, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
    var font := ThemeDB.fallback_font
    draw_string(font, pos, value, align, -1, size, color)

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
    var pts := PackedVector2Array()
    for i in range(25):
        var a := TAU * float(i) / 24.0
        pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
    draw_colored_polygon(pts, color)
