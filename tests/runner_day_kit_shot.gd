extends "res://tests/runner_golden_shot.gd"
## Real RunnerGame golden-shot harness with the staged DAY fragment injected
## through the production RunnerArtSet/ArtCatalog seam. This remains separate
## from the release catalog until visual and performance approval.
##
##   godot --path . --rendering-method gl_compatibility \
##     res://tests/runner_day_kit_shot.tscn -- \
##     out=/tmp/day_kit_portrait.png w=540 h=960 touch=1

var _day_kit_injected: bool = false
var _day_kit_verified: bool = false


func _ready() -> void:
	_out_path = "qa_shots/runner/day_kit.png"
	super._ready()


func _process(delta: float) -> void:
	if not _day_kit_injected and _game != null and _game.build_finished:
		_day_kit_injected = true
		var art_set := load("res://tests/fixtures/art/runner_day_review_art_set.tres") as RunnerArtSet
		var catalog := ArtCatalog.new()
		catalog.manifest_path = "res://tests/fixtures/art/runner_day_kit_catalog.json"
		var load_error := catalog.reload_manifest()
		if art_set == null or load_error != OK:
			_save_failed = true
			push_error("runner_day_kit_shot: catalog setup failed %s" % catalog.manifest_errors())
		else:
			_game.track.configure_art(art_set, catalog)
			print("[runner_day_kit_shot] injected staged catalog assets=%d" %
					catalog.asset_ids("runner_day").size())
	super._process(delta)
	if _started and _day_kit_injected and not _day_kit_verified:
		_day_kit_verified = true
		var status := _game.track.authored_day_kit_status()
		if not bool(status.get("active", false)):
			_save_failed = true
			push_error("runner_day_kit_shot: incomplete kit %s" % status)
		else:
			print("[runner_day_kit_shot] kit active %s" % status)
