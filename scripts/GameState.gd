# scripts/GameState.gd (autoload singleton)
extends Node

# --- Core State ---

# DEBUG



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
var _in_pillar_tick := false  # set around the central pillar loop
var _eu_last_tick: float = 0.0
var _eu_rate_ps: float = 0.0

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
var _pillar_accum: Array = []            # per-pillar timers
var manual_ignite_enabled: bool = true
var auto_ignite_enabled: bool = true
var _auto_ignite_was_enabled: bool = true

const NUM_PILLARS := 6
const PILLAR_COUNT := 6
const BASE_PILLAR_INTERVAL_S := 2.0      # default time between ignitions
const MIN_PILLAR_INTERVAL_S  := 0.3      # clamp after research
const PILLAR_PULSE_EU        := 1.2      # Eu per ignition before multipliers
const PILLAR_PULSE_HEAT      := 0.6      # Heat contribution per ignition
const PILLAR_FUEL_PULSE      := 0.06     # Fuel burned per ignition
const PILLAR_LEVEL_BONUS     := 0.20     # +20% Eu per level (same as before)
const PILLAR_EU_BASE: float = 1.0         # Eu per shot at Lv1 (tweak)

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
const FUEL_START_FRAC: float = 0.90
const FUEL_PER_IGNITE: float = 0.01             # ml spent per manual ignite
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

const COOLANT_START_FRAC: float = 0.90
const COOLANT_USE_PER_SEC_BASE: float = 0.0     # baseline pump use
const COOLANT_USE_PER_SEC_WHEN_COOLING: float = 2.0   # extra when heat > ambient
const COOLANT_USE_PER_SEC_WHEN_VENT: float = 8.0      # extra while venting
const COOLANT_REFILL_PER_SEC: float = 0.0       # set >0 for passive refill
const COOLANT_POWER := 0.6
const COOLANT_CAP  := 1000.0   
const COOLANT_PER_IGNITE: float = 0.02

# HEAT
const BASE_HEAT_S := 0.4
const HEAT_FACTOR := 0.02
const HEAT_START: float = 50.0
const BASE_COOL_PER_SEC: float = 1.5
const COOLANT_COOL_FULL_PER_SEC: float = 8.0
const IDLE_COOL_DELAY: float = 3.0
const IDLE_COOL_PER_SEC: float = 4.0
const AMBIENT_WARM_PER_SEC: float = 1.0
const IGNITE_HEAT_PULSE: float = 0.3

var underheat: float = 25
var overheat: float = 75

# VENTING
const VENT_COOL_PER_SEC: float = 6.5
const VENT_DURATION_SEC: float = 8.0
const VENT_DROP_TOTAL: float = 14.0

var is_venting: bool = false
var _vent_timer: Timer
var _vent_cool_remaining: float = 0.0
var _vent_rate: float = 0.0

@export var vent_duration: float = 8.0

# Fixed‑timestep accumulator (10 Hz)
const STEP := 0.1
var _accum := 0.0
var _time_since_ignite: float = 0.0

# MARKET
const SELL_EU_RATE: float = 0.10                # $ per 1 Eu when selling
const AUTO_SELL_RATE_EU_PER_SEC: float = 2.0    # Eu/s while auto‑sell is ON

const MKT_FUEL_PACK_AMOUNT: float = 50.0
const MKT_COOLANT_PACK_AMOUNT: float = 50.0

const MKT_FUEL_PACK_BASE_COST: float = 25.0
const MKT_COOLANT_PACK_BASE_COST: float = 25.0

const MKT_STORAGE_STEP: float = 100.0
const MKT_FUEL_STORAGE_BASE_COST: float = 60.0
const MKT_COOLANT_STORAGE_BASE_COST: float = 60.0

var market_auto_sell: bool = false
var _market_fuel_buys: int = 0
var _market_coolant_buys: int = 0
var _market_fuel_store_buys: int = 0
var _market_coolant_store_buys: int = 0

var _market_timer: Timer


# ---- SIGNALS ----
signal research_loaded
signal state_changed
signal eu_changed(value)
signal heat_changed(value)
signal venting_started
signal venting_finished
signal fuel_changed(value)
signal coolant_changed(value)
signal pillar_fired(idx: int)
signal money_changed(value)
signal fuel_empty
signal pillar_no_fuel(pillar_path: NodePath)
signal eu_tick_generated(amount: float)   # Eu produced this sim tick (pillars only)
signal eu_rate_changed(per_sec: float)    # instantaneous Eu/s based on last tick


