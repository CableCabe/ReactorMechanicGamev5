# scripts/GameState.gd (autoload singleton)
extends Node

# --- Core State ---
# CURRENCY:
var _eu: float = 0.0
var eu: float:
	get: return _eu
	set(value):
		if !is_equal_approx(value, _eu):
			_eu = value
			eu_changed.emit(_eu)
var money: float = 0.0
var flags: Dictionary = {"auto_sell_ratio": 0.01}

const FUEL_TO_EU := 18.0
const BASE_EU_S := 1.0
const CLICK_BONUS := 2.0
const PRICE_PER_10_EU := 1.0

# RESEARCH
var research_db: Dictionary = {}    # loaded JSON
var research: Dictionary = {}       # key -> level (int)
var research_levels: Dictionary = {}

# PILLARS
var pillars: Array = []   # Array of Dictionary {"id":int, "level":int, "enabled":bool}

const NUM_PILLARS := 6
const BASE_PILLAR_INTERVAL_S := 2.0      # default time between ignitions
const MIN_PILLAR_INTERVAL_S  := 0.3      # clamp after research
const PILLAR_PULSE_EU        := 1.2      # Eu per ignition before multipliers
const PILLAR_PULSE_HEAT      := 0.6      # Heat contribution per ignition
const PILLAR_FUEL_PULSE      := 0.06     # Fuel burned per ignition
const PILLAR_LEVEL_BONUS     := 0.20     # +20% Eu per level (same as before)

# FUEL
var fuel_cap: float = 1000.0
var _fuel: float = 0.0
var fuel: float:
	get: return _fuel
	set(value):
		var v: float = clamp(value, 0.0, fuel_cap)
		if not is_equal_approx(v, _fuel):
			_fuel = v
			fuel_changed.emit(_fuel)
			if has_signal("state_changed"):
				state_changed.emit()

const FUEL_BURN_S := 0.0002
const FUEL_CAP     := 1000.0
const FUEL_START_FRAC: float = 0.50
const FUEL_PER_IGNITE: float = 1.0             # ml spent per manual ignite
const FUEL_REFILL_PER_SEC: float = 0.0      # set >0 if you want passive refuel

# COOLANT
var coolant_cap: float = 1000.0
var _coolant: float = 0.0
var coolant: float:
	get: return _coolant
	set(value):
		var v: float = clamp(value, 0.0, coolant_cap)
		if not is_equal_approx(v, _coolant):
			_coolant = v
			coolant_changed.emit(_coolant)
			if has_signal("state_changed"):
				state_changed.emit()

const COOLANT_START_FRAC: float = 0.50
const COOLANT_USE_PER_SEC_BASE: float = 0.0     # baseline pump use
const COOLANT_USE_PER_SEC_WHEN_COOLING: float = 2.0   # extra when heat > ambient
const COOLANT_USE_PER_SEC_WHEN_VENT: float = 8.0      # extra while venting
const COOLANT_REFILL_PER_SEC: float = 0.0       # set >0 for passive refill
const COOLANT_POWER := 0.6
const COOLANT_CAP  := 1000.0   

# HEAT
const BASE_HEAT_S := 0.4
const HEAT_FACTOR := 0.02
const HEAT_START: float = 50.0
const BASE_COOL_PER_SEC: float = 1.5
const COOLANT_COOL_FULL_PER_SEC: float = 8.0
const IDLE_COOL_DELAY: float = 3.0
const IDLE_COOL_PER_SEC: float = 4.0
const AMBIENT_WARM_PER_SEC: float = 1.0
const IGNITE_HEAT_PULSE: float = 1.8

# VENTING
const VENT_COOL_PER_SEC: float = 6.5
const VENT_DURATION_SEC: float = 3.0
const VENT_DROP_TOTAL: float = 18.0

var is_venting: bool = false
var _vent_timer: Timer
var _vent_cool_remaining: float = 0.0

# Fixed‑timestep accumulator (10 Hz)
const STEP := 0.1
var _accum := 0.0
var _time_since_ignite: float = 0.0


# ---- SIGNALS ----
signal research_loaded
signal state_changed
signal eu_changed(value)
signal heat_changed(value)
signal vent_started
signal vent_finished
signal fuel_changed(value)
signal coolant_changed(value)


# ---- SPENDING TRACKER ----
func add_eu(a: float) -> void:
	eu = eu + a

func spend_eu(a: float) -> bool:
	if _eu >= a:
		eu = _eu - a
		return true
	return false



