class_name CloudSaveReconciler
extends RefCounted
## Pure, deterministic reconciliation. No disk, identity, transport or rewards.
## Legacy snapshots cannot reveal shared earnings/spends: never sum balances.

const WALLET_KEY: String = "cloud_wallet_v1"
const PRIVATE_KEYS: PackedStringArray = ["commerce", "account_deletion", "account_deletion_receipt", "account_deletion_receipts", "account_deletion_recovery_owner", "_cloud_owner"]
const MAX_COMPONENTS: int = 256
const MAX_VALUE: int = 9007199254740991


static func progress(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for key: String in PRIVATE_KEYS:
		result.erase(key)
	return result


static func _number(value: Variant) -> float:
	if value is int or value is float:
		var n := float(value)
		return clampf(n, 0.0, float(MAX_VALUE)) if is_finite(n) else 0.0
	return 0.0


static func _integer(value: Variant) -> int:
	return int(_number(value))


static func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _signature(value: Dictionary) -> String:
	# Normalize integral JSON numbers so disk/Web round trips keep ancestry IDs.
	return JSON.stringify(JSON.parse_string(JSON.stringify(value))).sha256_text()


static func _array(value: Variant) -> Array:
	return value if value is Array else []


static func _union(left: Array, right: Array) -> Array:
	var result: Array = []
	for value: Variant in left + right:
		if value is String and not value.is_empty() and value not in result:
			result.append(value)
	result.sort()
	return result


static func _max_tree(left: Dictionary, right: Dictionary) -> Dictionary:
	var result := left.duplicate(true)
	for key: Variant in right:
		var a: Variant = result.get(key)
		var b: Variant = right[key]
		if b is Dictionary:
			result[key] = _max_tree(_dictionary(a), b)
		elif b is bool:
			result[key] = (a is bool and a) or b
		elif b is int or b is float:
			result[key] = maxf(_number(a), _number(b))
		elif not result.has(key):
			result[key] = b
	return result


static func wallet_valid(save: Dictionary) -> bool:
	var wallet := _dictionary(save.get(WALLET_KEY))
	if wallet.get("version") != 1 or not wallet.get("lineage") is String or String(wallet.get("lineage", "")).length() != 64:
		return false
	if not wallet.get("credits") is Dictionary or not wallet.get("debits") is Dictionary:
		return false
	if not _valid_count(wallet.get("base")): return false
	for field: String in ["credits", "debits"]:
		var components: Dictionary = wallet[field]
		if components.size() > MAX_COMPONENTS:
			return false
		for replica: Variant in components:
			if not replica is String or String(replica).length() != 64 or not _valid_count(components[replica]):
				return false
	var purchases: Variant = wallet.get("purchases", {})
	if not purchases is Dictionary: return false
	for id: Variant in purchases:
		if not id is String or String(id).is_empty() or not _valid_count(purchases[id]): return false
	var rewards: Variant = wallet.get("rewards", {})
	if not rewards is Dictionary: return false
	for id: Variant in rewards:
		if not id is String or String(id).is_empty() or not _valid_count(rewards[id]): return false
	var ancestors: Variant = wallet.get("legacy_sources", [])
	if not ancestors is Array or ancestors.size() > MAX_COMPONENTS: return false
	for ancestor: Variant in ancestors:
		if not ancestor is String or String(ancestor).length() != 64: return false
	return _integer(save.get("fish")) == wallet_balance(wallet)


static func _valid_count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 \
		and float(value) <= float(MAX_VALUE) and floor(float(value)) == float(value)


static func wallet_balance(wallet: Dictionary) -> int:
	var total := _integer(wallet.get("base"))
	for value: Variant in _dictionary(wallet.get("credits")).values():
		total += _integer(value)
	for value: Variant in _dictionary(wallet.get("rewards")).values():
		total += _integer(value)
	for value: Variant in _dictionary(wallet.get("debits")).values():
		total -= _integer(value)
	for value: Variant in _dictionary(wallet.get("purchases")).values():
		total -= _integer(value)
	return clampi(total, 0, MAX_VALUE)


static func seed_wallet(balance: int, lineage: String) -> Dictionary:
	return {"version": 1, "lineage": lineage, "base": maxi(balance, 0), "credits": {}, "debits": {}, "purchases": {}, "rewards": {}, "legacy_sources": []}


## Record a real local balance delta once. Replica counter merges are idempotent.
## Negative accumulated balance is retained inside the ledger as debt; future
## income repays it before becoming spendable after concurrent offline spends.
static func change_wallet(save: Dictionary, delta: int, replica: String) -> Dictionary:
	var wallet: Dictionary
	if wallet_valid(save):
		wallet = save[WALLET_KEY].duplicate(true)
	else:
		wallet = seed_wallet(_integer(save.get("fish")), (replica + _signature(progress(save))).sha256_text())
		wallet["legacy_sources"] = [_signature(progress(save))]
	var field := "credits" if delta >= 0 else "debits"
	var counters: Dictionary = wallet[field]
	# Never evict a counter: that could replay earnings or erase a spend.
	if counters.size() >= MAX_COMPONENTS and not counters.has(replica):
		return {}
	counters[replica] = _integer(counters.get(replica)) + absi(delta)
	return wallet


static func purchase_wallet(save: Dictionary, costs: Dictionary, replica: String) -> Dictionary:
	var wallet := change_wallet(save, 0, replica)
	if wallet.is_empty(): return {}
	var purchases := _dictionary(wallet.get("purchases")).duplicate(true)
	for id: Variant in costs:
		if not id is String or _number(costs[id]) != costs[id]: return {}
		purchases[id] = maxi(_integer(purchases.get(id)), _integer(costs[id]))
	wallet["purchases"] = purchases
	return wallet


static func reward_wallet(save: Dictionary, reward_id: String, amount: int, replica: String) -> Dictionary:
	var wallet := change_wallet(save, 0, replica)
	if wallet.is_empty() or reward_id.is_empty() or amount < 0: return {}
	var rewards := _dictionary(wallet.get("rewards")).duplicate(true)
	rewards[reward_id] = maxi(_integer(rewards.get(reward_id)), amount)
	wallet["rewards"] = rewards
	return wallet


static func _played(save: Dictionary) -> bool:
	var wallet := _dictionary(save.get(WALLET_KEY))
	for field: String in ["credits", "debits", "purchases", "rewards"]:
		if _dictionary(wallet.get(field)).values().any(func(v: Variant) -> bool: return _number(v) > 0.0):
			return true
	return _integer(save.get("fish")) > 0 or _integer(save.get("xp")) > 0 \
		or _integer(save.get("runner_high_score")) > 0 or _integer(save.get("endless_high_score")) > 0 \
		or bool(save.get("tutorial_complete", false)) \
		or not _dictionary(save.get("achievements")).is_empty() \
		or _array(save.get("unlocked_cosmetics")).size() > 1 \
		or not _dictionary(save.get("best_times")).is_empty() \
		or _dictionary(save.get("stats")).values().any(func(v: Variant) -> bool: return _number(v) > 0.0)


static func _board_identity(board: Array) -> String:
	var result: Array = []
	for row: Variant in board:
		if not row is Dictionary:
			return ""
		result.append([row.get("id"), row.get("target"), row.get("param"), row.get("mult")])
	return JSON.stringify(result)


## Conservative dominance compares lifetime progress and earned ownership, not
## timestamps, equipment or wallet size. Equal progress with unequal wallets
## remains ambiguous: an old snapshot cannot explain its earnings/spends.
static func _tree_covers(left: Dictionary, right: Dictionary) -> bool:
	for key: Variant in right:
		var a: Variant = left.get(key)
		var b: Variant = right[key]
		if b is Dictionary:
			if not _tree_covers(_dictionary(a), b): return false
		elif b is bool:
			if b and not (a is bool and a): return false
		elif b is int or b is float:
			if _number(a) < _number(b): return false
		elif a != b:
			return false
	return true


static func _progress_covers(left: Dictionary, right: Dictionary) -> bool:
	for key: String in ["stats", "achievements"]:
		if not _tree_covers(_dictionary(left.get(key)), _dictionary(right.get(key))): return false
	for key: String in ["xp", "runner_high_score", "endless_high_score", "runner_mission_stars", "runner_biome_milestone", "daily_best_streak"]:
		if _integer(left.get(key)) < _integer(right.get(key)): return false
	for key: String in ["unlocked_cosmetics", "runner_mission_channels"]:
		for value: Variant in _array(right.get(key)):
			if key == "unlocked_cosmetics" and value == "body_classic": continue
			if value not in _array(left.get(key)): return false
	if bool(right.get("tutorial_complete", false)) and not bool(left.get("tutorial_complete", false)): return false
	for key: Variant in _dictionary(right.get("best_times")):
		var rt := _number(right["best_times"][key])
		var lt := _number(_dictionary(left.get("best_times")).get(key))
		if rt > 0.0 and (lt <= 0.0 or lt > rt): return false
	for key: Variant in _dictionary(right.get("gp_records")):
		var a := _dictionary(_dictionary(left.get("gp_records")).get(key))
		var b := _dictionary(right["gp_records"][key])
		if a.is_empty() or int(a.get("placement", 99)) > int(b.get("placement", 99)): return false
		if a.get("placement") == b.get("placement") and _number(a.get("points")) < _number(b.get("points")): return false
	if _integer(left.get("runner_mission_stars")) == _integer(right.get("runner_mission_stars")):
		var lb := _array(left.get("runner_missions"))
		var rb := _array(right.get("runner_missions"))
		if not rb.is_empty():
			if _board_identity(lb) != _board_identity(rb): return false
			for i: int in rb.size():
				if _number(lb[i].get("progress")) < _number(rb[i].get("progress")): return false
				if bool(rb[i].get("done", false)) and not bool(lb[i].get("done", false)): return false
	return true


static func reconcile(local_raw: Dictionary, cloud_raw: Dictionary) -> Dictionary:
	var local := progress(local_raw)
	var cloud := progress(cloud_raw)
	# Keep unknown fields and preference/equipment choices from this device.
	# Absent fields can be recovered from cloud; never recursively sum counters.
	var merged := cloud.duplicate(true)
	merged.merge(local, true)
	for key: String in ["stats", "achievements"]:
		merged[key] = _max_tree(_dictionary(local.get(key)), _dictionary(cloud.get(key)))
	for key: String in ["unlocked_cosmetics", "runner_mission_channels"]:
		merged[key] = _union(_array(local.get(key)), _array(cloud.get(key)))
	for key: String in ["xp", "runner_high_score", "endless_high_score", "runner_mission_stars", "runner_biome_milestone", "runner_progression_pacing_version", "daily_best_streak"]:
		merged[key] = maxi(_integer(local.get(key)), _integer(cloud.get(key)))
	merged["tutorial_complete"] = bool(local.get("tutorial_complete", false)) or bool(cloud.get("tutorial_complete", false))
	var times := _dictionary(local.get("best_times")).duplicate(true)
	for key: Variant in _dictionary(cloud.get("best_times")):
		var other := _number(cloud["best_times"][key])
		if other > 0.0 and (_number(times.get(key)) <= 0.0 or other < _number(times.get(key))):
			times[key] = other
	merged["best_times"] = times
	var records := _dictionary(local.get("gp_records")).duplicate(true)
	for key: Variant in _dictionary(cloud.get("gp_records")):
		var a := _dictionary(records.get(key))
		var b := _dictionary(cloud["gp_records"][key])
		var ap := int(a.get("placement", 99))
		var bp := int(b.get("placement", 99))
		if bp < ap or (bp == ap and _integer(b.get("points")) > _integer(a.get("points"))):
			records[key] = b.duplicate(true)
	merged["gp_records"] = records
	var daily := cloud if int(cloud.get("daily_last_day", -1)) > int(local.get("daily_last_day", -1)) else local
	for key: String in ["daily_last_day", "daily_last_time", "daily_streak"]:
		if daily.has(key): merged[key] = daily[key]
	var ls := _integer(local.get("runner_mission_stars"))
	var cs := _integer(cloud.get("runner_mission_stars"))
	var lb := _array(local.get("runner_missions"))
	var cb := _array(cloud.get("runner_missions"))
	var board_owner := cloud if cs > ls or lb.is_empty() else local
	merged["runner_missions"] = _array(board_owner.get("runner_missions")).duplicate(true)
	merged["runner_missions_next_run"] = bool(board_owner.get("runner_missions_next_run", false))
	if ls == cs and not lb.is_empty() and _board_identity(lb) == _board_identity(cb):
		var board: Array = merged["runner_missions"]
		for i: int in board.size():
			board[i]["progress"] = minf(_number(board[i].get("target")), maxf(_number(lb[i].get("progress")), _number(cb[i].get("progress"))))
			# Reconciliation never grants rewards; earned completion remains earned.
			board[i]["done"] = bool(lb[i].get("done", false)) or bool(cb[i].get("done", false))
		var all_done := board.all(func(row: Dictionary) -> bool: return bool(row.get("done", false)))
		if all_done and not lb.all(func(row: Dictionary) -> bool: return bool(row.get("done", false))) \
			and not cb.all(func(row: Dictionary) -> bool: return bool(row.get("done", false))):
			# Combining complementary partial rows must not manufacture a board
			# completion with neither its star nor reward. Keep both snapshots and
			# retry after one device completes the board through real gameplay.
			return {"ok": false, "error": "ambiguous_mission_board"}
		merged["runner_missions_next_run"] = bool(local.get("runner_missions_next_run", false)) or bool(cloud.get("runner_missions_next_run", false))
	var wallet: Dictionary
	var policy := "legacy_dominant"
	var local_signature := _signature(local)
	var cloud_signature := _signature(cloud)
	if wallet_valid(local) and cloud_signature in local[WALLET_KEY].get("legacy_sources", []):
		wallet = local[WALLET_KEY].duplicate(true)
		policy = "known_legacy_ancestor"
	elif wallet_valid(cloud) and local_signature in cloud[WALLET_KEY].get("legacy_sources", []):
		wallet = cloud[WALLET_KEY].duplicate(true)
		policy = "known_legacy_ancestor"
	elif wallet_valid(local) and wallet_valid(cloud) and local[WALLET_KEY]["lineage"] == cloud[WALLET_KEY]["lineage"] and local[WALLET_KEY]["base"] == cloud[WALLET_KEY]["base"]:
		wallet = local[WALLET_KEY].duplicate(true)
		for field: String in ["credits", "debits"]:
			wallet[field] = _max_tree(local[WALLET_KEY][field], cloud[WALLET_KEY][field])
			if wallet[field].size() > MAX_COMPONENTS:
				return {"ok": false, "error": "wallet_capacity"}
		wallet["purchases"] = _max_tree(_dictionary(local[WALLET_KEY].get("purchases")), _dictionary(cloud[WALLET_KEY].get("purchases")))
		wallet["rewards"] = _max_tree(_dictionary(local[WALLET_KEY].get("rewards")), _dictionary(cloud[WALLET_KEY].get("rewards")))
		wallet["legacy_sources"] = _union(_array(local[WALLET_KEY].get("legacy_sources")), _array(cloud[WALLET_KEY].get("legacy_sources")))
		if wallet["legacy_sources"].size() > MAX_COMPONENTS: return {"ok": false, "error": "wallet_capacity"}
		policy = "shared_lineage_counters"
	elif not _played(local) or not _played(cloud):
		var played := cloud if not _played(local) else local
		wallet = played[WALLET_KEY].duplicate(true) if wallet_valid(played) else seed_wallet(_integer(played.get("fish")), _signature(played))
		if not wallet_valid(played):
			wallet["legacy_sources"] = [_signature(played)]
		policy = "pristine_adopts_played"
	else:
		# Deterministic ancestry reset for legacy/unrelated ledgers. Both originals
		# are durably backed up by SaveManager before this result is applied.
		var signatures: Array[String] = [local_signature, cloud_signature]
		signatures.sort()
		var local_covers := _progress_covers(local, cloud)
		var cloud_covers := _progress_covers(cloud, local)
		if local_signature != cloud_signature and local_covers == cloud_covers:
			return {"ok": false, "error": "ambiguous_legacy_wallet"}
		var chosen := local if local_covers else cloud
		wallet = chosen[WALLET_KEY].duplicate(true) if wallet_valid(chosen) else seed_wallet(_integer(chosen.get("fish")), (signatures[0] + signatures[1]).sha256_text())
		wallet["legacy_sources"] = _union(_union(_array(_dictionary(local.get(WALLET_KEY)).get("legacy_sources")), _array(_dictionary(cloud.get(WALLET_KEY)).get("legacy_sources"))), signatures)
		if wallet["legacy_sources"].size() > MAX_COMPONENTS: return {"ok": false, "error": "wallet_capacity"}
	merged[WALLET_KEY] = wallet
	merged["fish"] = wallet_balance(wallet)
	merged["cloud_sync_version"] = 2
	return {"ok": true, "progress": merged, "wallet_policy": policy}
