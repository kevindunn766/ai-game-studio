extends Control

signal sell_clicked

var coins: float = 0.0:
    set(value):
        coins = value
        update_ui()

var per_click: int = 1:
    set(value):
        per_click = value
        update_ui()

var per_sec: float = 0.0:
    set(value):
        per_sec = value
        update_ui()

@onready var coins_label: Label = $CoinsLabel
@onready var per_click_label: Label = $PerClickLabel
@onready var per_sec_label: Label = $PerSecLabel
@onready var sell_button: Button = $SellButton
@onready var upgrades_container: VBoxContainer = $UpgradesContainer
@onready var rush_hour_label: Label = $RushHourLabel
@onready var prestige_label: Label = $PrestigeLabel
@onready var prestige_button: Button = $PrestigeButton

const SAVE_PATH = "user://lemonade_stand.json"
const AUTOSAVE_INTERVAL = 5.0
var _autosave_timer = 0.0

# Novelty twist: a random "Rush Hour" event triples income for a short
# window, giving idle-clicker players a reason to come back and actively
# click instead of just watching numbers climb passively.
const RUSH_HOUR_DURATION = 12.0
const RUSH_HOUR_MULTIPLIER = 3.0
const RUSH_HOUR_MIN_INTERVAL = 25.0
const RUSH_HOUR_MAX_INTERVAL = 45.0
var rush_hour_active = false
var rush_hour_timer = 0.0
var next_rush_hour_timer = 0.0

# Structural addition: a prestige loop ("Rebrew Recipe"). Lifetime coins
# earned this run build toward Recipe Points; cashing them in wipes coins,
# upgrades and per-click/per-sec back to their starting values but grants
# a permanent multiplier on all future coin gains, so runs compound across
# resets instead of the numbers just climbing forever in one long run.
const PRESTIGE_DIVISOR = 1000.0
const PRESTIGE_MULT_PER_POINT = 0.1
var total_earned: float = 0.0
var prestige_points: int = 0:
    set(value):
        prestige_points = value
        update_ui()

var upgrades = {
    "lemons": { "name": "Better Lemons", "cost": 10, "click": 1, "owned": 0 },
    "sugar": { "name": "Sugar Rush", "cost": 25, "click": 2, "owned": 0 },
    "tipjar": { "name": "Tip Jar", "cost": 50, "sec": 1, "owned": 0 },
    "helper": { "name": "Hired Helper", "cost": 150, "sec": 3, "owned": 0 },
    "franchise": { "name": "Franchise", "cost": 500, "sec": 10, "owned": 0 }
}

func _ready():
    load_save()
    sell_button.pressed.connect(_on_sell_pressed)
    prestige_button.pressed.connect(_on_prestige_pressed)
    render_upgrades()
    update_ui()
    process_mode = Node.PROCESS_MODE_ALWAYS
    rush_hour_label.visible = false
    next_rush_hour_timer = randf_range(RUSH_HOUR_MIN_INTERVAL, RUSH_HOUR_MAX_INTERVAL)

func _prestige_multiplier() -> float:
    return 1.0 + prestige_points * PRESTIGE_MULT_PER_POINT

func _pending_prestige_gain() -> int:
    return int(floor(sqrt(total_earned / PRESTIGE_DIVISOR)))

func _add_coins(amount: float):
    coins += amount
    total_earned += amount

func _process(delta):
    var effective_per_sec = per_sec * RUSH_HOUR_MULTIPLIER if rush_hour_active else per_sec
    effective_per_sec *= _prestige_multiplier()
    if effective_per_sec > 0:
        _add_coins(effective_per_sec * delta)
        update_ui()

    if rush_hour_active:
        rush_hour_timer -= delta
        if rush_hour_timer <= 0.0:
            _end_rush_hour()
        else:
            rush_hour_label.text = "RUSH HOUR! %dx COINS (%ds)" % [int(RUSH_HOUR_MULTIPLIER), ceil(rush_hour_timer)]
    else:
        next_rush_hour_timer -= delta
        if next_rush_hour_timer <= 0.0:
            _start_rush_hour()

    # Idle income and click income were never persisted on their own before
    # this fix - only buying an upgrade triggered a save, so closing the
    # game after just clicking/idling lost all of that progress. Autosave
    # periodically, and also on quit/background (see _notification below).
    _autosave_timer += delta
    if _autosave_timer >= AUTOSAVE_INTERVAL:
        _autosave_timer = 0.0
        save_game()

