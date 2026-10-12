extends Node
## Execute only through run_tests.sh's isolated project/user directory.
## No network or live account. Local commerce stays local; earned progress syncs.

class OnlineFixture extends "res://scripts/network/leaderboard_client.gd":
	var requests: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
	func _dispatch_request(method: String, url: String, body: String, _cb: Callable) -> void:
		requests.append({"method": method, "url": url, "body": body})

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var original := SaveManager.data.duplicate(true)
	_test_snapshot()
	_test_upload()
	_test_cloud_adoption()
	SaveManager.data = original
	SaveManager.save_now()
	CommerceClient._reload_cache()
	print("[cloud_save_privacy] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _cache() -> Dictionary:
	return {"last_account": "synthetic-local-a", "accounts": {
		"synthetic-local-a": {"product_ids": ["cozy_expedition"], "verified_at": "local-verified"},
		"synthetic-local-b": {"product_ids": [], "verified_at": "other-local-verified"},
	}}


func _progress() -> Dictionary:
	var progress := SaveManager.default_save()
	progress["fish"] = 42
	progress["xp"] = 125
	progress["unlocked_cosmetics"] = ["body_classic", "hat_beanie"]
	progress["stats"]["races_finished"] = 3
	progress["best_times"] = {"glacier": 65.25}
	progress["runner"] = {"best_distance": 321.0, "mission_index": 2}
	return progress


func _test_snapshot() -> void:
	var local := _progress()
	local["commerce"] = _cache()
	var before := local.duplicate(true)
	var snapshot := SaveManager.cloud_progress_snapshot(local)
	_check("snapshot_excludes_all_account_purchase_caches", not snapshot.has("commerce"))
	_check("snapshot_keeps_earned_currency_xp_and_cosmetics", snapshot["fish"] == 42
		and snapshot["xp"] == 125 and snapshot["unlocked_cosmetics"] == local["unlocked_cosmetics"])
	_check("snapshot_keeps_runner_and_race_progress", snapshot["runner"] == local["runner"]
		and snapshot["best_times"] == local["best_times"] and snapshot["stats"] == local["stats"])
	_check("snapshot_does_not_mutate_local_data", local == before)
	snapshot["stats"]["races_finished"] = 999
	snapshot["unlocked_cosmetics"].append("synthetic-added")
	_check("snapshot_nested_values_are_detached", local == before)
	var old_save := {"fish": 4, "unknown_future_progress": {"value": 3}}
	_check("snapshot_preserves_old_and_future_progress_fields",
		SaveManager.cloud_progress_snapshot(old_save) == old_save)


func _test_upload() -> void:
	SaveManager.data = _progress()
	SaveManager.data["commerce"] = _cache()
	SaveManager.data["_cloud_owner"] = "synthetic-local-b".sha256_text()
	var before := SaveManager.data.duplicate(true)
	var online := OnlineFixture.new()
	add_child(online)
	online._token = "synthetic-token"
	online.signed_in = true
	online._synced_this_session = true
	online._save_revision = "absent"
	online._auth_owner_id = "synthetic-local-b"
	online._push_save_now()
	_check("production_upload_path_issues_one_put", online.requests.size() == 1
		and online.requests[0]["method"] == "PUT")
	var envelope: Dictionary = JSON.parse_string(online.requests[0]["body"])
	var body: Dictionary = envelope["progress"]
	_check("production_upload_body_has_no_commerce", not body.has("commerce"))
	_check("production_upload_keeps_earned_progress", body["fish"] == 42
		and body["stats"]["races_finished"] == 3 and body["runner"]["best_distance"] == 321)
	_check("production_upload_leaves_offline_cache_intact", SaveManager.data == before)
	online.free()


func _test_cloud_adoption() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager.data["commerce"] = _cache()
	var local_cache: Dictionary = SaveManager.data["commerce"].duplicate(true)
	var remote := _progress()
	remote["commerce"] = {"last_account": "synthetic-foreign", "accounts": {
		"synthetic-local-a": {"product_ids": ["aurora_celebration"]},
		"synthetic-foreign": {"product_ids": ["research_crew"]},
	}}
	var before := remote.duplicate(true)
	SaveManager.adopt_cloud_save(remote)
	_check("adoption_keeps_local_verified_cache_only", SaveManager.data["commerce"] == local_cache)
	_check("adoption_rejects_foreign_account_cache", not SaveManager.data["commerce"]["accounts"].has("synthetic-foreign"))
	_check("adoption_restores_earned_currency_and_cosmetics", SaveManager.data["fish"] == 42
		and SaveManager.data["unlocked_cosmetics"] == remote["unlocked_cosmetics"])
	_check("adoption_restores_race_and_runner_progress", SaveManager.data["best_times"] == remote["best_times"]
		and SaveManager.data["runner"] == remote["runner"])
	_check("adoption_does_not_mutate_remote_payload", remote == before)
	_check("commerce_reload_preserves_local_offline_grant", CommerceClient.owns_product("cozy_expedition"))
	_check("cloud_cache_cannot_create_offline_purchase_grant", not CommerceClient.owns_product("aurora_celebration"))
	var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	_check("local_persistence_preserves_only_local_cache", stored is Dictionary
		and stored["commerce"] == local_cache)
	SaveManager.data = SaveManager.default_save()
	SaveManager.adopt_cloud_save(remote)
	_check("fresh_device_never_imports_legacy_commerce", not SaveManager.data.has("commerce"))
	_check("fresh_device_still_restores_earned_progress", SaveManager.data["fish"] == 42
		and SaveManager.data["runner"] == remote["runner"])
	_check("fresh_device_requires_server_purchase_refresh", not CommerceClient.owns_product("cozy_expedition")
		and not CommerceClient.owns_product("research_crew"))


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error("[cloud_save_privacy] FAIL: " + label)
