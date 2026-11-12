extends Control
## 逃家游戏 · Godot 版（带排行榜）
## 排行榜走网页版同一套 Supabase 接口：register_player / login_player / submit_score。

const SB_URL := "https://spvouajdnckiyihhccux.supabase.co"
const SB_KEY := "sb_publishable_gOcJXjEu8wVL7tDFNCL5yw_7Y7Zy7ET"
const 存档 := "user://player.cfg"

var 血条 := 100
var 天 := 0
var 目标 := 5
var 结束 := false
var 结束原因 := ""
var 已上传 := false

var 日志: RichTextLabel
var 状态: Label
var 面: PanelContainer
var 我的: Label
var 名框: LineEdit
var 密框: LineEdit
var 榜单: RichTextLabel

var 名字 := ""
var 玩家ID := ""
var cid := ""

func _ready() -> void:
	_搭界面()
	_读存档()
	_开场()

# ---------------- 界面 ----------------
func _搭界面() -> void:
	var 底色 := ColorRect.new()
	底色.color = Color("#f4efe6")
	底色.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(底色)

	var 边 := MarginContainer.new()
	边.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["margin_left", "margin_right"]:
		边.add_theme_constant_override(k, 18)
	边.add_theme_constant_override("margin_top", 18)
	边.add_theme_constant_override("margin_bottom", 18)
	add_child(边)

	var 竖 := VBoxContainer.new()
	竖.add_theme_constant_override("separation", 10)
	边.add_child(竖)

	var 题 := Label.new()
	题.text = "逃家游戏"
	题.add_theme_font_size_override("font_size", 26)
	竖.add_child(题)

	状态 = Label.new()
	状态.add_theme_font_size_override("font_size", 15)
	竖.add_child(状态)

	日志 = RichTextLabel.new()
	日志.size_flags_vertical = Control.SIZE_EXPAND_FILL
	日志.bbcode_enabled = true
	日志.add_theme_font_size_override("normal_font_size", 15)
	竖.add_child(日志)

	var 一行 := HBoxContainer.new()
	一行.add_theme_constant_override("separation", 8)
	竖.add_child(一行)
	for 名 in ["考试", "逃跑", "报警"]:
		var 钮 := Button.new()
		钮.text = 名
		钮.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		钮.custom_minimum_size = Vector2(0, 44)
		钮.pressed.connect(动作.bind(名))
		一行.add_child(钮)

	var 二行 := HBoxContainer.new()
	二行.add_theme_constant_override("separation", 8)
	竖.add_child(二行)
	var 榜钮 := Button.new()
	榜钮.text = "排行榜"
	榜钮.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	榜钮.custom_minimum_size = Vector2(0, 40)
	榜钮.pressed.connect(_开榜)
	二行.add_child(榜钮)
	var 重钮 := Button.new()
	重钮.text = "重新开始"
	重钮.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	重钮.custom_minimum_size = Vector2(0, 40)
	重钮.pressed.connect(_开场)
	二行.add_child(重钮)

	_搭榜()

func _搭榜() -> void:
	面 = PanelContainer.new()
	面.set_anchors_preset(Control.PRESET_FULL_RECT)
	面.visible = false
	add_child(面)

	var 边 := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		边.add_theme_constant_override(k, 16)
	面.add_child(边)

	var 竖 := VBoxContainer.new()
	竖.add_theme_constant_override("separation", 8)
	边.add_child(竖)

	var 题 := Label.new()
	题.text = "排行榜"
	题.add_theme_font_size_override("font_size", 22)
	竖.add_child(题)

	我的 = Label.new()
	我的.add_theme_font_size_override("font_size", 14)
	竖.add_child(我的)

	var 输入 := HBoxContainer.new()
	输入.add_theme_constant_override("separation", 6)
	竖.add_child(输入)
	名框 = LineEdit.new()
	名框.placeholder_text = "名字"
	名框.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	输入.add_child(名框)
	密框 = LineEdit.new()
	密框.placeholder_text = "密码"
	密框.secret = true
	密框.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	输入.add_child(密框)

	var 行 := HBoxContainer.new()
	行.add_theme_constant_override("separation", 6)
	竖.add_child(行)
	for 名 in ["注册", "登录", "刷新榜单"]:
		var 钮 := Button.new()
		钮.text = 名
		钮.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		钮.pressed.connect(榜动作.bind(名))
		行.add_child(钮)

	榜单 = RichTextLabel.new()
	榜单.bbcode_enabled = true
	榜单.size_flags_vertical = Control.SIZE_EXPAND_FILL
	榜单.add_theme_font_size_override("normal_font_size", 14)
	竖.add_child(榜单)

	var 关 := Button.new()
	关.text = "关闭"
	关.custom_minimum_size = Vector2(0, 40)
	关.pressed.connect(func(): 面.visible = false)
	竖.add_child(关)

