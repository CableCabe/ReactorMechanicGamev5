extends PanelContainer

@onready var sell_toggle: Button        = %SellToggle
@onready var buy_fuel_btn: Button       = %BuyFuelBtn
@onready var buy_coolant_btn: Button    = %BuyCoolantBtn
@onready var fuel_store_btn: Button     = %FuelStorageBtn
@onready var cool_store_btn: Button     = %CoolantStorageBtn
@onready var GS = get_node("/root/GameState")

func _ready() -> void:
	sell_toggle.toggle_mode = true
	sell_toggle.button_pressed = false
	sell_toggle.pressed.connect(_on_toggle_sell)

	buy_fuel_btn.pressed.connect(_on_buy_fuel)
	buy_coolant_btn.pressed.connect(_on_buy_coolant)
	fuel_store_btn.pressed.connect(_on_buy_fuel_storage)
	cool_store_btn.pressed.connect(_on_buy_coolant_storage)

	if GS.has_signal("money_changed"):
		GS.money_changed.connect(_refresh)
	if GS.has_signal("eu_changed"):
		GS.eu_changed.connect(_refresh)
	if GS.has_signal("state_changed"):
		GS.state_changed.connect(_refresh)

	_refresh()

func _refresh(_v: float = 0.0) -> void:
	# Current pack sizes
	var fuel_pack: float = GS.MKT_FUEL_PACK_AMOUNT
	var c_pack: float = GS.MKT_COOLANT_PACK_AMOUNT

	# Compute effective pack amount (don’t overfill; show partial)
	var fuel_space: float = max(0.0, GS.fuel_cap - GS.fuel)
	var cool_space: float = max(0.0, GS.coolant_cap - GS.coolant)
	var fuel_amt: float = min(fuel_pack, fuel_space)
	var cool_amt: float = min(c_pack, cool_space)

	var fuel_price: float = GS.market_fuel_price_for_amount(fuel_amt)
	var cool_price: float = GS.market_coolant_price_for_amount(cool_amt)

	buy_fuel_btn.text = "Buy Fuel (+%0.0f ml)  $%0.0f" % [fuel_amt, fuel_price]
	buy_coolant_btn.text = "Buy Coolant (+%0.0f ml)  $%0.0f" % [cool_amt, cool_price]

	fuel_store_btn.text = "Upgrade Fuel Storage (+%0.0f)  $%0.0f" % [GS.MKT_STORAGE_STEP, GS.market_fuel_storage_price()]
	cool_store_btn.text = "Upgrade Coolant Storage (+%0.0f)  $%0.0f" % [GS.MKT_STORAGE_STEP, GS.market_coolant_storage_price()]

	# Disable when unaffordable or full
	buy_fuel_btn.disabled = (fuel_amt <= 0.0) or (GS.money < fuel_price)
	buy_coolant_btn.disabled = (cool_amt <= 0.0) or (GS.money < cool_price)
	fuel_store_btn.disabled = GS.money < GS.market_fuel_storage_price()
	cool_store_btn.disabled = GS.money < GS.market_coolant_storage_price()

	# Sync toggle with model (selling is OFF by default)
	if "market_auto_sell" in GS:
		sell_toggle.button_pressed = GS.market_auto_sell
	if sell_toggle.button_pressed:
		sell_toggle.text = "Auto‑Sell: ON"
	else:
		sell_toggle.text = "Auto‑Sell: OFF"

func _on_toggle_sell() -> void:
	var on: bool = sell_toggle.button_pressed
	GS.set_market_auto_sell(on)
	_refresh()

func _on_buy_fuel() -> void:
	GS.market_buy_fuel_pack()

func _on_buy_coolant() -> void:
	GS.market_buy_coolant_pack()

func _on_buy_fuel_storage() -> void:
	GS.market_buy_fuel_storage()

func _on_buy_coolant_storage() -> void:
	GS.market_buy_coolant_storage()
