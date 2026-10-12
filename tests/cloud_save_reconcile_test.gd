extends Node
## Isolated offline fixture: no live identity, provider or cloud requests.
const Merge = preload("res://scripts/save/cloud_save_reconciler.gd")
const Online = preload("res://scripts/network/leaderboard_client.gd")
var passed := 0
var failed := 0
const A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const L := "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

class SaveFailure extends "res://scripts/save/save_manager.gd":
	func _ready() -> void: pass
	func _write_cloud_state(_owner_hash: String, _value: Dictionary) -> bool: return false

class Client extends "res://scripts/network/leaderboard_client.gd":
	var requests: Array[Dictionary] = []
	func _ready() -> void: set_process(false)
	func can_sign_in() -> bool: return true
	func _dispatch_request(method: String, url: String, body: String, cb: Callable) -> void:
		requests.append({"method": method, "body": body, "callback": cb})

func check(label: String, condition: bool) -> void:
	if condition: passed += 1
	else:
		failed += 1
		push_error("[cloud-reconcile] " + label)

func state(fish: int = 100) -> Dictionary:
	var s := SaveManager.default_save()
	s.fish = fish
	s[Merge.WALLET_KEY] = Merge.seed_wallet(fish, L)
	return s

func delta(s: Dictionary, amount: int, replica: String) -> Dictionary:
	var result := s.duplicate(true)
	result[Merge.WALLET_KEY] = Merge.change_wallet(result, amount, replica)
	result.fish = Merge.wallet_balance(result[Merge.WALLET_KEY])
	return result

func purchase(s: Dictionary, costs: Dictionary, replica: String) -> Dictionary:
	var result := s.duplicate(true)
	result[Merge.WALLET_KEY] = Merge.purchase_wallet(result, costs, replica)
	result.fish = Merge.wallet_balance(result[Merge.WALLET_KEY])
	result.unlocked_cosmetics.append_array(costs.keys())
	return result

