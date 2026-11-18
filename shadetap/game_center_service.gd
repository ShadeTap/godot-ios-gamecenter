class_name GameCenterService
extends RefCounted

# Apple Game Center for a ShadeTap game over the native GameCenterKit bridge
# (iOS). The game says what Game Center should show — scores and achievement
# percents by component ID — and this class signs the player in, sends what is
# new and opens the system panels. It knows nothing of the game, so every game
# uses the same file. Without the bridge (Android, desktop, tests) it does nothing.
# Canonical source: ShadeTap/godot-ios-gamecenter, shadetap/game_center_service.gd.
# A game carries an unchanged copy; change it there first.
const BRIDGE := "GameCenterKit"
signal state_changed
var signed_in := false
# Optional debug trace: trace.call(event, details). The service prints nothing.
var trace := Callable()
var _backend: Object
var _started := false
# The wanted state and what was sent this session. Memory only: every sign-in
# sends the whole wanted state again, and a failed send is dropped from the
# record, so the next sync repeats it. No timers, retries or queues.
var _wanted := {"scores": {}, "achievements": {}}
var _sent := {"scores": {}, "achievements": {}}

static func bridge() -> Object:
	return Engine.get_singleton(BRIDGE) if Engine.has_singleton(BRIDGE) else null

# `backend`: the bridge, null (no Game Center) or a test double with its methods and signals.
func _init(backend: Object = null) -> void:
	_backend = backend

func available() -> bool:
	return is_instance_valid(_backend)

# Sign-in once per launch; GameKit reports later sign-ins and account switches
# through the same `authenticated` signal.
func start() -> void:
	if not available() or _started: return
	_started = true
	_listen("authenticated", _on_authenticated)
	_listen("score_submitted", _on_score_submitted)
	_listen("achievement_reported", _on_achievement_reported)
	_listen("panel_failed", _on_panel_failed)
	_trace("start", {})
	_call("authenticate")

# `desired`: {"scores": {id: int}, "achievements": {id: percent 0..100}}.
func sync(desired: Dictionary) -> void:
	if not available(): return
	_wanted = {"scores": desired.get("scores", {}).duplicate(), "achievements": desired.get("achievements", {}).duplicate()}
	if signed_in: _send()

# False without Game Center or before sign-in: the caller decides what to show.
func open_achievements() -> bool:
	if not available() or not signed_in: return false
	_trace("panel", {"panel": "achievements"})
	return _call("show_achievements")

func open_leaderboard(id: String) -> bool:
	if not available() or not signed_in: return false
	_trace("panel", {"panel": "leaderboard", "id": id})
	return _call("show_leaderboard", [id])

# Only values above the ones already sent go out; zero is never sent.
func _send() -> void:
	for id in _wanted.scores:
		var score := int(_wanted.scores[id])
		if score <= 0 or score <= int(_sent.scores.get(id, 0)): continue
		_sent.scores[id] = score
		_trace("submit_score", {"id": id, "score": score})
		_call("submit_score", [str(id), score])
	for id in _wanted.achievements:
		var percent := float(_wanted.achievements[id])
		if percent <= 0 or percent <= float(_sent.achievements.get(id, 0.0)): continue
		_sent.achievements[id] = percent
		_trace("report_achievement", {"id": id, "percent": percent})
		_call("report_achievement", [str(id), percent])

# Any sign-in (the first, a later one or another account) starts the record
# anew and sends everything; a refusal, cancel or offline only signs out.
func _on_authenticated(ok: bool, error: String) -> void:
	_trace("authenticated", {"ok": ok, "error": error})
	var changed := signed_in != ok
	signed_in = ok
	if ok: _sent = {"scores": {}, "achievements": {}}
	if changed: state_changed.emit()
	if ok: _send()

func _on_score_submitted(ok: bool, leaderboard_id: String, error: String) -> void:
	if ok: return
	_sent.scores.erase(leaderboard_id)
	_trace("score_failed", {"id": leaderboard_id, "error": error})

func _on_achievement_reported(ok: bool, achievement_id: String, error: String) -> void:
	if ok: return
	_sent.achievements.erase(achievement_id)
	_trace("achievement_failed", {"id": achievement_id, "error": error})

func _on_panel_failed(panel: String, error: String) -> void:
	_trace("panel_failed", {"panel": panel, "error": error})

# A bridge without a member is tolerated: the call or the signal is skipped.
func _call(method: String, args: Array = []) -> bool:
	if not _backend.has_method(method): return false
	_backend.callv(method, args)
	return true

func _listen(signal_name: String, handler: Callable) -> void:
	if _backend.has_signal(signal_name) and not _backend.is_connected(signal_name, handler): _backend.connect(signal_name, handler)

func _trace(event: String, details: Dictionary) -> void:
	if trace.is_valid(): trace.call(event, details)