# ---- DEBUG ----




# ---- READY ----
func _ready() -> void:
	set_process(true)
	# Create a private, non-autostart timer so nothing fires early
	_vent_timer = Timer.new()
	_vent_timer.name = "VentTimerPriv"
	_vent_timer.one_shot = true
	_vent_timer.autostart = false
	add_child(_vent_timer)
	_vent_timer.timeout.connect(_on_vent_timeout)

# ---- LOADING ----
func _enter_tree() -> void:
	set_process(true)
	reset_state_defaults()
	ensure_pillars(PILLAR_COUNT)
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
	_market_timer = Timer.new()
	_market_timer.wait_time = 0.5
	_market_timer.one_shot = false
	add_child(_market_timer)
	_market_timer.timeout.connect(_on_market_timeout)
	_market_timer.start()	
	
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
		#print("Loaded research entries:", research_db.size())
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
	if _heat < underheat or _heat > overheat:
		return 0.5
	return 1.0



# ---- VENTING ----

func start_vent() -> void:
	# prevent re-entry if already venting or timer active
	if is_venting:
		return
	if _vent_timer and _vent_timer.time_left > 0.0:
		return

	is_venting = true
	_auto_ignite_was_enabled = auto_ignite_enabled
	auto_ignite_enabled = false
	manual_ignite_enabled = false

	# planned total drop over duration -> per-second rate
	_vent_cool_remaining = max(0.0, VENT_DROP_TOTAL)
	_vent_rate = 0.0
	if vent_duration > 0.0:
		_vent_rate = VENT_DROP_TOTAL / vent_duration

	emit_signal("venting_started")
	get_tree().call_group("reaction_pillars", "_vent_lock")

	if not _vent_timer:
		_vent_timer = Timer.new()
		_vent_timer.one_shot = true
		add_child(_vent_timer)
		_vent_timer.timeout.connect(_on_vent_timeout)

	_vent_timer.stop()
	_vent_timer.wait_time = max(0.01, vent_duration)
	_vent_timer.start()

func _on_vent_timeout() -> void:
	# finish only once
	if not is_venting:
		return
	is_venting = false
	_vent_cool_remaining = 0.0
	_vent_rate = 0.0
	auto_ignite_enabled = _auto_ignite_was_enabled
	manual_ignite_enabled = true
	emit_signal("venting_finished")
	get_tree().call_group("reaction_pillars", "_vent_unlock")
	_ignite_sanity() 

func _ignite_sanity() -> void:
	# If we are not venting, manual ignite should be allowed
	if not is_venting and not manual_ignite_enabled:
		manual_ignite_enabled = true




# ---- PROCESSES ----

func _process(delta: float) -> void:
	
	# DEBUGGING
	
	
	# MAIN
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
	if is_venting and heat > 0.0:
		var old := heat
		heat = max(0.0, heat - _vent_rate * delta)
		if heat != old:
			emit_signal("heat_changed", heat)
	
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
	
	_ignite_sanity() 
	
	var dheat: float = (warm - cool) * delta
	heat = _heat + dheat

# ---- FUEL ----

func add_fuel(amount: float) -> void:
	if amount <= 0.0:
		return
	fuel += amount
	if fuel > fuel_cap:
		fuel = fuel_cap
	emit_signal("fuel_changed", fuel)

func consume_fuel(amount: float, who: Node = null) -> bool:
	if amount <= 0.0:
		return true
	if fuel >= amount:
		fuel -= amount
		emit_signal("fuel_changed", fuel)
		if fuel <= 0.0:
			emit_signal("fuel_empty")
		return true
	# Not enough fuel
	emit_signal("fuel_empty")
	if who != null:
		emit_signal("pillar_no_fuel", who.get_path())
	return false