func _ready() -> void:
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) or not identity.begins_with("waddle-wars-tests-"):
		push_error("cloud-reconcile requires isolated waddle-wars-tests-* user data")
		get_tree().quit(2)
		return
	var saved := SaveManager.data.duplicate(true)
	var settings := SettingsManager.settings.duplicate(true)
	var left := delta(state(), 30, A)
	var right := delta(state(), 20, B)
	var merged := Merge.reconcile(left, right)
	check("concurrent credits retained once", merged.ok and merged.progress.fish == 150)
	for i in 20:
		merged = Merge.reconcile(merged.progress, right)
		check("repeat sync does not duplicate credits %d" % i, merged.progress.fish == 150)
	var spent := Merge.reconcile(delta(state(), -30, A), delta(state(), -20, B))
	check("concurrent distinct spends retained once", spent.progress.fish == 50)
	var same_item := Merge.reconcile(purchase(state(), {"hat_beanie": 40}, A), purchase(state(), {"hat_beanie": 40}, B))
	check("same item paid once across devices", same_item.progress.fish == 60 and same_item.progress.unlocked_cosmetics.count("hat_beanie") == 1)
	var debt: Dictionary = Merge.reconcile(delta(state(), -80, A), delta(state(), -70, B)).progress
	check("offline debt not minted into fish", debt.fish == 0)
	debt = delta(debt, 30, A)
	check("new income first repays debt", debt.fish == 0)
	debt = delta(debt, 30, A)
	check("only excess over debt spendable", debt.fish == 10)
	var old_a := {"fish": 100, "xp": 100, "unlocked_cosmetics": ["body_classic", "hat_a"], "achievements": {"one": true}, "stats": {"fish_total": 600}, "best_times": {"race": 70.0}}
	var old_b := {"fish": 9000, "xp": 200, "unlocked_cosmetics": ["body_classic", "hat_b"], "achievements": {"two": true}, "stats": {"fish_total": 9000}, "best_times": {"race": 60.0}}
	var ambiguous := Merge.reconcile(old_a, old_b)
	check("unrelated legacy histories defer without losing either balance", not ambiguous.ok and ambiguous.error == "ambiguous_legacy_wallet")
	old_b.unlocked_cosmetics.append("hat_a")
	old_b.achievements.one = true
	var original_a := old_a.duplicate(true)
	var original_b := old_b.duplicate(true)
	var legacy := Merge.reconcile(old_a, old_b)
	check("dominant legacy snapshot keeps its coherent wallet", legacy.progress.fish == 9000 and legacy.wallet_policy == "legacy_dominant")
	check("earned unlock union", legacy.progress.unlocked_cosmetics == ["body_classic", "hat_a", "hat_b"])
	check("earned achievements retained without reward emission", legacy.progress.achievements.one and legacy.progress.achievements.two and legacy.progress.xp == 200)
	check("best time min and monotonic statistic max", legacy.progress.best_times.race == 60 and legacy.progress.stats.fish_total == 9000)
	check("merge leaves inputs untouched", old_a == original_a and old_b == original_b)
	var earned_after_merge := delta(legacy.progress, 10, A)
	var lineage: String = earned_after_merge[Merge.WALLET_KEY].lineage
	for i in 20:
		earned_after_merge = Merge.reconcile(earned_after_merge, JSON.parse_string(JSON.stringify(original_b))).progress
		check("legacy replay preserves lineage and subsequent earned fish %d" % i, earned_after_merge.fish == 9010 and earned_after_merge[Merge.WALLET_KEY].lineage == lineage)
	var adopted: Dictionary = Merge.reconcile(SaveManager.default_save(), old_b).progress
	check("pristine adopts played balance", adopted.fish == 9000)
	adopted = delta(adopted, 25, A)
	check("failed first PUT followed by earnings preserves adopted ancestor", Merge.reconcile(adopted, old_b).progress.fish == 9025)
	var reward_a := state()
	reward_a[Merge.WALLET_KEY] = Merge.reward_wallet(reward_a, "runner_board:1", 120, A)
	reward_a.fish = 220
	var reward_b := state()
	reward_b[Merge.WALLET_KEY] = Merge.reward_wallet(reward_b, "runner_board:1", 120, B)
	reward_b.fish = 220
	check("same offline board reward credited once", Merge.reconcile(reward_a, reward_b).progress.fish == 220)
	var malformed := state()
	malformed[Merge.WALLET_KEY].credits[A] = -1
	check("negative ledger component rejected", not Merge.wallet_valid(malformed))
	malformed[Merge.WALLET_KEY].credits[A] = 1.5
	check("fractional ledger component rejected", not Merge.wallet_valid(malformed))
	var board_a := state()
	board_a.runner_mission_stars = 1
	board_a.runner_missions = [{"id": "jump_total", "target": 40, "progress": 10, "done": false, "param": "", "mult": 0}]
	var board_b := board_a.duplicate(true)
	board_b.runner_missions[0].progress = 25
	check("matching board progress retained not summed", Merge.reconcile(board_a, board_b).progress.runner_missions[0].progress == 25)
	board_b.runner_mission_stars = 2
	board_b.runner_missions[0].target = 60
	board_b.runner_missions[0].progress = 3
	check("higher-star board stays coherent", Merge.reconcile(board_a, board_b).progress.runner_missions[0].progress == 3)
	var split_a := state()
	split_a.runner_missions = [{"id": "a", "target": 1, "progress": 1, "done": true}, {"id": "b", "target": 1, "progress": 0, "done": false}]
	var split_b := state()
	split_b.runner_missions = [{"id": "a", "target": 1, "progress": 0, "done": false}, {"id": "b", "target": 1, "progress": 1, "done": true}]
	var split := Merge.reconcile(split_a, split_b)
	check("complementary partial board cannot skip star and reward", not split.ok and split.error == "ambiguous_mission_board")
	var seeded := delta(original_a, 5, A)
	check("first local wallet conversion records old snapshot ancestry", Merge.reconcile(seeded, original_a).progress.fish == 105)
	SaveManager.data = state()
	Progression.add_fish(40, "runner_board:4")
	Progression.add_fish(40, "runner_board:4")
	check("actual progression milestone hook grants once", SaveManager.data.fish == 140 and Progression.get_stat("fish_total") == 40)
	SaveManager.data = state()
	var daily_a := DailyChallenge.record_completion(65.0)
	var daily_left := SaveManager.data.duplicate(true)
	SaveManager.data = state()
	DailyChallenge.record_completion(60.0)
	check("actual daily reward reconciles once across saved replicas", Merge.reconcile(daily_left, SaveManager.data).progress.fish == 100 + daily_a.fish)
	_test_storage(original_a, original_b)
	_test_client()
	_test_retry_and_pending()
	SaveManager.data = saved
	SettingsManager.settings = settings
	SaveManager.save_now()
	print("[cloud-reconcile] %d/%d passed" % [passed, passed + failed])
	get_tree().quit(1 if failed else 0)

