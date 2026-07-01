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

const SAVE_PATH = "user://lemonade_stand.json"

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
    render_upgrades()
    update_ui()
    process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta):
    if per_sec > 0:
        coins += per_sec * delta
        update_ui()

func _on_sell_pressed():
    coins += per_click
    update_ui()

func update_ui():
    coins_label.text = "Coins: %d" % floor(coins)
    per_click_label.text = "Per click: %d" % per_click
    per_sec_label.text = "Per sec: %.1f" % per_sec
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
    var saved_upgrades = data.get("upgrades", {})
    if typeof(saved_upgrades) == TYPE_DICTIONARY:
        for key in saved_upgrades:
            if upgrades.has(key):
                upgrades[key].owned = int(saved_upgrades[key])
