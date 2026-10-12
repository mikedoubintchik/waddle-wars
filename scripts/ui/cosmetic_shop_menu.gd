extends Control
## The shop is a routed screen, not a layer above still-interactive menu buttons.
## Creating it on demand keeps billing discovery off the boot/gameplay path.


const ShopScript = preload("res://scripts/commerce/premium_cosmetic_shop.gd")


func _ready() -> void:
	ExpeditionMenuStyle.add_backdrop(self, "shop")
	UITheme.apply_ui_scale(self)
	var shop := ShopScript.new()
	shop.closed.connect(_go_back, CONNECT_ONE_SHOT)
	add_child(shop)


func _go_back() -> void:
	SceneRouter.go_back()
