class_name ShareManager
extends RefCounted
## Static viral-sharing helpers: compose punchy share copy for race results
## and leaderboard challenges, then hand it to the best available channel.
## On web that is the native share sheet (navigator.share — must be invoked
## synchronously from a button press so the browser still sees the user
## gesture), falling back to the clipboard everywhere else. Every path is
## silent-safe: headless and desktop runs never error and never block.

## Which channel share() actually used, so callers know whether to toast
## "Copied!" (the native share sheet is its own feedback).
enum Method { WEB_SHARE, CLIPBOARD }

const SHARE_URL: String = "https://waddlewars.ninjaconsulting.ai"

## How long the confirmation toast stays fully visible (seconds).
const TOAST_HOLD: float = 1.6

## 64x64 share glyph (linked-nodes motif) in the same hand-drawn style as the
## UITheme.ICON_* set, so share buttons read as part of the menu family.
const ICON_SHARE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M22 32 L42 17 M22 32 L42 47" stroke="#9fc4e0" stroke-width="4" fill="none" stroke-linecap="round"/>
<circle cx="16" cy="32" r="9" fill="#7fd0f7" stroke="#3d6d94" stroke-width="2"/>
<circle cx="47" cy="15" r="9" fill="#7fe08f" stroke="#3f8f55" stroke-width="2"/>
<circle cx="47" cy="49" r="9" fill="#f5c542" stroke="#c98f1b" stroke-width="2"/>
</svg>"""


## Punchy one-line share copy for a finished run. `mode` is one of "race",
## "grand_prix", "time_trial", "endless"; unknown modes read as a race.
## `time_text` is already formatted (RaceHUD.format_time or a score string)
## and may be empty (DNF) — the copy simply omits the time clause then.
static func compose_race_text(mode: String, course_name: String, position: int, time_text: String) -> String:
	var feat: String
	match mode:
		"endless":
			feat = "Scored %s on the Endless Expedition" % time_text
		"time_trial":
			feat = "Clocked %s on %s" % [time_text, course_name]
		_:
			feat = "%s on %s" % [_position_tag(position), course_name]
			if not time_text.is_empty():
				feat += " in %s" % time_text
			if mode == "grand_prix":
				feat += " (Grand Prix)"
	return "🐧 %s — think you can out-waddle me? %s" % [feat, SHARE_URL]


## Leaderboard challenge copy for the "Challenge Friends" button.
static func compose_challenge_text() -> String:
	return "Can you beat my crew on the Waddle Wars leaderboard? 🐧 %s" % SHARE_URL


static func _position_tag(position: int) -> String:
	match position:
		1:
			return "🥇 P1"
		2:
			return "🥈 P2"
		3:
			return "🥉 P3"
		_:
			return "P%d" % maxi(position, 1)


## Hands `text` to the platform share channel and reports which one ran.
## Web: navigator.share when the browser offers it (called synchronously so
## the press's user gesture is still valid; the promise result is ignored),
## else navigator.clipboard plus DisplayServer as a belt-and-braces copy.
## Desktop/headless: DisplayServer clipboard (a no-op headless). Never blocks.
static func share(text: String) -> Method:
	if OS.has_feature("web") and not GameConfig.is_headless():
		var js := ("(function(){var t=%s;" +
			"if(navigator.share){navigator.share({text:t}).catch(function(){});return \"share\";}" +
			"if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t).catch(function(){});}" +
			"return \"clipboard\";})()") % _js_quote(text)
		var used: Variant = JavaScriptBridge.eval(js, true)
		if used is String and String(used) == "share":
			return Method.WEB_SHARE
	DisplayServer.clipboard_set(text)
	return Method.CLIPBOARD


## share() plus a "Copied to clipboard!" toast on `host` when the clipboard
## path ran. The native share sheet needs no extra confirmation.
static func share_with_toast(host: Control, text: String) -> void:
	if share(text) == Method.CLIPBOARD:
		show_toast(host, "Copied to clipboard!")


## Small self-dismissing confirmation toast anchored bottom-center of `host`
## (a full-rect screen root). Replaces any toast it previously put there.
static func show_toast(host: Control, text: String) -> void:
	if GameConfig.is_headless() or host == null or not host.is_inside_tree():
		return
	if host.has_meta("_share_toast"):
		var old: Variant = host.get_meta("_share_toast")
		if old is PanelContainer and is_instance_valid(old):
			(old as PanelContainer).queue_free()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",
		UITheme.make_panel_style(Color(0.075, 0.129, 0.220, 0.96), Color(UITheme.COLOR_ACCENT, 0.6)))
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_font_override("font", UITheme.bold_font())
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	panel.add_child(label)
	host.add_child(panel)
	host.set_meta("_share_toast", panel)
	panel.reset_size()
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_KEEP_SIZE, 72)
	panel.modulate.a = 0.0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(TOAST_HOLD)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)


## Themed button with the share glyph; falls back to the plain themed button
## when the SVG module is unavailable (headless), like make_menu_button.
static func make_share_button(text: String, size: Vector2 = Vector2(240, 56), font_size: int = 24) -> Button:
	var button := UITheme.make_button(text, size, font_size)
	var texture := UITheme.make_icon(ICON_SHARE, 1.0)
	if texture != null:
		button.icon = texture
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 26)
		button.add_theme_constant_override("h_separation", 10)
	return button


static func _js_quote(s: String) -> String:
	return "\"%s\"" % s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
