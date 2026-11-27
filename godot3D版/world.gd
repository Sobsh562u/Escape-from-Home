extends Node3D
## 逃家游戏 · 轻 3D 原型
## 目标：验证「走 + 交互 + 心情值影响考试分数」这条主线能不能成立。
## 操作：WASD 移动，E 交互。心情 0–100，越高考试分越高。

const SPEED := 4.2
const GRAVITY := -12.0
const MOOD_MAX := 100
const HP_MAX := 100

var mood := 50
var hp := 100
var day := 1
var over := false

var player: CharacterBody3D
var camera: Camera3D
var hp_bar: ProgressBar
var mood_bar: ProgressBar
var log_label: Label
var hint_label: Label
var day_label: Label
var mood_num: Label
var hp_num: Label

var spots: Array = []
var near: Dictionary = {}
var bench_day := 0
var bench_uses := 0
var shop_day := 0
var shot_left := 8 if OS.has_environment("SHOT") else 0

func _ready() -> void:
	_setup_input()
	_build_world()
	_build_player()
	_build_ui()
	_say("你醒了。房间很小，门外是院子。WASD 走，E 用。")
	_say("心情值现在 50。心情越高，考试分越高；心情掉到底，只能考 0 到 10 分。")

# ---------------- 输入 ----------------
func _setup_input() -> void:
	var map := {"左": KEY_A, "右": KEY_D, "前": KEY_W, "后": KEY_S, "用": KEY_E}
	for k in map.keys():
		if not InputMap.has_action(k):
			InputMap.add_action(k)
		var ev := InputEventKey.new()
		ev.physical_keycode = map[k]
		InputMap.action_add_event(k, ev)

# ---------------- 场景 ----------------
func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	return m