func _test_storage(local: Dictionary, remote: Dictionary) -> void:
	SaveManager.data = local.duplicate(true)
	check("first account claims unbound guest only", SaveManager.bind_cloud_owner("synthetic-cloud-a"))
	var result := SaveManager.reconcile_cloud_save("synthetic-cloud-a", remote, A)
	check("automatic local reconcile succeeds", result.ok and SaveManager.data.fish == 9000)
	var recovery := SaveManager._cloud_state("synthetic-cloud-a".sha256_text())
	check("both originals durable before replacement", recovery.originals.local.fish == 100 and recovery.originals.cloud.fish == 9000)
	check("originals exclude owner and commerce", not recovery.originals.local.has("_cloud_owner") and not recovery.originals.local.has("commerce"))
	check("different account cannot reconcile", not SaveManager.reconcile_cloud_save("synthetic-cloud-b", remote, A).ok)
	check("account switch creates independent local slot", SaveManager.bind_cloud_owner("synthetic-cloud-b") and SaveManager.data.fish == 0 and not SaveManager.data.achievements.has("one"))
	check("returning account restores its own working save", SaveManager.bind_cloud_owner("synthetic-cloud-a") and SaveManager.data.fish == 9000 and SaveManager.data.achievements.one)
	var failing := SaveFailure.new()
	add_child(failing)
	failing.data = SaveManager.data.duplicate(true)
	var unchanged := failing.data.duplicate(true)
	var blocked := failing.reconcile_cloud_save("synthetic-cloud-a", remote, A)
	check("failed backup cannot replace local progress", not blocked.ok and blocked.error == "backup_failed" and failing.data == unchanged)
	failing.free()
	check("owner marker never uploaded", not SaveManager.cloud_progress_snapshot(SaveManager.data).has("_cloud_owner"))

