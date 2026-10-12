extends RefCounted
## Diagnostic-only mapping from bracketed Godot clock reads to performance.now().
## The browser read occurs somewhere inside the bracket, not at its midpoint.


static func bracket(label: String, before_us: int, browser_ms: Variant, after_us: int) -> Dictionary:
	var sample := {"label": label, "godot_before_us": before_us,
		"godot_after_us": after_us, "valid": false}
	if before_us < 0 or after_us < before_us:
		sample["reason"] = "Invalid monotonic Godot bracket"
		return sample
	if typeof(browser_ms) != TYPE_FLOAT and typeof(browser_ms) != TYPE_INT:
		sample["reason"] = "Browser clock unavailable or not numeric"
		return sample
	var browser_us := float(browser_ms) * 1000.0
	if not is_finite(browser_us) or browser_us < 0.0:
		sample["reason"] = "Browser clock is non-finite or negative"
		return sample
	sample.merge({"valid": true, "browser_ms": float(browser_ms),
		"bracket_width_us": after_us - before_us,
		"browser_minus_godot_min_us": browser_us - float(after_us),
		"browser_minus_godot_max_us": browser_us - float(before_us) }, true)
	return sample