# ---- LOADING ----
func _enter_tree() -> void:
	set_process(true)
	reset_state_defaults()
	ensure_pillars()
	_load_research()
	load_game()
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 0.6
	add_child(t)
	t.timeout.connect(func():
		sim_ready = true
		t.queue_free())
	_vent_timer = Timer.new()
	_vent_timer.one_shot = true
	add_child(_vent_timer)
	_vent_timer.timeout.connect(_on_vent_timeout)
	
func reset_state_defaults() -> void:
	eu = 0.0
	money = 0.0
	fuel_cap = 100.0
	coolant_cap = 100.0
	fuel = fuel_cap * FUEL_START_FRAC
	coolant = coolant_cap * COOLANT_START_FRAC
	heat = HEAT_START
	research_levels.clear()
	ensure_pillars(PILLAR_COUNT)
	state_changed.emit()
	if has_signal("eu_changed"): eu_changed.emit(eu)


func _load_research() -> void:
	var f = FileAccess.open("res://data/research.json", FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			research_db = parsed
		elif typeof(parsed) == TYPE_ARRAY:
			var d = {}
			for e in parsed:
				var k = e.get("key", e.get("id", e.get("name", "item_%d" % d.size())))
				d[k] = e
			research_db = d
		print("Loaded research entries:", research_db.size())
	else:
		push_error("Missing research.json at res://data/research.json")
	research_loaded.emit()




# ---- Mod system ----
func base_stats() -> Dictionary:
	return {
		"eu_add": 0.0,    # flat Eu added per second (rare)
		"eu_mult": 1.0,   # multiplicative Eu boost
		"heat_add": 0.0,  # flat heat per second
		"heat_mult": 1.0, # multiplicative heat factor
		"fuel_add": 0.0,  # extra fuel burn per s
		"fuel_mult": 1.0,  # multiplicative fuel factor
		"fire_rate_mult": 1.0   # >1.0 = faster ignition
	}

func apply_mods(stats: Dictionary, mods: Array) -> void:
	# additive first
	for m in mods:
		if m.get("op") == "add":
			var k: String = str(m.get("stat"))
			var cur := float(stats.get(k, 0.0))
			stats[k] = cur + float(m.get("value", 0.0))

	# then multiplicative
	for m in mods:
		if m.get("op") == "mul":
			var k: String = str(m.get("stat"))
			var cur := float(stats.get(k, 1.0))
			stats[k] = cur * (1.0 + float(m.get("value", 0.0)))


func global_mods() -> Array:
	var mods: Array = []
	for key in research_db.keys():
		var lvl := research_level(key)
		if lvl <= 0: continue
		var levels: Array = research_db[key].get("levels", [])
		for i in range(min(lvl, levels.size())):
			var mlist: Array = levels[i].get("mods", [])
			for m in mlist:
				if String(m.get("scope","global")) == "global":
					mods.append(m)
	return mods

func pillar_mods(idx: int) -> Array:
	var mods: Array = []
	for key in research_db.keys():
		var lvl := research_level(key)
		if lvl <= 0: continue
		var levels: Array = research_db[key].get("levels", [])
		for i in range(min(lvl, levels.size())):
			for m in levels[i].get("mods", []):
				if String(m.get("scope","")) == "pillar":
					# optional targeting: { scope:"pillar", pillar:"all"/int }
					var target = m.get("pillar", "all")
					if target == "all" or int(target) == idx:
						mods.append(m)
	return mods



# ---- HEAT ----

var _heat: float = HEAT_START
var heat: float:
	get: return _heat
	set(value):
		var v: float = value
		if v > 1.0:
			v = clamp(v, 0.0, 100.0)  # model supports 0..100
		else:
			v = clamp(v, 0.0, 1.0)    # also supports 0..1 (we'll emit 0..100 below)
			v = v * 100.0
		if not is_equal_approx(v, _heat):
			_heat = v
			heat_changed.emit(_heat)
			if has_signal("state_changed"):
				state_changed.emit()

var sim_ready: bool = false

func add_heat_pulse(amount: float) -> void:
	var k: float = 0.5 + min(_time_since_ignite, 1.0) * 0.5
	heat = heat + amount * k
	_time_since_ignite = 0.0

func set_heat(v: float) -> void:
	heat = v

func add_heat(d: float) -> void:
	heat = heat + d

# Sweet-spot: 35–65% is optimal, outside it halves output/rate.
func heat_rate_mult() -> float:
	if _heat < 35.0 or _heat > 65.0:
		return 0.5
	return 1.0



# ---- VENTING ----

func start_venting(duration: float = VENT_DURATION_SEC) -> void:
	if is_venting:
		return
	is_venting = true
	_vent_cool_remaining = VENT_DROP_TOTAL
	vent_started.emit()
	_vent_timer.stop()
	_vent_timer.wait_time = duration
	_vent_timer.start()

func _on_vent_timeout() -> void:
	is_venting = false
	_vent_cool_remaining = 0.0
	vent_finished.emit()



# ---- PROCESSES ----

func _process(delta: float) -> void:
	_accum += delta
	while _accum >= STEP:
		sim_tick(STEP)
		_accum -= STEP
	if not sim_ready: return
	_time_since_ignite += delta

	# Passive cooling
	var cool: float = BASE_COOL_PER_SEC
	if _time_since_ignite >= IDLE_COOL_DELAY:
		cool += IDLE_COOL_PER_SEC
	if is_venting:
		cool += VENT_COOL_PER_SEC
	var fill: float = 0.0
	if coolant_cap > 0.0:
		fill = clamp(coolant / coolant_cap, 0.0, 1.0)
	cool += COOLANT_COOL_FULL_PER_SEC * fill

	# Idle bonus after a few seconds without ignitions
	if _time_since_ignite >= IDLE_COOL_DELAY:
		cool += IDLE_COOL_PER_SEC

	# Venting bonus
	if is_venting:
		# deterministic drop: ~VENT_DROP_TOTAL over VENT_DURATION_SEC
		var vent_rate: float = VENT_DROP_TOTAL / max(VENT_DURATION_SEC, 0.001)
		var step: float = vent_rate * delta
		if step > _vent_cool_remaining:
			step = _vent_cool_remaining
		_vent_cool_remaining -= step
		set_heat(_heat - step)
		return   # skip normal warm/cool while venting
	
	# Fuel: optional passive refill
	if FUEL_REFILL_PER_SEC > 0.0 and _fuel < fuel_cap:
		add_fuel(FUEL_REFILL_PER_SEC * delta)

	# Coolant: baseline pump + extra when actually cooling, + big use while venting
	var cool_use: float = COOLANT_USE_PER_SEC_BASE
	var warm: float = AMBIENT_WARM_PER_SEC * (HEAT_START - _heat)
	
	if _heat > HEAT_START:
		cool_use += COOLANT_USE_PER_SEC_WHEN_COOLING * ((_heat - HEAT_START) / 50.0)  # scales with how hot
	if is_venting:
		cool_use += COOLANT_USE_PER_SEC_WHEN_VENT
	if cool_use > 0.0 and _coolant > 0.0:
		add_coolant(-cool_use * delta)  # note the minus: using coolant	

	# Gentle drift back toward the ambient target (HEAT_START)
	if is_venting:
		warm = 0.0   # don't fight the vent
	
	# Optional passive refill if you want visible motion for now
	if COOLANT_REFILL_PER_SEC > 0.0 and _coolant < coolant_cap and not is_venting:
		add_coolant(COOLANT_REFILL_PER_SEC * delta)

	var dheat: float = (warm - cool) * delta
	heat = _heat + dheat

# ---- FUEL/COOLING ----

func add_fuel(d: float) -> void:
	fuel = _fuel + d

func add_coolant(d: float) -> void:
	coolant = _coolant + d

# ---- SIM TICK ----

func sim_tick(dt: float) -> void:
	# --- pulsed production from pillars ---
	var produced_eu: float = 0.0
	var heat_pulse: float = 0.0
	var total_heat_s: float = BASE_HEAT_S

	var gstats: Dictionary = base_stats()
	apply_mods(gstats, global_mods())
	var interval: float = effective_interval(gstats)

	for i in range(pillars.size()):
		var p: Dictionary = pillars[i]
		if not bool(p.get("unlocked", false)) or not bool(p.get("enabled", false)):
			continue

		# accumulate time
		p["timer"] = float(p.get("timer", 0.0)) + dt

		# fire as many times as interval allows
		var fired: bool = false
		while float(p["timer"]) >= interval:
			# fuel gate
			var fuel_need: float = PILLAR_FUEL_PULSE * (float(gstats.get("fuel_mult", 1.0)) + float(gstats.get("fuel_add", 0.0)))
			if fuel < fuel_need:
				break
			p["timer"] = float(p["timer"]) - interval
			fuel -= fuel_need
			fired = true

			# per-pillar stats
			var stats: Dictionary = base_stats()
			apply_mods(stats, [
				{"stat":"eu_mult","op":"mul","value": float(gstats.get("eu_mult", 1.0)) - 1.0},
				{"stat":"heat_mult","op":"mul","value": float(gstats.get("heat_mult", 1.0)) - 1.0}
			])
			apply_mods(stats, pillar_mods(i))

			var level_mult: float = 1.0 + float(p.get("level", 0)) * PILLAR_LEVEL_BONUS
			var eu_gain: float = (PILLAR_PULSE_EU * level_mult * float(stats.get("eu_mult", 1.0))) + float(stats.get("eu_add", 0.0))
			produced_eu += eu_gain
			heat_pulse += (PILLAR_PULSE_HEAT + float(stats.get("heat_add", 0.0))) * float(stats.get("heat_mult", 1.0))

		if fired:
			emit_signal("pillar_fired", i)

	# apply outputs
	eu += produced_eu
	if dt > 0.0:
		total_heat_s += heat_pulse / dt

	# cooling & heat application
	var coolant_flow: float = 1.0 if coolant > 0.0 else 0.0
	var cooling_s: float = coolant_flow * COOLANT_POWER
	var heat_s: float = total_heat_s + produced_eu * HEAT_FACTOR
	heat += (heat_s - cooling_s) * dt
	if coolant_flow > 0.0:
		coolant = max(0.0, coolant - 0.2 * dt)

	# auto-sell
	var sell_eu: float = eu * float(flags.get("auto_sell_ratio", 0.0))
	if sell_eu > 0.0:
		eu -= sell_eu
		money += (sell_eu / 10.0) * current_price()

	emit_signal("state_changed")


#  ---- ECONOMY STUFF ----

func current_price() -> float:
	var price_mult := 1.0 + float(research.get("market_i", 0)) * 0.05
	return PRICE_PER_10_EU * price_mult

func do_click() -> void:
	eu += CLICK_BONUS
	emit_signal("state_changed")

func can_afford(cost: Dictionary) -> bool:
	if cost.has("eu") and eu < float(cost["eu"]):
		return false
	if cost.has("money") and money < float(cost["money"]):
		return false
	return true

func pay(cost: Dictionary) -> void:
	if cost.has("eu"):
		eu -= float(cost["eu"]) 
	if cost.has("money"):
		money -= float(cost["money"]) 



# ---- SAVE/LOAD ----

const SAVE_PATH := "user://savegame.json"

func save_game() -> void:
	var data: Dictionary = {
		"eu": eu,
		"money": money,
		"fuel": fuel,
		"coolant": coolant,
		"fuel_cap": fuel_cap,
		"coolant_cap": coolant_cap,
		"heat": heat,
		"pillars": pillars,
		"research_levels": research_levels
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		print("Saved:", SAVE_PATH)

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed

	eu = float(d.get("eu", eu))
	money = float(d.get("money", money))
	fuel = float(d.get("fuel", fuel))
	coolant = float(d.get("coolant", coolant))
	fuel_cap = float(d.get("fuel_cap", fuel_cap))
	coolant_cap = float(d.get("coolant_cap", coolant_cap))
	heat = float(d.get("heat", heat))

	var p_any: Variant = d.get("pillars", pillars)
	if typeof(p_any) == TYPE_ARRAY:
		pillars = p_any
	else:
		pillars = []

	var rl_any: Variant = d.get("research_levels", research_levels)
	if typeof(rl_any) == TYPE_DICTIONARY:
		research_levels = rl_any
	else:
		research_levels = {}

	ensure_pillars(PILLAR_COUNT)   # keep model sane

	state_changed.emit()
	if has_signal("eu_changed"):
		eu_changed.emit(eu)
	print("Loaded:", SAVE_PATH)
	return true

func reset_save() -> void:
	# delete file if present, then reset to defaults
	if FileAccess.file_exists(SAVE_PATH):
		var abs: String = ProjectSettings.globalize_path(SAVE_PATH)
		var rc: int = DirAccess.remove_absolute(abs)
		if rc == OK:
			print("Removed save:", abs)
		else:
			push_warning("Couldn't remove save (%s), code=%d" % [abs, rc])
	reset_state_defaults()

		



#  ---- PILLAR STUFF ----

signal pillar_fired(idx: int)
const PILLAR_COUNT := 6

func ensure_pillars(count: int = PILLAR_COUNT) -> void:
	# Grow with sensible defaults
	while pillars.size() < count:
		var i := pillars.size()
		pillars.append({
			"unlocked": i == 0,  # first pillar unlocked by default
			"level": 0,
			"on": i == 0,
		})

func get_pillar(i: int) -> Dictionary:
	ensure_pillars(i + 1)
	return pillars[i]

func set_pillar(i: int, d: Dictionary) -> void:
	ensure_pillars(i + 1)
	pillars[i] = d
	if has_signal("state_changed"):
		state_changed.emit()

func unlock_cost(idx: int) -> Dictionary:
	# 100, 200, 300 Eu… tweak to taste
	return {"eu": 100.0 * (idx + 1)}

func unlock_pillar(idx: int) -> void:
	if idx <= 0: # Pillar 1 starts unlocked
		return
	if idx < pillars.size() and not pillars[idx]["unlocked"]:
		var cost := unlock_cost(idx)
		if not can_afford(cost):
			return
		pay(cost)
		pillars[idx]["unlocked"] = true
		emit_signal("state_changed")

func effective_interval(gstats: Dictionary) -> float:
	var rate: float = float(gstats.get("fire_rate_mult", 1.0))
	var interval: float = BASE_PILLAR_INTERVAL_S / max(0.1, rate)
	return float(max(MIN_PILLAR_INTERVAL_S, interval))

func pillar_pulse_eu(idx: int) -> float:
	var g: Dictionary = base_stats(); apply_mods(g, global_mods())
	var s: Dictionary = base_stats()
	apply_mods(s, [
		{"stat":"eu_mult","op":"mul","value": float(g.get("eu_mult",1.0)) - 1.0}
	])
	apply_mods(s, pillar_mods(idx))
	var lvl_mult: float = 1.0 + float(pillars[idx].get("level",0)) * PILLAR_LEVEL_BONUS
	return (PILLAR_PULSE_EU * lvl_mult * float(s.get("eu_mult",1.0))) + float(s.get("eu_add",0.0))


func init_pillars() -> void:
	if pillars.size() == 0:
		for i in range(NUM_PILLARS):
			pillars.append({
				"id": i,
				"level": 0,
				"enabled": i == 0,
				"unlocked": i == 0,
				"timer": 0.0
			})

func toggle_pillar(idx: int, on: bool) -> void:
	if idx >= 0 and idx < pillars.size():
		pillars[idx]["enabled"] = on

func pillar_upgrade_cost(level: int) -> Dictionary:
	# simple Eu cost curve: 50, 100, 150, ...
	return {"eu": 50.0 * (level + 1)}

func upgrade_pillar(idx: int) -> void:
	if idx < 0 or idx >= pillars.size():
		return
	var lvl: int = pillars[idx]["level"]
	var cost := pillar_upgrade_cost(lvl)
	if not can_afford(cost):
		return
	pay(cost)
	pillars[idx]["level"] = lvl + 1
	emit_signal("state_changed")
	
	
	
#  ---- RESEARCH STUFF ----
	
func _load_research_db() -> void:
	var f := FileAccess.open("res://data/research.json", FileAccess.READ)
	if f:
		research_db = JSON.parse_string(f.get_as_text())
		
func research_level(key: String) -> int:
	return int(research.get(key, 0))

func research_max_level(key: String) -> int:
	var node: Dictionary = research_db.get(key, {})
	var levels: Array = node.get("levels", [])
	return levels.size()

func research_cost(key: String) -> Dictionary:
	var lvl := research_level(key)
	var node: Dictionary = research_db.get(key, {})
	var levels: Array = node.get("levels", [])
	if lvl >= levels.size(): return {}
	return levels[lvl].get("cost", {})

func research_deps_satisfied(key: String) -> bool:
	var deps: Array = research_db.get(key, {}).get("deps", [])
	for d in deps:
		if research_level(String(d)) <= 0:
			return false
	return true

func research_available(key: String) -> bool:
	return research_deps_satisfied(key) and research_level(key) < research_max_level(key) and can_afford(research_cost(key))

func buy_research(key: String) -> void:
	if not research_db.has(key): return
	if not research_deps_satisfied(key): return

	var lvl := research_level(key)
	var max_lvl := research_max_level(key)
	if lvl >= max_lvl: return

	var level_def: Dictionary = research_db[key]["levels"][lvl]
	var cost: Dictionary = level_def.get("cost", {})
	if not can_afford(cost): return
	pay(cost)

	# apply immediate actions
	var unlock_def: Dictionary = level_def.get("unlock", {})
	if unlock_def.has("pillars"):
		for i in unlock_def["pillars"]:
			unlock_pillar(int(i))

	var ob: Dictionary = level_def.get("on_buy", {})
	if ob.has("fuel_cap_delta"):
		fuel_cap += float(ob["fuel_cap_delta"])
	if ob.has("coolant_cap_delta"):
		coolant_cap += float(ob["coolant_cap_delta"])

	# commit level
	research[key] = lvl + 1
	emit_signal("state_changed")
	save_game()