func _test_client() -> void:
	var client := Client.new()
	add_child(client)
	SettingsManager.set_setting("online", "display_name", "Legacy Guest")
	SettingsManager.set_setting("online", "public_handles", {})
	check("legacy guest handle survives empty scope map", client.player_display_name() == "Legacy Guest")
	var guest_result: Array = []
	client.set_display_name("Snow Friend", func(ok: bool, body: Dictionary) -> void: guest_result.append([ok, body]))
	check("guest name stores locally without request", guest_result[0][0] and client.player_display_name() == "Snow Friend" and client.requests.is_empty())
	client.signed_in = true
	client._token = "synthetic-token"
	client._auth_owner_id = "synthetic-name-a"
	check("guest handle not inherited by signed-in account", client.player_display_name() == "Penguin")
	var name_reply: Array = []
	client.set_display_name("Account A", func(ok: bool, body: Dictionary) -> void: name_reply.append([ok, body]))
	var old: Callable = client.requests[0].callback
	client._auth_generation += 1
	client._auth_owner_id = "synthetic-name-b"
	old.call(true, {"name": "Account A"})
	check("late name success cannot write another account", not name_reply[0][0] and client.custom_player_name().is_empty())
	client.requests.clear()
	client._load_public_name()
	check("new device fetches custom public profile", client.requests.size() == 1 and client.requests[0].method == "GET")
	client.requests[0].callback.call(true, {"name": "Cross Device"})
	check("profile fetch restores only explicit custom handle", client.player_display_name() == "Cross Device")
	client._profile_requested_generation = -1
	client.requests.clear()
	client._load_public_name()
	var stale_get: Callable = client.requests[0].callback
	client.set_display_name("Fresh Name", func(_ok: bool, _body: Dictionary) -> void: pass)
	client.requests[1].callback.call(true, {"name": "Fresh Name"})
	stale_get.call(true, {"name": "Stale Name"})
	check("older profile read cannot undo a new chosen name", client.player_display_name() == "Fresh Name")
	client.requests.clear()
	client._synced_this_session = false
	client.cloud_sync_error = false
	var before := SaveManager.data.duplicate(true)
	client._on_auth_changed_sync()
	check("sync begins with revision-capable pull", client.requests.size() == 1 and client.requests[0].method == "GET")
	client.requests[0].callback.call(true, {"exists": false})
	check("unsupported server never mutates active save or uploads", SaveManager.data == before and client.requests.size() == 1 and client.cloud_sync_status() == "unavailable")
	check("chooser permanently inactive", not client.has_cloud_save_conflict() and not client.resolve_cloud_save_conflict(true))
	client.free()

func _test_retry_and_pending() -> void:
	SaveManager.data = SaveManager.default_save()
	var client := Client.new()
	add_child(client)
	client.signed_in = true
	client._token = "synthetic-token"
	client._auth_owner_id = "synthetic-retry-owner"
	client._on_auth_changed_sync()
	var reply := {"exists": true, "sync_protocol": 2, "revision": A, "data": JSON.stringify({"fish": 500, "xp": 20})}
	client.requests[0].callback.call(true, reply)
	check("pristine first pull starts conditional PUT", client.requests.size() == 2 and SaveManager.data.fish == 500)
	client.requests[1].callback.call(false, {"error": "network"})
	SaveManager.set_value("fish", 525)
	client.cloud_sync_error = false
	client._on_auth_changed_sync()
	client.requests[2].callback.call(true, reply)
	check("failed PUT retry preserves real local earnings", client.requests.size() == 4 and JSON.parse_string(client.requests[3].body).progress.fish == 525)
	client.requests[3].callback.call(true, {"sync_protocol": 2, "revision": B})
	check("only revision acknowledgement marks cloud saved", client.cloud_sync_status() == "saved")
	client.free()
	SaveManager.data = SaveManager.default_save()
	SaveManager.data.fish = 100
	client = Client.new()
	add_child(client)
	client.signed_in = true
	client._token = "synthetic-token"
	client._auth_owner_id = "synthetic-ambiguous-owner"
	client._on_auth_changed_sync()
	client.requests[0].callback.call(true, {"exists": true, "sync_protocol": 2, "revision": A, "data": JSON.stringify({"fish": 9000})})
	check("ambiguous legacy does not upload or reduce active fish", client.requests.size() == 1 and SaveManager.data.fish == 100 and client.cloud_sync_status() == "pending")
	var recovery := SaveManager._cloud_state(client._auth_owner_id.sha256_text())
	check("ambiguous originals both durable", recovery.originals.local.fish == 100 and recovery.originals.cloud.fish == 9000)
	client._on_auth_changed_sync()
	check("ambiguous state does not poll-loop", client.requests.size() == 1 and client._cloud_retry_timer < 0)
	client.notify_save_written()
	check("meaningful local save permits bounded retry", not client.cloud_sync_error)
	client.free()