# ---- COOLING ----

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

		if is_venting:
			continue
			
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

	if dt > 0.0:
		total_heat_s += heat_pulse / dt
		_eu_last_tick = produced_eu
		_eu_rate_ps = produced_eu / dt
		if produced_eu > 0.0:
			_eu_last_tick = produced_eu
			_eu_rate_ps = produced_eu / dt
			eu_tick_generated.emit(_eu_last_tick)
			eu_rate_changed.emit(_eu_rate_ps)

	if produced_eu > 0.0:
		add_eu(produced_eu, "pillar_sim")   # reason starts with "pillar_…" if you prefer


	# Vent cooling happens AFTER (and now there’s no production during vent)
	if is_venting:
		var step: float = _vent_rate * dt
		if step > _vent_cool_remaining:
			step = _vent_cool_remaining
		_vent_cool_remaining -= step
		set_heat(heat - step)  # setter so UI updates
		if _vent_cool_remaining <= 0.0:
			_on_vent_timeout()
		return  # skip normal cooling and pillar effects while venting

		

	# cooling & heat application
	var coolant_flow: float = 1.0 if coolant > 0.0 else 0.0
	var cooling_s: float = coolant_flow * COOLANT_POWER
	var heat_s: float = total_heat_s + produced_eu * HEAT_FACTOR
	heat += (heat_s - cooling_s) * dt
	if coolant_flow > 0.0:
		coolant = max(0.0, coolant - 0.2 * dt)

	emit_signal("state_changed")
	
# DEBUG




	
func _count_enabled_pillars() -> int:
	var c: int = 0
	for p in pillars:
		if bool(p.get("unlocked", false)) and bool(p.get("enabled", true)):
			c += 1
	return c




#  ---- ECONOMY STUFF ----

func add_eu(amount: float, reason: String = "") -> void:
	if amount == 0.0:
		return

	# keep your vent guard for pillar sim
	if is_venting and (_in_pillar_tick or reason.begins_with("pillar")):
		return

	eu += amount
	eu_changed.emit(eu)

	# Feed Eu/t for everything that didn't come from the sim_tick produced_eu path
	# (that path uses reason == "pillar_sim")
	if amount > 0.0 and reason != "pillar_sim":
		_eu_last_tick = amount
		eu_tick_generated.emit(amount)
		if STEP > 0.0:
			_eu_rate_ps = amount / STEP
			eu_rate_changed.emit(_eu_rate_ps)

func spend_eu(a: float) -> bool:
	if _eu >= a:
		eu = _eu - a
		return true
	return false

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

func get_eu_last_tick() -> float:
	return _eu_last_tick

func get_eu_rate_ps() -> float:
	return _eu_rate_ps


# ---- MARKET ----

func add_money(d: float) -> void:
	money = money + d
	money_changed.emit(money)

func spend_money(cost: float) -> bool:
	if money < cost:
		return false
	money = money - cost
	money_changed.emit(money)
	return true

func set_market_auto_sell(on: bool) -> void:
	market_auto_sell = on

func sell_eu(amount: float, force: bool = false) -> float:
	if not force and not market_auto_sell:
		return 0.0

	var a: float = clamp(amount, 0.0, eu)
	if a <= 0.0:
		return 0.0
	eu -= a
	eu_changed.emit(eu)
	var earned: float = a * SELL_EU_RATE
	add_money(earned)
	return earned

func _on_market_timeout() -> void:
	if not market_auto_sell:
		return
	var dt: float = _market_timer.wait_time
	var to_sell: float = AUTO_SELL_RATE_EU_PER_SEC * dt
	sell_eu(to_sell)   # flag-gated by sell_eu itself


func market_fuel_price() -> float:
	return MKT_FUEL_PACK_BASE_COST * pow(1.15, float(_market_fuel_buys))

func market_coolant_price() -> float:
	return MKT_COOLANT_PACK_BASE_COST * pow(1.15, float(_market_coolant_buys))

func market_fuel_storage_price() -> float:
	return MKT_FUEL_STORAGE_BASE_COST * pow(1.25, float(_market_fuel_store_buys))

func market_coolant_storage_price() -> float:
	return MKT_COOLANT_STORAGE_BASE_COST * pow(1.25, float(_market_coolant_store_buys))