# ---------------- 存档 ----------------
func _读存档() -> void:
	var c := ConfigFile.new()
	if c.load(存档) == OK:
		名字 = c.get_value("玩家", "名字", "")
		玩家ID = c.get_value("玩家", "id", "")
		cid = c.get_value("玩家", "cid", "")
	if cid == "":
		cid = "c" + str(Time.get_unix_time_from_system()) + str(randi())

func _存() -> void:
	var c := ConfigFile.new()
	c.set_value("玩家", "名字", 名字)
	c.set_value("玩家", "id", 玩家ID)
	c.set_value("玩家", "cid", cid)
	c.save(存档)

# ---------------- 逻辑 ----------------
func _写(文: String, 色: String = "#2c2620") -> void:
	日志.append_text("[color=%s]%s[/color]\n" % [色, 文])

func _刷状态() -> void:
	var 谁 := "未登录" if 名字 == "" else "玩家 %s" % 名字
	状态.text = "第 %d 天 · 血条 %d / %d · %s" % [天, 血条, 100, 谁]

func _开场() -> void:
	血条 = 100
	天 = 0
	结束 = false
	结束原因 = ""
	已上传 = false
	日志.clear()
	_写("第 0 天。撑过 %d 天，就能走出这个门。" % 目标, "#6d6455")
	_刷状态()

func 动作(名: String) -> void:
	if 结束:
		return
	if 名 == "考试":
		var 分 := randi_range(0, 100)
		天 += 1
		if 分 == 0:
			血条 -= 40
			_写("第 %d 天：考了 0 分，扣 40。" % 天, "#b7472a")
		elif 分 < 60:
			血条 -= 15
			_写("第 %d 天：考了 %d 分，不及格，扣 15。" % [天, 分], "#8a5a2b")
		else:
			血条 += 10
			_写("第 %d 天：考了 %d 分，过了，加 10。" % [天, 分], "#2f5d50")
	elif 名 == "逃跑":
		if randf() < 0.3:
			_写("你跑了出去，没人追上来。", "#2f5d50")
			_结("跑路")
		else:
			血条 -= 20
			_写("在巷口被抓回来，扣 20。", "#b7472a")
	else:
		if randf() < 0.15:
			_写("警察把门打开了，你被带走。", "#2f5d50")
			_结("报警")
		else:
			血条 -= 5
			_写("警察说这是家务事，扣 5。", "#8a5a2b")
	_判()

func _判() -> void:
	血条 = mini(血条, 100)
	_写("—— 第 %d 天，血条 %d" % [天, 血条], "#6d6455")
	_刷状态()
	if 血条 <= 0:
		_写("血条见底。你被关在家里，一直关到 18 岁。", "#b7472a")
		_结("被抓")
	elif 天 >= 目标:
		_写("第 %d 天，你 18 岁了，门开了。你走了出去。" % 天, "#2f5d50")
		_结("成年")

func _结(因: String) -> void:
	结束 = true
	结束原因 = 因
	_刷状态()
	_上报()

