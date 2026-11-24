extends RefCounted
## One scene-tree watcher shared by the mod's node_added consumers.
##
## The shop overlay gate and the shop highlighter both need to see nodes as they
## appear (and the nodes already present at startup). Instead of each connecting
## node_added and walking the tree, they subscribe here.

var _tree: SceneTree = null
var _subscribers: Array = []


func setup(tree: SceneTree) -> void:
	_tree = tree
	if _tree != null and not _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.connect(_on_node_added)


## Register `handler` and replay the existing tree to it once.
func subscribe(handler: Callable) -> void:
	if not _subscribers.has(handler):
		_subscribers.append(handler)
	if _tree != null and _tree.root != null:
		_scan(_tree.root)


func unsubscribe(handler: Callable) -> void:
	_subscribers.erase(handler)


func teardown() -> void:
	if _tree != null and _tree.node_added.is_connected(_on_node_added):
		_tree.node_added.disconnect(_on_node_added)
	_tree = null
	_subscribers.clear()


func _on_node_added(node: Node) -> void:
	for handler in _subscribers:
		handler.call(node)


func _scan(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_scan(child)