# New: proportional price helpers for partial packs
func market_fuel_price_for_amount(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var pack: float = MKT_FUEL_PACK_AMOUNT
	var frac: float = clamp(amount / pack, 0.0, 1.0)
	return market_fuel_price() * frac

func market_coolant_price_for_amount(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var pack: float = MKT_COOLANT_PACK_AMOUNT
	var frac: float = clamp(amount / pack, 0.0, 1.0)
	return market_coolant_price() * frac

func market_buy_fuel_pack() -> bool:
	var space: float = max(0.0, fuel_cap - fuel)
	var amount: float = min(MKT_FUEL_PACK_AMOUNT, space)
	if amount <= 0.0:
		return false
	var cost: float = market_fuel_price_for_amount(amount)
	if not spend_money(cost):
		return false
	add_fuel(amount)
	_market_fuel_buys += 1
	return true

func market_buy_coolant_pack() -> bool:
	var space: float = max(0.0, coolant_cap - coolant)
	var amount: float = min(MKT_COOLANT_PACK_AMOUNT, space)
	if amount <= 0.0:
		return false
	var cost: float = market_coolant_price_for_amount(amount)
	if not spend_money(cost):
		return false
	add_coolant(amount)
	_market_coolant_buys += 1
	return true

func market_buy_fuel_storage() -> bool:
	var cost: float = market_fuel_storage_price()
	if not spend_money(cost):
		return false
	fuel_cap = fuel_cap + MKT_STORAGE_STEP
	_market_fuel_store_buys += 1
	state_changed.emit()    # let UIs refresh capacity
	return true

func market_buy_coolant_storage() -> bool:
	var cost: float = market_coolant_storage_price()
	if not spend_money(cost):
		return false
	coolant_cap = coolant_cap + MKT_STORAGE_STEP
	_market_coolant_store_buys += 1
	state_changed.emit()
	return true

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
		"research_levels": research_levels,
		"market": {
			"auto_sell": market_auto_sell,
	   		"fuel_buys": _market_fuel_buys,
	   		"coolant_buys": _market_coolant_buys,
	   		"fuel_store_buys": _market_fuel_store_buys,
			"coolant_store_buys": _market_coolant_store_buys
		}
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		print("Saved:", SAVE_PATH)

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	if not f:
		return false
	if d.has("market"):
		var m: Dictionary = d.get("market")
		market_auto_sell = bool(m.get("auto_sell", false))
		_market_fuel_buys = int(m.get("fuel_buys", 0))
		_market_coolant_buys = int(m.get("coolant_buys", 0))
		_market_fuel_store_buys = int(m.get("fuel_store_buys", 0))
		_market_coolant_store_buys = int(m.get("coolant_store_buys", 0))
	else:
		market_auto_sell = false
		_market_fuel_buys = 0
		_market_coolant_buys = 0
		_market_fuel_store_buys = 0
		_market_coolant_store_buys = 0

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

func ensure_pillars(n: int) -> void:
	while pillars.size() < n:
		var i: int = pillars.size()
		pillars.append({
			"unlocked": i == 0,
			"level": 1,
			"enabled": false,   # ← was true; start OFF so UI and model agree
			"timer": 0.0
		})
	while _pillar_accum.size() < n:
		_pillar_accum.append(0.0)

func get_pillar(i: int) -> Dictionary:
	if i < 0 or i >= pillars.size():
		return {}
	return pillars[i]

func set_pillar_enabled(i: int, on: bool) -> void:
	if i < 0 or i >= pillars.size():
		return
	pillars[i]["enabled"] = on


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

func _pillar_interval(i: int) -> float:
	var p: Dictionary = get_pillar(i)
	var lvl: int = int(p.get("level", 1))
	var lvl_mult: float = max(0.4, 1.0 - 0.10 * float(lvl - 1))   # faster with level
	var rate_mult: float = heat_rate_mult()                       # 0.5 outside sweet spot
	if rate_mult <= 0.0:
		rate_mult = 0.01
	return BASE_PILLAR_INTERVAL_S * lvl_mult / rate_mult


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

	var lvt: int = int(pillars[idx].get("level", 0))

	# cost is a DICTIONARY (e.g. {"eu": 50.0})
	var cost: Dictionary = pillar_upgrade_cost(lvt)

	if not can_afford(cost):
		return
	pay(cost)  # uses your existing multi-currency deduction

	pillars[idx]["level"] = lvt + 1
	emit_signal("state_changed")
	emit_signal("eu_changed", eu)
	
func _tick_pillars(dt: float) -> void:
	if is_venting:
		#print("trip")
		return
	else:
		var count: int = min(PILLAR_COUNT, pillars.size())
		_in_pillar_tick = true
		for i in range(count):
			var p: Dictionary = pillars[i]
			if not bool(p.get("unlocked", false)): continue
			if not bool(p.get("enabled", true)):   continue

			_pillar_accum[i] += dt
			var need: float = _pillar_interval(i)
			if _pillar_accum[i] < need: continue
			_pillar_accum[i] -= need

			var lvl  := int(p.get("level", 1))
			var gain := PILLAR_EU_BASE * float(lvl)
	
			add_eu(gain, "pillar_%d" % i)
			add_heat_pulse(IGNITE_HEAT_PULSE * 0.25)

			pillar_fired.emit(i)  # flash hook (UI listens to this)
		_in_pillar_tick = false

	
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