func _box(pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	add_child(mi)
	return mi

func _solid(wall_pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = wall_pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	body.add_child(mi)
	add_child(body)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.62, 0.68, 0.78)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)

	# 地面：房间 + 院子，一整块
	_solid(Vector3(0, -0.1, -8), Vector3(13, 0.2, 25), Color(0.24, 0.24, 0.26))

	# 房间后墙（z=4）
	_solid(Vector3(0, 1.3, 4.1), Vector3(6.4, 2.6, 0.2), Color(0.35, 0.33, 0.30))
	# 房间两侧
	_solid(Vector3(-3.2, 1.3, 0), Vector3(0.2, 2.6, 8.2), Color(0.32, 0.31, 0.29))
	_solid(Vector3(3.2, 1.3, 0), Vector3(0.2, 2.6, 8.2), Color(0.32, 0.31, 0.29))
	# 房间前墙，中间留一道门
	_solid(Vector3(-2.1, 1.3, -4.1), Vector3(2.2, 2.6, 0.2), Color(0.33, 0.31, 0.29))
	_solid(Vector3(2.1, 1.3, -4.1), Vector3(2.2, 2.6, 0.2), Color(0.33, 0.31, 0.29))
	# 院子边界
	_solid(Vector3(-6.6, 0.9, -12), Vector3(0.2, 1.8, 16), Color(0.22, 0.30, 0.22))
	_solid(Vector3(6.6, 0.9, -12), Vector3(0.2, 1.8, 16), Color(0.22, 0.30, 0.22))
	_solid(Vector3(0, 0.9, -20.1), Vector3(13, 1.8, 0.2), Color(0.22, 0.30, 0.22))

	# 家具：床、书桌
	_box(Vector3(-2.0, 0.35, 2.4), Vector3(1.8, 0.45, 2.8), Color(0.55, 0.42, 0.36))
	_box(Vector3(-2.0, 0.75, 2.4), Vector3(1.6, 0.15, 2.4), Color(0.78, 0.74, 0.68))
	_box(Vector3(2.0, 0.45, 2.6), Vector3(1.6, 0.9, 0.9), Color(0.45, 0.38, 0.30))
	_box(Vector3(2.0, 0.96, 2.6), Vector3(1.7, 0.08, 1.0), Color(0.72, 0.68, 0.62))
	# 门框与半开的门板
	_box(Vector3(-1.02, 1.3, -4.05), Vector3(0.12, 2.6, 0.16), Color(0.36, 0.26, 0.18))
	_box(Vector3(1.02, 1.3, -4.05), Vector3(0.12, 2.6, 0.16), Color(0.36, 0.26, 0.18))
	var door := _box(Vector3(-0.55, 1.2, -3.65), Vector3(1.0, 2.4, 0.07), Color(0.46, 0.34, 0.23))
	door.rotation_degrees = Vector3(0, -48, 0)
	# 桌面台灯（暖光）
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(2.0, 1.6, 2.2)
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 1.6
	lamp.omni_range = 4.5
	add_child(lamp)
	# 院子：长椅、便利店
	_box(Vector3(-2.0, 0.35, -11.0), Vector3(0.8, 0.12, 2.4), Color(0.52, 0.38, 0.26))
	_box(Vector3(-2.4, 0.2, -11.0), Vector3(0.1, 0.4, 2.2), Color(0.40, 0.40, 0.42))
	_box(Vector3(-1.6, 0.2, -11.0), Vector3(0.1, 0.4, 2.2), Color(0.40, 0.40, 0.42))
	_box(Vector3(4.0, 1.2, -15.0), Vector3(3.4, 2.4, 2.2), Color(0.30, 0.44, 0.52))
	_box(Vector3(4.0, 2.5, -15.0), Vector3(3.6, 0.2, 2.4), Color(0.72, 0.66, 0.52))

	spots = [
		{"pos": Vector3(2.0, 0, 1.9), "name": "书桌（考试）", "kind": "exam"},
		{"pos": Vector3(-2.0, 0, 1.5), "name": "床（睡觉）", "kind": "sleep"},
		{"pos": Vector3(0, 0, -3.4), "name": "门（出门 / 回家）", "kind": "door"},
		{"pos": Vector3(-2.0, 0, -10.2), "name": "公园长椅（坐着缓缓）", "kind": "bench"},
		{"pos": Vector3(3.4, 0, -13.6), "name": "便利店（买瓶水）", "kind": "shop"},
	]

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, 0.9, 0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.5
	cs.shape = cap
	player.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.35
	cm.height = 1.5
	mi.mesh = cm
	mi.material_override = _mat(Color(0.86, 0.72, 0.52))
	player.add_child(mi)
	add_child(player)

	camera = Camera3D.new()
	camera.fov = 62
	camera.position = player.position + Vector3(4.2, 5.4, 5.2)
	add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(360, 148)
	root.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)

	var title := Label.new()
	title.text = "逃家游戏 · 轻 3D 原型"
	title.add_theme_font_size_override("font_size", 17)
	vb.add_child(title)

	var hp_row := HBoxContainer.new()
	vb.add_child(hp_row)
	var hp_t := Label.new()
	hp_t.text = "血条"
	vb.add_child(hp_t)
	hp_bar = ProgressBar.new()
	hp_bar.max_value = HP_MAX
	hp_bar.value = hp
	hp_bar.custom_minimum_size = Vector2(240, 16)
	hp_bar.show_percentage = false
	hp_bar.modulate = Color(0.85, 0.35, 0.32)
	vb.add_child(hp_bar)
	hp_num = Label.new()
	hp_num.text = "100 / 100"
	hp_num.add_theme_font_size_override("font_size", 12)
	vb.add_child(hp_num)

	var mood_t := Label.new()
	mood_t.text = "心情（越高越放松，考试分越高）"
	mood_t.add_theme_font_size_override("font_size", 13)
	vb.add_child(mood_t)
	mood_bar = ProgressBar.new()
	mood_bar.max_value = MOOD_MAX
	mood_bar.value = mood
	mood_bar.custom_minimum_size = Vector2(240, 16)
	mood_bar.show_percentage = false
	mood_bar.modulate = Color(0.36, 0.66, 0.72)
	vb.add_child(mood_bar)
	mood_num = Label.new()
	mood_num.text = "心情 50"
	mood_num.add_theme_font_size_override("font_size", 12)
	vb.add_child(mood_num)

	day_label = Label.new()
	day_label.text = "第 1 天"
	day_label.position = Vector2(16, 178)
	day_label.add_theme_font_size_override("font_size", 15)
	root.add_child(day_label)

	log_label = Label.new()
	log_label.position = Vector2(16, 210)
	log_label.custom_minimum_size = Vector2(700, 200)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 15)
	log_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.88))
	root.add_child(log_label)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-260, -52)
	hint_label.custom_minimum_size = Vector2(520, 30)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 16)
	hint_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	hint_label.text = ""
	root.add_child(hint_label)

	# 操作说明
	var help := Label.new()
	help.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	help.position = Vector2(-260, -24)
	help.custom_minimum_size = Vector2(520, 24)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	help.text = "WASD 移动 · E 交互"
	root.add_child(help)
	_refresh()