func _start_rush_hour():
    rush_hour_active = true
    rush_hour_timer = RUSH_HOUR_DURATION
    rush_hour_label.visible = true

func _end_rush_hour():
    rush_hour_active = false
    rush_hour_label.visible = false
    next_rush_hour_timer = randf_range(RUSH_HOUR_MIN_INTERVAL, RUSH_HOUR_MAX_INTERVAL)

func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        save_game()

func _on_sell_pressed():
    var effective_per_click = per_click * RUSH_HOUR_MULTIPLIER if rush_hour_active else per_click
    effective_per_click *= _prestige_multiplier()
    _add_coins(effective_per_click)
    update_ui()

func _on_prestige_pressed():
    var gain = _pending_prestige_gain()
    if gain < 1:
        return
    prestige_points += gain
    coins = 0.0
    total_earned = 0.0
    per_click = 1
    per_sec = 0.0
    for key in upgrades:
        upgrades[key].owned = 0
    render_upgrades()
    save_game()
    update_ui()

func update_ui():
    coins_label.text = "Coins: %d" % floor(coins)
    per_click_label.text = "Per click: %d" % per_click
    per_sec_label.text = "Per sec: %.1f" % per_sec
    prestige_label.text = "Recipe Points: %d  (x%.1f coins)" % [prestige_points, _prestige_multiplier()]
    var gain = _pending_prestige_gain()
    prestige_button.text = "Rebrew Recipe (+%d)" % gain
    prestige_button.disabled = gain < 1
    refresh_upgrade_buttons()

func render_upgrades():
    for child in upgrades_container.get_children():
        child.queue_free()

    for key in upgrades:
        var up = upgrades[key]
        var row = HBoxContainer.new()
        var info = Label.new()
        var next_cost = floor(up.cost * pow(1.15, up.owned))
        info.text = "%s\nOwned: %d | Next: %d coins" % [up.name, up.owned, next_cost]
        info.add_theme_color_override("font_color", Color(0.15, 0.12, 0.02, 1))
        row.add_child(info)

        var btn = Button.new()
        btn.text = "Buy"
        btn.pressed.connect(_buy_upgrade.bind(key))
        btn.name = "btn_" + key
        row.add_child(btn)

        upgrades_container.add_child(row)

    refresh_upgrade_buttons()

func refresh_upgrade_buttons():
    for key in upgrades:
        var up = upgrades[key]
        var next_cost = floor(up.cost * pow(1.15, up.owned))
        var btn = upgrades_container.get_node_or_null("btn_" + key)
        if btn:
            btn.disabled = coins < next_cost

func _buy_upgrade(key: String):
    var up = upgrades[key]
    var next_cost = floor(up.cost * pow(1.15, up.owned))
    if coins < next_cost:
        return
    coins -= next_cost
    up.owned += 1
    if up.has("click"):
        per_click += up.click
    if up.has("sec"):
        per_sec += up.sec
    save_game()
    update_ui()
    render_upgrades()

func save_game():
    var data = {
        "coins": coins,
        "per_click": per_click,
        "per_sec": per_sec,
        "total_earned": total_earned,
        "prestige_points": prestige_points,
        "upgrades": {}
    }
    for key in upgrades:
        data.upgrades[key] = upgrades[key].owned
    var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(data))
        file.close()

func load_save():
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return
    var text = file.get_as_text()
    file.close()
    var data = JSON.parse_string(text)
    if data == null or typeof(data) != TYPE_DICTIONARY:
        return
    coins = data.get("coins", 0)
    per_click = int(data.get("per_click", 1))
    per_sec = data.get("per_sec", 0.0)
    total_earned = data.get("total_earned", 0.0)
    prestige_points = int(data.get("prestige_points", 0))
    var saved_upgrades = data.get("upgrades", {})
    if typeof(saved_upgrades) == TYPE_DICTIONARY:
        for key in saved_upgrades:
            if upgrades.has(key):
                upgrades[key].owned = int(saved_upgrades[key])