# ---------------- 网络 ----------------
func _请求(址: String, 法: int, 体: String = "") -> Dictionary:
	var 头 := PackedStringArray([
		"apikey: " + SB_KEY,
		"Authorization: Bearer " + SB_KEY,
		"Content-Type: application/json",
	])
	var h := HTTPRequest.new()
	add_child(h)
	var 错 := h.request(址, 头, 法, 体)
	if 错 != OK:
		h.queue_free()
		return {"ok": false, "msg": "请求发不出去"}
	var 果: Array = await h.request_completed
	h.queue_free()
	var 码: int = 果[1]
	var 文: String = (果[3] as PackedByteArray).get_string_from_utf8()
	if 码 < 200 or 码 >= 300:
		return {"ok": false, "msg": "服务器 %d" % 码}
	var 解 = JSON.parse_string(文)
	if typeof(解) != TYPE_DICTIONARY:
		return {"ok": false, "msg": "返回看不懂"}
	return 解

func _上报() -> void:
	if 已上传:
		return
	已上传 = true
	if 名字 == "":
		_写("这局成绩没上榜：还没注册玩家 ID。", "#8a5a2b")
		return
	var 体 := JSON.stringify({
		"p_name": 名字, "p_client_id": cid, "p_mode": "orig",
		"p_ending": String(结束原因).substr(0, 20),
		"p_days": 天, "p_stations": 天, "p_money": 0,
	})
	var 果 := await _请求(SB_URL + "/rest/v1/rpc/submit_score", HTTPClient.METHOD_POST, 体)
	if 果.get("ok", false):
		if 果.get("updated", false):
			_写("上榜了：%s 天（榜上只留你最好的一条）" % 果.get("days", 天), "#2f5d50")
		else:
			_写("没超过你的最好成绩，榜上不变。", "#6d6455")
	else:
		_写("这局没上榜：%s" % 果.get("msg", "网络问题"), "#8a5a2b")

# ---------------- 榜单 ----------------
func _开榜() -> void:
	面.visible = true
	名框.text = 名字
	_刷我的()
	_拉榜()

func _刷我的() -> void:
	if 名字 == "":
		我的.text = "还没登录，注册后才有玩家 ID。"
	else:
		我的.text = "已登录：%s · 玩家 ID %s" % [名字, 玩家ID]

func 榜动作(名: String) -> void:
	if 名 == "刷新榜单":
		_拉榜()
		return
	var n := 名框.text.strip_edges()
	var p := 密框.text.strip_edges()
	if n == "" or p == "":
		榜单.text = "名字和密码都要填。"
		return
	榜单.text = "正在连服务器…"
	var 体 := JSON.stringify({"p_name": n, "p_password": p})
	var 址 := SB_URL + "/rest/v1/rpc/register_player" if 名 == "注册" else SB_URL + "/rest/v1/rpc/login_player"
	var 果 := await _请求(址, HTTPClient.METHOD_POST, 体)
	if not 果.get("ok", false):
		榜单.text = "失败：%s" % 果.get("msg", "没连上")
		return
	名字 = n
	cid = 果.get("client_id", cid)
	玩家ID = 果.get("player_id", 玩家ID)
	_存()
	_刷我的()
	_刷状态()
	榜单.text = "%s成功，玩家 ID %s" % [名, 玩家ID]
	_拉榜()

func _拉榜() -> void:
	var 址 := SB_URL + "/rest/v1/scores?select=name,player_id,mode,days,stations&deleted_at=is.null&order=days.desc,stations.desc&limit=20"
	var h := HTTPRequest.new()
	add_child(h)
	var 头 := PackedStringArray(["apikey: " + SB_KEY, "Authorization: Bearer " + SB_KEY])
	h.request(址, 头)
	var 果: Array = await h.request_completed
	h.queue_free()
	var 文: String = (果[3] as PackedByteArray).get_string_from_utf8()
	var 表 = JSON.parse_string(文)
	if typeof(表) != TYPE_ARRAY:
		榜单.text = "榜单拉不下来。"
		return
	if 表.is_empty():
		榜单.text = "还没有人上榜。"
		return
	var 行 := ""
	var 名次 := 1
	for 条 in 表:
		行 += "%2d. %s（%s）  %s 天\n" % [名次, 条.get("name", "匿名"), 条.get("player_id", ""), str(条.get("days", 0))]
		名次 += 1
	榜单.text = 行