# ---------------- 逻辑 ----------------
func _say(t: String) -> void:
	var lines := log_label.text.split("\n")
	lines.append(t)
	if lines.size() > 7:
		lines = lines.slice(lines.size() - 7, lines.size())
	log_label.text = "\n".join(lines)

func _refresh() -> void:
	hp_bar.value = hp
	mood_bar.value = mood
	hp_num.text = "%d / 100" % hp
	mood_num.text = "心情 %d" % mood
	day_label.text = "第 %d 天" % day
	if mood >= 80:
		mood_bar.modulate = Color(0.35, 0.75, 0.45)
	elif mood <= 25:
		mood_bar.modulate = Color(0.82, 0.30, 0.28)
	else:
		mood_bar.modulate = Color(0.36, 0.66, 0.72)

func _score_from_mood() -> int:
	var base := int(round(mood * 0.95))
	var s := base + randi_range(-5, 5)
	return clamp(s, 0, 100)

func _exam() -> void:
	var score := _score_from_mood()
	_say("你坐到书桌前，考了 %d 分。" % score)
	if score >= 90:
		hp = min(HP_MAX, hp + 6)
		mood = min(MOOD_MAX, mood + 6)
		_say("妈妈没挑出毛病。心情 +6，血条 +6。")
	elif score >= 60:
		hp -= 8
		mood = max(0, mood - 6)
		_say("妈妈把卷子翻来翻去：「就这样？」扣 8 血，心情 -6。")
	else:
		hp -= 15
		mood = max(0, mood - 12)
		_say("妈妈把卷子拍在桌上：「你看看你考的。」扣 15 血，心情 -12。")
	day += 1
	if hp <= 0:
		hp = 30
		day += 1
		mood = max(0, mood - 10)
		_say("你被折腾到没力气，躺了一天，血条回到 30。")
	_refresh()

func _sleep() -> void:
	mood = min(MOOD_MAX, mood + 6)
	hp = min(HP_MAX, hp + 4)
	day += 1
	_say("你在床上睡了很久。第 %d 天。心情 +6，血条 +4。" % day)
	_refresh()

func _bench() -> void:
	if bench_day != day:
		bench_day = day
		bench_uses = 0
	if bench_uses >= 3:
		_say("今天已经在长椅上坐了三回，再坐下去妈妈该起疑了。")
		return
	bench_uses += 1
	mood = min(MOOD_MAX, mood + 10)
	hp = min(HP_MAX, hp + 6)
	_say("你在长椅上坐下，风从树缝里过。心情 +10，血条 +6。（今天第 %d/3 回）" % bench_uses)
	_refresh()

func _shop() -> void:
	if shop_day == day:
		_say("今天已经买过一瓶水了，别再花钱。")
		return
	shop_day = day
	mood = min(MOOD_MAX, mood + 5)
	_say("你在便利店买了瓶水，站在门口喝完。心情 +5。")
	_refresh()

func _door() -> void:
	if player.position.z > -4.0:
		player.position = Vector3(0, 0.9, -6.5)
		_say("你走出家门，到了院子里。")
	else:
		player.position = Vector3(0, 0.9, 0)
		_say("你推门回到房间。")

func _try_interact() -> void:
	if near.is_empty():
		return
	match near.get("kind", ""):
		"exam": _exam()
		"sleep": _sleep()
		"bench": _bench()
		"shop": _shop()
		"door": _door()
		_: pass

func _process(delta: float) -> void:
	# 移动
	var dir := Input.get_vector("左", "右", "后", "前")
	var vel := player.velocity
	vel.x = dir.x * SPEED
	vel.z = dir.y * SPEED
	vel.y = GRAVITY if not player.is_on_floor() else 0.0
	player.velocity = vel
	player.move_and_slide()

	# 相机跟拍
	var want := player.position + Vector3(4.2, 5.4, 5.2)
	camera.position = camera.position.lerp(want, min(1.0, delta * 5.0))
	camera.look_at(player.position + Vector3(0, 0.6, 0), Vector3.UP)

	# 找最近的交互点
	near = {}
	var best := 999.0
	for s in spots:
		var d: float = player.position.distance_to(s["pos"])
		if d < 1.8 and d < best:
			best = d
			near = s
	if near.is_empty():
		hint_label.text = ""
	else:
		hint_label.text = "按 E 使用：%s" % near["name"]

	if Input.is_action_just_pressed("用"):
		_try_interact()

	if shot_left > 0:
		shot_left -= 1
		if shot_left == 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(OS.get_environment("SHOT"))
			get_tree().quit()
