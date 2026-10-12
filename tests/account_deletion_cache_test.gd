extends Node
## Run only through run_tests.sh's isolated project/user identity. No network.

class SaveFixture extends "res://scripts/save/save_manager.gd":
	var fail_write_path: String = ""
	var fail_replace_path: String = ""
	var fail_read_path: String = ""
	var fail_read_after_replace_path: String = ""
	var journal_reads: int = 0
	var journal_writes: Array[Dictionary] = []
	var journal_replaces: int = 0
	func _ready() -> void:
		set_process(false)
	func _write_json_file(path: String, value: Dictionary) -> bool:
		if path == ACCOUNT_DELETION_TMP_PATH:
			journal_writes.append(value.duplicate(true))
		if path == fail_write_path:
			return false
		return super._write_json_file(path, value)
	func _replace_file(source: String, destination: String) -> bool:
		if destination == fail_replace_path:
			return false
		var replaced := super._replace_file(source, destination)
		if replaced and destination == ACCOUNT_DELETION_PATH:
			journal_replaces += 1
		if replaced and destination == fail_read_after_replace_path:
			fail_read_path = destination
		return replaced
	func _read_json_checked(path: String) -> Dictionary:
		if path == ACCOUNT_DELETION_PATH:
			journal_reads += 1
		if path == fail_read_path:
			return {"ok": false, "data": {}}
		return super._read_json_checked(path)

const OWNER_A: String = "synthetic-retired-a"
const OWNER_B: String = "synthetic-active-b"
const RECEIPT_OWNER_A: String = "synthetic-receipt-a"
const RECEIPT_OWNER_B: String = "synthetic-receipt-b"
const RECEIPT_A: String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const RECEIPT_B: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var custom := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
			or not custom.begins_with("waddle-wars-tests-"):
		push_error("account_deletion_cache: isolated run_tests.sh identity required")
		get_tree().quit(2)
		return
	var save := SaveFixture.new()
	add_child(save)
	save.load_save()
	_test_journal_transitions(save)
	_test_owner_scoped_cleanup(save)
	_test_recovery_and_writes(save)
	_test_cleanup_failures(save)
	_test_cached_journal_getters(save)
	_test_unavailable_journal(save)
	_test_receipt_journal(save)
	_test_receipt_corruption_and_legacy(save)
	save.free()
	print("[account_deletion_cache] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _progress(fish: int = 42, last_owner: String = OWNER_A) -> Dictionary:
	var result := SaveManager.default_save()
	result["fish"] = fish
	result["xp"] = 125
	result["unlocked_cosmetics"] = ["body_classic", "hat_beanie"]
	result["stats"]["races_finished"] = 3
	result["best_times"] = {"glacier": 65.25}
	result["runner"] = {"best_distance": 321.0, "mission_index": 2}
	result["future_progress"] = {"keep": true}
	result["commerce"] = {"last_account": last_owner, "future_cache_field": "keep", "accounts": {
		OWNER_A: {"product_ids": ["cozy_expedition"], "verified_at": "old"},
		OWNER_B: {"product_ids": ["research_crew"], "verified_at": "other"},
	}}
	return result


func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_check("fixture_can_write_" + path, false)
		return
	file.store_string(JSON.stringify(value))
	file.close()


func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _clean(value: Dictionary) -> bool:
	var commerce: Dictionary = value.get("commerce", {})
	return not commerce.get("accounts", {}).has(OWNER_A) and commerce.get("last_account", "") != OWNER_A


func _other_cache_preserved(value: Dictionary) -> bool:
	var commerce: Dictionary = value.get("commerce", {})
	return commerce.get("accounts", {}).get(OWNER_B) == _progress()["commerce"]["accounts"][OWNER_B] \
		and commerce.get("future_cache_field") == "keep"


func _test_journal_transitions(save: SaveFixture) -> void:
	_check("fresh_journal_available", save.account_deletion_journal_available())
	_check("fresh_owner_has_no_deletion", save.account_deletion_state(OWNER_A).is_empty())
	_check("invalid_owner_and_state_rejected", not save.set_account_deletion_state("", "pending")
		and not save.set_account_deletion_state(OWNER_A, "invalid"))
	save.fail_write_path = SaveManager.ACCOUNT_DELETION_TMP_PATH
	_check("failed_journal_write_not_reported_durable", not save.set_account_deletion_state(OWNER_A, "pending")
		and save.account_deletion_state(OWNER_A).is_empty())
	save.fail_write_path = ""
	save.fail_read_path = SaveManager.ACCOUNT_DELETION_TMP_PATH
	_check("failed_staged_readback_does_not_commit_marker", not save.set_account_deletion_state(OWNER_A, "pending")
		and save.account_deletion_state(OWNER_A).is_empty())
	save.fail_read_path = ""
	_check("pending_marker_durable", save.set_account_deletion_state(OWNER_A, "pending")
		and _read(SaveManager.ACCOUNT_DELETION_PATH)["accounts"][OWNER_A] == "pending")
	var restarted := SaveFixture.new()
	add_child(restarted)
	_check("pending_survives_restart", restarted.account_deletion_state(OWNER_A) == "pending")
	restarted.free()
	_check("definitive_failure_can_clear_pending", save.set_account_deletion_state(OWNER_A, "")
		and save.account_deletion_state(OWNER_A).is_empty())
	_check("pending_can_be_reestablished", save.set_account_deletion_state(OWNER_A, "pending"))
	save.data = _progress()
	var before := save.data.duplicate(true)
	_check("pending_is_not_authority_to_erase", not save.erase_account_purchase_cache(OWNER_A) and save.data == before)
	# A failed ordinary backup rename leaves a complete active-account snapshot
	# in its staging file. It must join later retirement cleanup.
	_write(SaveManager.SAVE_PATH, _progress())
	_write(SaveManager.SAVE_BACKUP_PATH, _progress(7))
	save.fail_replace_path = SaveManager.SAVE_BACKUP_PATH
	save.save_now()
	_check("failed_backup_rename_leaves_active_account_staging", save._dirty
		and not _clean(_read(SaveManager.SAVE_BACKUP_TMP_PATH)))
	save.fail_replace_path = ""
	save.fail_write_path = SaveManager.SAVE_BACKUP_TMP_PATH
	save.save_now()
	_check("failed_backup_write_keeps_existing_staging_pending", save._dirty
		and not _clean(_read(SaveManager.SAVE_BACKUP_TMP_PATH)))
	save.fail_write_path = ""
	# Another owner's prior retirement staging legitimately retains still-active
	# A. Its own valid progress must survive until A is subsequently retired.
	var first_retirement_owner := "synthetic-first-retirement"
	_check("independent_first_retirement_durable", save.set_account_deletion_state(first_retirement_owner, "retired"))
	_write(SaveManager.SAVE_RETIRE_TMP_PATH, _progress(5))
	var staged_fish := 20
	for path: String in SaveManager.LEGACY_RETIRE_TMP_PATHS:
		_write(path, _progress(staged_fish))
		staged_fish += 1
	_check("first_retirement_preserves_active_account_staging_and_progress", save.erase_account_purchase_cache(first_retirement_owner)
		and not _clean(_read(SaveManager.SAVE_RETIRE_TMP_PATH))
		and _read(SaveManager.SAVE_RETIRE_TMP_PATH)["fish"] == 5 and save.data == before)
	_check("retirement_commits_before_cache_erase", save.set_account_deletion_state(OWNER_A, "retired")
		and save.account_deletion_state(OWNER_A) == "retired" and save.data == before)
	_check("retired_marker_cannot_be_cleared_or_downgraded", not save.set_account_deletion_state(OWNER_A, "")
		and not save.set_account_deletion_state(OWNER_A, "pending")
		and save.account_deletion_state(OWNER_A) == "retired")
	_check("retired_transition_idempotent", save.set_account_deletion_state(OWNER_A, "retired"))
	_check("other_owner_pending_independent", save.set_account_deletion_state(OWNER_B, "pending")
		and save.account_deletion_state(OWNER_A) == "retired")
	_check("other_owner_pending_can_clear", save.set_account_deletion_state(OWNER_B, ""))
	var readback_owner := "synthetic-retirement-readback"
	_check("readback_fixture_pending_durable", save.set_account_deletion_state(readback_owner, "pending"))
	save.fail_read_after_replace_path = SaveManager.ACCOUNT_DELETION_PATH
	_check("failed_final_journal_readback_not_reported_success", not save.set_account_deletion_state(readback_owner, "retired")
		and save.account_deletion_state(readback_owner) == "unavailable"
		and _read(SaveManager.ACCOUNT_DELETION_PATH)["accounts"][readback_owner] == "retired")
	save.fail_read_path = ""
	save.fail_read_after_replace_path = ""
	_check("final_readback_retry_recovers_durable_retirement", save.refresh_account_deletion_journal()
		and save.account_deletion_state(readback_owner) == "retired"
		and not save.set_account_deletion_state(readback_owner, ""))


func _test_owner_scoped_cleanup(save: SaveFixture) -> void:
	save.data = _progress()
	_write(SaveManager.SAVE_PATH, _progress())
	_write(SaveManager.SAVE_BACKUP_PATH, _progress(7))
	_write(SaveManager.SAVE_TMP_PATH, _progress(3))
	var uploaded: Array[int] = [0]
	save.save_written.connect(func() -> void: uploaded[0] += 1)
	_check("confirmed_retirement_scrubs_all_copies", save.erase_account_purchase_cache(OWNER_A))
	_check("memory_retired_grants_removed", _clean(save.data))
	_check("memory_other_owner_cache_and_future_fields_preserved", _other_cache_preserved(save.data))
	var snapshot := SaveManager.cloud_progress_snapshot(save.data)
	_check("earned_and_guest_progress_preserved", snapshot == SaveManager.cloud_progress_snapshot(_progress()))
	for path: String in [SaveManager.SAVE_PATH, SaveManager.SAVE_BACKUP_PATH, SaveManager.SAVE_TMP_PATH]:
		var stored := _read(path)
		_check("retired_cache_removed_from_" + path, _clean(stored) and _other_cache_preserved(stored))
	_check("backup_and_interrupted_write_keep_own_progress", _read(SaveManager.SAVE_BACKUP_PATH)["fish"] == 7
		and _read(SaveManager.SAVE_TMP_PATH)["fish"] == 3)
	for path: String in [SaveManager.SAVE_BACKUP_TMP_PATH, SaveManager.SAVE_RETIRE_TMP_PATH]:
		_check("retired_cache_removed_from_owned_staging_" + path, _clean(_read(path))
			and _other_cache_preserved(_read(path)))
	_check("fixed_retirement_staging_keeps_own_progress", _read(SaveManager.SAVE_RETIRE_TMP_PATH)["fish"] == 5)
	var staged_fish := 20
	for path: String in SaveManager.LEGACY_RETIRE_TMP_PATHS:
		_check("legacy_retirement_stage_scrubbed_without_progress_loss_" + path, _clean(_read(path))
			and _other_cache_preserved(_read(path)) and _read(path)["fish"] == staged_fish)
		staged_fish += 1
	_check("cleanup_never_announces_cloud_upload", uploaded[0] == 0)
	_check("journal_not_in_cloud_or_save", not snapshot.has("account_deletion")
		and not _read(SaveManager.SAVE_PATH).has("account_deletion")
		and _read(SaveManager.ACCOUNT_DELETION_PATH).keys().size() == 2)
	save.data = _progress(42, OWNER_B)
	_check("other_offline_pointer_survives_deletion", save.erase_account_purchase_cache(OWNER_A)
		and save.data["commerce"]["last_account"] == OWNER_B)


func _test_recovery_and_writes(save: SaveFixture) -> void:
	# Model a crash after durable retirement but before local cache cleanup.
	_write(SaveManager.SAVE_PATH, _progress(18))
	_write(SaveManager.SAVE_BACKUP_PATH, _progress(7))
	_write(SaveManager.SAVE_TMP_PATH, _progress(3))
	_write(SaveManager.SAVE_BACKUP_TMP_PATH, _progress(6))
	_write(SaveManager.SAVE_RETIRE_TMP_PATH, _progress(5))
	var restarted := SaveFixture.new()
	add_child(restarted)
	restarted.load_save()
	_check("disk_load_fences_and_repairs_interrupted_retirement", restarted.account_deletion_state(OWNER_A) == "retired"
		and _clean(restarted.data) and restarted.data["fish"] == 18)
	_check("disk_load_scrubs_all_recovery_copies", _clean(_read(SaveManager.SAVE_PATH))
		and _clean(_read(SaveManager.SAVE_BACKUP_PATH)) and _clean(_read(SaveManager.SAVE_TMP_PATH)))
	_check("disk_load_scrubs_backup_and_fixed_staging", _clean(_read(SaveManager.SAVE_BACKUP_TMP_PATH))
		and _clean(_read(SaveManager.SAVE_RETIRE_TMP_PATH))
		and _read(SaveManager.SAVE_BACKUP_TMP_PATH)["fish"] == 6
		and _read(SaveManager.SAVE_RETIRE_TMP_PATH)["fish"] == 5)
	# Make main unreadable; an older valid backup still cannot restore grants.
	_write(SaveManager.SAVE_PATH, {"commerce": _progress()["commerce"]})
	var file := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
	file.store_string("broken save")
	file.close()
	_write(SaveManager.SAVE_BACKUP_PATH, _progress(11))
	restarted.load_save()
	_check("backup_recovery_cannot_resurrect_retired_cache", _clean(restarted.data)
		and restarted.data["fish"] == 11 and _other_cache_preserved(restarted.data))
	restarted.save_now()
	_check("ordinary_write_keeps_valid_backup_when_main_corrupt", _read(SaveManager.SAVE_BACKUP_PATH)["fish"] == 11
		and _clean(_read(SaveManager.SAVE_PATH)))
	# Stale cache reinserted by an old consumer cannot reach normal persistence.
	_write(SaveManager.SAVE_PATH, _progress(19))
	restarted.data = _progress(88)
	restarted.save_now()
	_check("ordinary_write_sanitizes_memory_and_main", _clean(restarted.data)
		and _clean(_read(SaveManager.SAVE_PATH)) and _read(SaveManager.SAVE_PATH)["fish"] == 88)
	_check("backup_rotation_sanitizes_old_main", _clean(_read(SaveManager.SAVE_BACKUP_PATH))
		and _read(SaveManager.SAVE_BACKUP_PATH)["fish"] == 19)
	restarted.data = _progress()
	var remote := _progress(90)
	remote["commerce"]["accounts"][OWNER_B]["product_ids"] = ["aurora_celebration"]
	restarted.adopt_cloud_save(remote)
	_check("cloud_adoption_preserves_progress_but_not_retired_or_foreign_grants", restarted.data["fish"] == 90
		and _clean(restarted.data) and _other_cache_preserved(restarted.data))
	_check("cloud_adoption_keeps_journal_durable", restarted.account_deletion_state(OWNER_A) == "retired")
	restarted.free()
	save.load_save()


func _test_cleanup_failures(save: SaveFixture) -> void:
	save.data = _progress()
	_write(SaveManager.SAVE_PATH, _progress())
	_write(SaveManager.SAVE_BACKUP_PATH, _progress(7))
	_write(SaveManager.SAVE_TMP_PATH, _progress(3))
	save.fail_replace_path = SaveManager.SAVE_BACKUP_PATH
	_check("partial_cleanup_not_reported_complete", not save.erase_account_purchase_cache(OWNER_A)
		and save._dirty and _clean(save.data) and _clean(_read(SaveManager.SAVE_PATH))
		and not _clean(_read(SaveManager.SAVE_BACKUP_PATH)))
	_check("partial_cleanup_retains_durable_retired_fence", save.account_deletion_state(OWNER_A) == "retired")
	save.fail_replace_path = ""
	_check("explicit_retry_repairs_partial_cleanup", save.erase_account_purchase_cache(OWNER_A)
		and not save._dirty and _clean(_read(SaveManager.SAVE_BACKUP_PATH)))
	_write(SaveManager.SAVE_PATH, _progress())
	save.fail_replace_path = SaveManager.SAVE_PATH
	_check("main_rename_failure_honest_and_recoverable", not save.erase_account_purchase_cache(OWNER_A)
		and save._dirty and save.account_deletion_state(OWNER_A) == "retired"
		and not _clean(_read(SaveManager.SAVE_PATH)))
	save.fail_replace_path = ""
	_check("main_failure_retry_preserves_gameplay", save.erase_account_purchase_cache(OWNER_A)
		and _clean(_read(SaveManager.SAVE_PATH)) and save.data["fish"] == 42)
	_write(SaveManager.SAVE_BACKUP_PATH, _progress(7))
	save.fail_read_path = SaveManager.SAVE_BACKUP_PATH
	_check("cleanup_read_failure_not_reported_complete", not save.erase_account_purchase_cache(OWNER_A)
		and save._dirty and save.account_deletion_state(OWNER_A) == "retired")
	save.fail_read_path = ""
	_check("read_failure_retry_repairs_remaining_copy", save.erase_account_purchase_cache(OWNER_A)
		and _clean(_read(SaveManager.SAVE_BACKUP_PATH)))
	save.fail_read_after_replace_path = SaveManager.SAVE_PATH
	_check("failed_final_save_readback_not_reported_complete", not save.erase_account_purchase_cache(OWNER_A)
		and save._dirty and _clean(_read(SaveManager.SAVE_PATH)))
	save.fail_read_after_replace_path = ""
	save.fail_read_path = ""
	_check("final_save_readback_retry_confirms_cleanup", save.erase_account_purchase_cache(OWNER_A) and not save._dirty)


func _test_unavailable_journal(save: SaveFixture) -> void:
	var valid_journal := _read(SaveManager.ACCOUNT_DELETION_PATH)
	_write(SaveManager.ACCOUNT_DELETION_PATH, {"version": 1, "accounts": {OWNER_A: "unknown"}})
	save.data = _progress()
	var before := _read(SaveManager.SAVE_PATH)
	_check("explicit_refresh_detects_corrupt_journal", not save.refresh_account_deletion_journal())
	_check("corrupt_journal_fences_account_consumers", not save.account_deletion_journal_available()
		and save.account_deletion_state(OWNER_A) == "unavailable" and save.get_value("commerce", {}) == {})
	_check("corrupt_journal_never_authorizes_mutation", not save.set_account_deletion_state(OWNER_A, "pending")
		and not save.erase_account_purchase_cache(OWNER_A))
	save.save_now()
	_check("corrupt_journal_blocks_save_without_losing_data", save._dirty
		and _read(SaveManager.SAVE_PATH) == before and _other_cache_preserved(save.data))
	_write(SaveManager.ACCOUNT_DELETION_PATH, valid_journal)
	_check("journal_repair_restores_known_retirement", save.refresh_account_deletion_journal()
		and save.account_deletion_journal_available()
		and save.account_deletion_state(OWNER_A) == "retired" and save.erase_account_purchase_cache(OWNER_A))
	_check("repaired_journal_preserves_other_account", _other_cache_preserved(save.data))
	_write(SaveManager.ACCOUNT_DELETION_PATH, {"version": 1, "accounts": {}})
	_check("journal_rollback_cannot_clear_known_retirement", not save.refresh_account_deletion_journal()
		and save.account_deletion_state(OWNER_A) == "unavailable")
	_write(SaveManager.ACCOUNT_DELETION_PATH, valid_journal)
	_check("complete_journal_repair_reopens_other_account", save.refresh_account_deletion_journal()
		and save.account_deletion_state(OWNER_B).is_empty())


func _test_cached_journal_getters(save: SaveFixture) -> void:
	var reads := save.journal_reads
	for index: int in 1000:
		save.account_deletion_journal_available()
		save.account_deletion_state(OWNER_A)
		save.account_deletion_state(OWNER_B)
		save.account_deletion_receipt(OWNER_A)
		save.account_deletion_receipt(OWNER_B)
		save.account_deletion_recovery_subject()
		save.get_value("commerce", {})
	_check("ownership_and_auth_getters_do_no_disk_reads", save.journal_reads == reads)
	var restarted := SaveFixture.new()
	add_child(restarted)
	_check("new_consumer_lazily_loads_journal_once", restarted.account_deletion_state(OWNER_A) == "retired"
		and restarted.account_deletion_journal_available()
		and restarted.account_deletion_state(OWNER_B).is_empty() and restarted.journal_reads == 1)
	restarted.free()


func _test_receipt_journal(save: SaveFixture) -> void:
	var before := save.data.duplicate(true)
	var writes := save.journal_writes.size()
	for value: String in ["", "a".repeat(63), "a".repeat(65), "A".repeat(64), "g".repeat(64),
			"é".repeat(64), "a".repeat(63) + "\n", "a".repeat(63) + " "]:
		_check("invalid_recovery_receipt_refused", not save.begin_account_deletion(RECEIPT_OWNER_A, value))
	_check("empty_recovery_owner_refused", not save.begin_account_deletion("", RECEIPT_A))
	_check("invalid_receipts_never_write_or_change_save", save.journal_writes.size() == writes and save.data == before)
	save.fail_write_path = SaveManager.ACCOUNT_DELETION_TMP_PATH
	_check("receipt_begin_write_failure_not_durable", not save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_A)
		and save.account_deletion_state(RECEIPT_OWNER_A).is_empty() and save.account_deletion_receipt(RECEIPT_OWNER_A).is_empty())
	save.fail_write_path = ""
	save.fail_read_path = SaveManager.ACCOUNT_DELETION_TMP_PATH
	_check("receipt_begin_staged_read_failure_not_durable", not save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_A)
		and save.account_deletion_state(RECEIPT_OWNER_A).is_empty())
	save.fail_read_path = ""
	save.fail_replace_path = SaveManager.ACCOUNT_DELETION_PATH
	_check("receipt_begin_rename_failure_keeps_prior_journal", not save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_A)
		and save.account_deletion_receipt(RECEIPT_OWNER_A).is_empty()
		and not _read(SaveManager.ACCOUNT_DELETION_PATH).get("accounts", {}).has(RECEIPT_OWNER_A))
	save.fail_replace_path = ""
	writes = save.journal_writes.size()
	var replaces := save.journal_replaces
	_check("receipt_begin_pending_and_secret_one_atomic_commit", save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_A)
		and save.journal_writes.size() == writes + 1 and save.journal_replaces == replaces + 1)
	var committed: Dictionary = save.journal_writes.back()
	var normalized_commit: Dictionary = JSON.parse_string(JSON.stringify(committed))
	_check("single_commit_contains_pending_receipt_and_owner", committed["accounts"][RECEIPT_OWNER_A] == "pending"
		and committed["receipts"][RECEIPT_OWNER_A] == RECEIPT_A and committed["recovery_owner"] == RECEIPT_OWNER_A)
	_check("receipt_begin_readback_private_and_no_save_mutation", _read(SaveManager.ACCOUNT_DELETION_PATH) == normalized_commit
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A
		and save.account_deletion_recovery_subject() == RECEIPT_OWNER_A and save.data == before)
	writes = save.journal_writes.size()
	_check("receipt_retry_same_pending_is_idempotent", save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_A)
		and save.journal_writes.size() == writes)
	_check("receipt_retry_cannot_replace_pending_secret", not save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_B)
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A and save.journal_writes.size() == writes)
	var restarted := SaveFixture.new()
	add_child(restarted)
	_check("receipt_pending_survives_crash_restart", restarted.account_deletion_state(RECEIPT_OWNER_A) == "pending"
		and restarted.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A
		and restarted.account_deletion_recovery_subject() == RECEIPT_OWNER_A)
	var reads := restarted.journal_reads
	for index: int in 1000:
		restarted.account_deletion_receipt(RECEIPT_OWNER_A)
		restarted.account_deletion_recovery_subject()
	_check("receipt_recovery_getters_never_poll_disk", restarted.journal_reads == reads)
	restarted.free()
	_check("second_account_receipt_isolated_and_most_recent", save.begin_account_deletion(RECEIPT_OWNER_B, RECEIPT_B)
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A
		and save.account_deletion_receipt(RECEIPT_OWNER_B) == RECEIPT_B
		and save.account_deletion_recovery_subject() == RECEIPT_OWNER_B)
	_check("retirement_preserves_private_receipt_for_server_checks", save.set_account_deletion_state(RECEIPT_OWNER_A, "retired")
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A
		and save.account_deletion_recovery_subject() == RECEIPT_OWNER_B)
	_check("retired_begin_cannot_replace_or_clear_receipt", not save.begin_account_deletion(RECEIPT_OWNER_A, RECEIPT_B)
		and not save.set_account_deletion_state(RECEIPT_OWNER_A, "") and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A)
	save.data = _progress()
	save.data["commerce"]["accounts"][RECEIPT_OWNER_A] = {"product_ids": ["aurora_celebration"]}
	_write(SaveManager.SAVE_PATH, save.data)
	_write(SaveManager.SAVE_BACKUP_PATH, save.data)
	_check("retired_cache_erasure_keeps_recovery_secret", save.erase_account_purchase_cache(RECEIPT_OWNER_A)
		and not save.data["commerce"]["accounts"].has(RECEIPT_OWNER_A)
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A
		and save.account_deletion_receipt(RECEIPT_OWNER_B) == RECEIPT_B and save.data["fish"] == 42)
	var injected := save.data.duplicate(true)
	injected["account_deletion"] = {"receipts": {RECEIPT_OWNER_A: RECEIPT_A}}
	injected["account_deletion_receipt"] = RECEIPT_A
	injected["account_deletion_receipts"] = {RECEIPT_OWNER_B: RECEIPT_B}
	injected["account_deletion_recovery_owner"] = RECEIPT_OWNER_B
	var progress := SaveManager.cloud_progress_snapshot(injected)
	_check("receipt_fields_excluded_from_cloud_snapshot", JSON.stringify(progress).find(RECEIPT_A) < 0
		and JSON.stringify(progress).find(RECEIPT_B) < 0 and not progress.has("account_deletion_recovery_owner"))
	save.data = injected
	save.save_now()
	_check("receipt_fields_excluded_from_normal_save_memory", JSON.stringify(save.data).find(RECEIPT_A) < 0
		and JSON.stringify(save.data).find(RECEIPT_B) < 0)
	for path: String in [SaveManager.SAVE_PATH, SaveManager.SAVE_BACKUP_PATH, SaveManager.SAVE_TMP_PATH,
			SaveManager.SAVE_BACKUP_TMP_PATH, SaveManager.SAVE_RETIRE_TMP_PATH]:
		_check("receipt_not_echoed_in_owned_save_copy_" + path, not FileAccess.file_exists(path)
			or (FileAccess.get_file_as_string(path).find(RECEIPT_A) < 0 and FileAccess.get_file_as_string(path).find(RECEIPT_B) < 0))
	save.adopt_cloud_save(injected)
	_check("cloud_adoption_cannot_import_receipt_secrets", JSON.stringify(save.data).find(RECEIPT_A) < 0
		and JSON.stringify(save.data).find(RECEIPT_B) < 0 and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A)
	_check("authenticated_negative_clears_pending_receipt_and_pointer", save.set_account_deletion_state(RECEIPT_OWNER_B, "")
		and save.account_deletion_receipt(RECEIPT_OWNER_B).is_empty()
		and save.account_deletion_recovery_subject().is_empty()
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A)
	_check("cleared_pointer_does_not_guess_remaining_retired_owner", _read(SaveManager.ACCOUNT_DELETION_PATH).get("receipts", {}).has(RECEIPT_OWNER_A)
		and not _read(SaveManager.ACCOUNT_DELETION_PATH).has("recovery_owner"))
	# A completed rename is a durable fence even when its final readback fails.
	save.fail_read_after_replace_path = SaveManager.ACCOUNT_DELETION_PATH
	_check("receipt_begin_final_readback_failure_not_reported_success", not save.begin_account_deletion(RECEIPT_OWNER_B, RECEIPT_B)
		and save.account_deletion_state(RECEIPT_OWNER_B) == "unavailable"
		and save.account_deletion_receipt(RECEIPT_OWNER_B).is_empty() and save.account_deletion_recovery_subject().is_empty())
	_check("failed_readback_disk_has_pending_and_receipt_together", _read(SaveManager.ACCOUNT_DELETION_PATH)["accounts"][RECEIPT_OWNER_B] == "pending"
		and _read(SaveManager.ACCOUNT_DELETION_PATH)["receipts"][RECEIPT_OWNER_B] == RECEIPT_B)
	save.fail_read_after_replace_path = ""
	save.fail_read_path = ""
	_check("receipt_readback_retry_recovers_committed_fence", save.refresh_account_deletion_journal()
		and save.account_deletion_receipt(RECEIPT_OWNER_B) == RECEIPT_B
		and save.account_deletion_recovery_subject() == RECEIPT_OWNER_B)
	save.fail_read_after_replace_path = SaveManager.ACCOUNT_DELETION_PATH
	_check("pending_clear_readback_failure_not_reported_success", not save.set_account_deletion_state(RECEIPT_OWNER_B, "")
		and save.account_deletion_state(RECEIPT_OWNER_B) == "unavailable")
	save.fail_read_after_replace_path = ""
	save.fail_read_path = ""
	_check("authorized_clear_exact_readback_can_recover", save.refresh_account_deletion_journal()
		and save.account_deletion_receipt(RECEIPT_OWNER_B).is_empty()
		and save.account_deletion_recovery_subject().is_empty())


func _test_receipt_corruption_and_legacy(save: SaveFixture) -> void:
	_check("pending_receipt_corruption_fixture_committed", save.begin_account_deletion(RECEIPT_OWNER_B, RECEIPT_B))
	var valid := _read(SaveManager.ACCOUNT_DELETION_PATH)
	var invalids: Array[Dictionary] = []
	var value := valid.duplicate(true)
	value["receipts"] = []
	invalids.append(value)
	value = valid.duplicate(true)
	value["receipts"][RECEIPT_OWNER_A] = "A".repeat(64)
	invalids.append(value)
	value = valid.duplicate(true)
	value["receipts"]["synthetic-orphan"] = RECEIPT_B
	invalids.append(value)
	value = valid.duplicate(true)
	value["recovery_owner"] = "synthetic-orphan"
	invalids.append(value)
	value = valid.duplicate(true)
	value["recovery_owner"] = 17
	invalids.append(value)
	value = valid.duplicate(true)
	value["receipts"][RECEIPT_OWNER_B] = RECEIPT_A
	invalids.append(value)
	value = valid.duplicate(true)
	value["accounts"].erase(RECEIPT_OWNER_B)
	value["receipts"].erase(RECEIPT_OWNER_B)
	value.erase("recovery_owner")
	invalids.append(value)
	for journal: Dictionary in invalids:
		_write(SaveManager.ACCOUNT_DELETION_PATH, journal)
		_check("corrupt_receipt_journal_fails_closed_without_echo", not save.refresh_account_deletion_journal()
			and save.account_deletion_receipt(RECEIPT_OWNER_A).is_empty() and save.account_deletion_recovery_subject().is_empty())
		_write(SaveManager.ACCOUNT_DELETION_PATH, valid)
		_check("valid_receipt_journal_repair_restores_private_service", save.refresh_account_deletion_journal()
			and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A)
	value = valid.duplicate(true)
	value.erase("receipts")
	_write(SaveManager.ACCOUNT_DELETION_PATH, value)
	_check("receipt_field_rollback_cannot_discard_known_secret", not save.refresh_account_deletion_journal()
		and save.account_deletion_state(RECEIPT_OWNER_A) == "unavailable")
	_write(SaveManager.ACCOUNT_DELETION_PATH, valid)
	_check("receipt_rollback_repair_preserves_retired_state", save.refresh_account_deletion_journal())
	value = valid.duplicate(true)
	value["receipts"][RECEIPT_OWNER_A] = RECEIPT_B
	_write(SaveManager.ACCOUNT_DELETION_PATH, value)
	_check("receipt_replacement_cannot_replace_known_secret", not save.refresh_account_deletion_journal())
	_write(SaveManager.ACCOUNT_DELETION_PATH, valid)
	_check("receipt_replacement_repair_restores_original", save.refresh_account_deletion_journal()
		and save.account_deletion_receipt(RECEIPT_OWNER_A) == RECEIPT_A)
	var moved := DirAccess.rename_absolute(ProjectSettings.globalize_path(SaveManager.ACCOUNT_DELETION_PATH),
		ProjectSettings.globalize_path(SaveManager.ACCOUNT_DELETION_TMP_PATH))
	_check("known_receipt_missing_journal_never_assumed_empty", moved == OK and not save.refresh_account_deletion_journal()
		and save.account_deletion_receipt(RECEIPT_OWNER_A).is_empty())
	_write(SaveManager.ACCOUNT_DELETION_PATH, valid)
	_check("missing_journal_repair_restores_known_secret", save.refresh_account_deletion_journal())
	# Existing v1 state-only journals remain valid for a fresh reader. No random
	# receipt or recovery owner may be fabricated from account ordering.
	var legacy := valid.duplicate(true)
	legacy.erase("receipts")
	legacy.erase("recovery_owner")
	legacy["accounts"]["synthetic-legacy-pending"] = "pending"
	_write(SaveManager.ACCOUNT_DELETION_PATH, legacy)
	var restarted := SaveFixture.new()
	add_child(restarted)
	_check("legacy_v1_state_journal_loads_without_fabricated_receipt", restarted.account_deletion_journal_available()
		and restarted.account_deletion_state(RECEIPT_OWNER_A) == "retired"
		and restarted.account_deletion_receipt(RECEIPT_OWNER_A).is_empty()
		and restarted.account_deletion_recovery_subject().is_empty())
	_check("legacy_pending_cannot_be_replaced_with_new_receipt", not restarted.begin_account_deletion("synthetic-legacy-pending", RECEIPT_B)
		and restarted.account_deletion_receipt("synthetic-legacy-pending").is_empty())
	restarted.free()
	_write(SaveManager.ACCOUNT_DELETION_PATH, valid)
	_check("legacy_fixture_restoration_preserves_durable_receipt", save.refresh_account_deletion_journal())


func _check(label: String, success: bool) -> void:
	if success:
		_passed += 1
		print("[account_deletion_cache] PASS " + label)
	else:
		_failed += 1
		push_error("[account_deletion_cache] FAIL " + label)
