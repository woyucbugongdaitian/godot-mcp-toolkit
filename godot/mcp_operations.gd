extends SceneTree

var request_path := ""
var response_path := ""

func _initialize() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() < 2:
		quit_with_error("Expected request and response file arguments")
		return
	request_path = user_args[0]
	response_path = user_args[1]
	var request_variant = JSON.parse_string(FileAccess.get_file_as_string(request_path))
	if request_variant == null or not request_variant is Dictionary:
		quit_with_error("Request JSON is invalid")
		return
	var response := execute_operation(request_variant)
	var file := FileAccess.open(response_path, FileAccess.WRITE)
	if file == null:
		quit_with_error("Cannot write response file")
		return
	file.store_string(JSON.stringify(response))
	file.close()
	quit(0 if response.get("ok", false) else 1)

func execute_operation(request: Dictionary) -> Dictionary:
	var operation := String(request.get("operation", ""))
	var result = null
	match operation:
		"create_scene":
			result = create_scene(request)
		"inspect_scene_tree":
			result = inspect_scene_tree(request)
		"inspect_node":
			result = inspect_node(request)
		"edit_scene":
			result = edit_scene(request)
		"save_scene":
			result = save_scene_only(request)
		"load_sprite":
			result = edit_scene(request)
		"get_uid":
			result = get_uid(request)
		"update_project_uids":
			result = update_project_uids(request)
		"capture_screenshot":
			result = capture_screenshot(request)
		"create_animation":
			result = create_animation(request)
		"inspect_animation_players":
			result = inspect_animation_players(request)
		"inspect_tilemaps":
			result = inspect_tilemaps(request)
		"set_tile_cell":
			result = set_tile_cell(request)
		"simulate_input":
			result = simulate_input(request)
		"profile_scene":
			result = profile_scene(request)
		_:
			return {"ok": false, "error": "Unknown operation: %s" % operation}
	if result is Dictionary and result.has("error"):
		return {"ok": false, "error": result.error, "details": result}
	return {"ok": true, "schemaVersion": 1, "godot": compatibility_report(), "result": result}

func compatibility_report() -> Dictionary:
	var version_info := Engine.get_version_info()
	return {
		"version": String(version_info.get("string", "unknown")),
		"major": int(version_info.get("major", 0)),
		"minor": int(version_info.get("minor", 0)),
		"features": {
			"tile_map_layer": ClassDB.class_exists("TileMapLayer"),
			"animation_library": ClassDB.class_exists("AnimationLibrary"),
			"resource_uid": ClassDB.class_exists("ResourceUID"),
		},
	}

func create_scene(request: Dictionary):
	var scene_path := String(request.get("scenePath", ""))
	if scene_path.is_empty():
		return {"error": "scenePath is required"}
	var root_type := String(request.get("rootType", "Node2D"))
	var root_name := String(request.get("rootName", "Main"))
	var root := create_node(root_type, root_name)
	if root == null:
		return {"error": "Unsupported root type: %s" % root_type}
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK:
		return {"error": "Cannot pack scene: %s" % pack_error}
	var save_error := ResourceSaver.save(packed, scene_path)
	if save_error != OK:
		return {"error": "Cannot save scene %s: %s" % [scene_path, save_error]}
	return {"scenePath": scene_path, "rootType": root_type, "rootName": root_name, "saved": true}

func inspect_scene_tree(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var max_depth := clampi(int(request.get("maxDepth", 8)), 0, 32)
	var tree := describe_node(root, 0, max_depth)
	root.free()
	return {"scenePath": request.get("scenePath", ""), "tree": tree}

func inspect_node(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var node_path := NodePath(String(request.get("nodePath", ".")))
	var node := root.get_node_or_null(node_path)
	if node == null:
		root.free()
		return {"error": "Node not found: %s" % node_path}
	var result := describe_node_properties(node)
	root.free()
	return result

func edit_scene(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var operation := String(request.get("operation", "edit_scene"))
	var result := {}
	if operation == "add_node":
		var parent_path := NodePath(String(request.get("parentPath", ".")))
		var parent := root.get_node_or_null(parent_path)
		if parent == null:
			root.free()
			return {"error": "Parent node not found: %s" % parent_path}
		var child := create_node(String(request.get("nodeType", "Node")), String(request.get("nodeName", "Node")))
		if child == null:
			root.free()
			return {"error": "Unsupported node type"}
		parent.add_child(child)
		child.owner = root
		apply_properties(child, request.get("properties", {}))
		result = {"added": child.get_path().to_string(), "nodeType": child.get_class()}
	elif operation == "remove_node":
		var node := root.get_node_or_null(NodePath(String(request.get("nodePath", ""))))
		if node == null or node == root:
			root.free()
			return {"error": "Node not found or root cannot be removed"}
		var removed_path := node.get_path().to_string()
		node.get_parent().remove_child(node)
		node.free()
		result = {"removed": removed_path}
	elif operation == "set_node_property":
		var target := root.get_node_or_null(NodePath(String(request.get("nodePath", ""))))
		if target == null:
			root.free()
			return {"error": "Node not found: %s" % request.get("nodePath", "")}
		var property_name := String(request.get("property", ""))
		if not _has_property(target, property_name):
			root.free()
			return {"error": "Property not found: %s" % property_name}
		target.set(property_name, decode_value(request.get("value")))
		result = {"nodePath": request.get("nodePath", ""), "property": property_name, "set": true}
	elif operation == "load_sprite":
		var sprite_parent := root.get_node_or_null(NodePath(String(request.get("parentPath", "."))))
		if sprite_parent == null:
			root.free()
			return {"error": "Parent node not found"}
		var sprite := Sprite2D.new()
		sprite.name = String(request.get("nodeName", "Sprite2D"))
		var texture = load(String(request.get("texturePath", "")))
		if texture == null:
			root.free()
			return {"error": "Texture not found: %s" % request.get("texturePath", "")}
		sprite.texture = texture
		sprite_parent.add_child(sprite)
		sprite.owner = root
		result = {"added": sprite.get_path().to_string(), "texturePath": request.get("texturePath", "")}
	var save_result := save_root(root, String(request.get("scenePath", "")))
	root.free()
	if save_result.has("error"):
		return save_result
	result["saved"] = true
	return result

func save_root(root: Node, scene_path: String) -> Dictionary:
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		return {"error": "Cannot pack scene: %s" % pack_error}
	var save_error := ResourceSaver.save(packed, scene_path)
	if save_error != OK:
		return {"error": "Cannot save scene: %s" % save_error}
	return {"saved": true}

func save_scene_only(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var result := save_root(loaded.root, String(request.get("scenePath", "")))
	loaded.root.free()
	return result

func load_scene(request: Dictionary) -> Dictionary:
	var scene_path := String(request.get("scenePath", ""))
	if scene_path.is_empty():
		return {"error": "scenePath is required"}
	var packed = load(scene_path)
	if packed == null or not packed is PackedScene:
		return {"error": "Scene cannot be loaded: %s" % scene_path}
	var root := packed.instantiate()
	if root == null:
		return {"error": "Scene cannot be instantiated: %s" % scene_path}
	return {"root": root}

func create_node(node_type: String, node_name: String) -> Node:
	var object = ClassDB.instantiate(node_type)
	if object == null or not object is Node:
		return null
	var node: Node = object
	node.name = node_name
	return node

func describe_node(node: Node, depth: int, max_depth: int) -> Dictionary:
	var item := {
		"name": node.name,
		"path": node.get_path().to_string(),
		"type": node.get_class(),
		"owner": node.owner == null ? "" : node.owner.name,
		"children": [],
	}
	if depth >= max_depth:
		item["truncated"] = node.get_child_count() > 0
		return item
	for child in node.get_children():
		item["children"].append(describe_node(child, depth + 1, max_depth))
	return item

func describe_node_properties(node: Node) -> Dictionary:
	var properties := {}
	for property in node.get_property_list():
		var property_name := String(property.name)
		if property_name in ["script", "owner"]:
			continue
		var value = node.get(property_name)
		properties[property_name] = serialize_value(value)
	return {"name": node.name, "path": node.get_path().to_string(), "type": node.get_class(), "properties": properties}

func serialize_value(value):
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return {"type": "Vector2", "value": [value.x, value.y]}
	if value is Vector2i:
		return {"type": "Vector2i", "value": [value.x, value.y]}
	if value is Vector3:
		return {"type": "Vector3", "value": [value.x, value.y, value.z]}
	if value is Color:
		return {"type": "Color", "value": value.to_html(true)}
	if value is NodePath:
		return {"type": "NodePath", "value": String(value)}
	if value is Array:
		var array_result := []
		for item in value:
			array_result.append(serialize_value(item))
		return array_result
	if value is Dictionary:
		var dictionary_result := {}
		for key in value.keys():
			dictionary_result[String(key)] = serialize_value(value[key])
		return dictionary_result
	if value is Resource and not value.resource_path.is_empty():
		return {"resourcePath": value.resource_path}
	return str(value)

func apply_properties(node: Node, properties) -> void:
	if not properties is Dictionary:
		return
	for key in properties.keys():
		var property_name := String(key)
		if _has_property(node, property_name):
			node.set(property_name, decode_value(properties[key]))

func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.name) == property_name:
			return true
	return false

func decode_value(value):
	if value is Dictionary:
		if value.has("type") and value.has("value"):
			var type_name := String(value.type).to_lower()
			if type_name == "vector2":
				return Vector2(float(value.value[0]), float(value.value[1]))
			if type_name == "vector3":
				return Vector3(float(value.value[0]), float(value.value[1]), float(value.value[2]))
			if type_name == "color":
				return Color.from_string(String(value.value), Color.WHITE)
			if type_name == "nodepath":
				return NodePath(String(value.value))
		if value.has("resourcePath"):
			return load(String(value.resourcePath))
		var decoded := {}
		for key in value.keys():
			decoded[key] = decode_value(value[key])
		return decoded
	if value is Array:
		var decoded_array := []
		for item in value:
			decoded_array.append(decode_value(item))
		return decoded_array
	return value

func get_uid(request: Dictionary):
	if not ClassDB.class_exists("ResourceUID"):
		return {"error": "ResourceUID is not available in this Godot version"}
	var resource_path := String(request.get("resourcePath", ""))
	if resource_path.is_empty():
		return {"error": "resourcePath is required"}
	var uid := ResourceLoader.get_resource_uid(resource_path)
	return {"resourcePath": resource_path, "uid": uid, "uidText": ResourceUID.id_to_text(uid) if uid >= 0 else ""}

func update_project_uids(_request: Dictionary):
	return {"updated": false, "message": "Godot rebuilds resource UIDs on import; use --editor --quit after changing assets."}

func capture_screenshot(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(request.get("width", 1280)), int(request.get("height", 720)))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_root().add_child(viewport)
	viewport.add_child(root)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	var output_path := String(request.get("outputPath", "user://godot_mcp_screenshot.png"))
	var save_error := image.save_png(output_path)
	viewport.remove_child(root)
	root.free()
	viewport.free()
	if save_error != OK:
		return {"error": "Cannot save screenshot: %s" % save_error}
	return {"outputPath": output_path, "width": image.get_width(), "height": image.get_height()}

func create_animation(request: Dictionary):
	if not ClassDB.class_exists("AnimationLibrary"):
		return {"error": "AnimationLibrary is not available in this Godot version"}
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var node := root.get_node_or_null(NodePath(String(request.get("nodePath", "."))))
	if node == null or node.get_class() != "AnimationPlayer" or not node.has_method("get_animation_library"):
		root.free()
		return {"error": "AnimationPlayer not found: %s" % request.get("nodePath", ".")}
	var library = node.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		node.add_animation_library("", library)
	var animation_name := String(request.get("animationName", ""))
	if animation_name.is_empty():
		root.free()
		return {"error": "animationName is required"}
	if library.has_animation(animation_name):
		root.free()
		return {"error": "Animation already exists: %s" % animation_name}
	var animation := Animation.new()
	animation.length = maxf(float(request.get("length", 1.0)), 0.0)
	var add_error := library.add_animation(animation_name, animation)
	if add_error != OK:
		root.free()
		return {"error": "Cannot add animation: %s" % add_error}
	var result := save_root(root, String(request.get("scenePath", "")))
	root.free()
	if result.has("error"):
		return result
	return {"animationName": animation_name, "length": animation.length, "saved": true}

func inspect_animation_players(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var players := []
	collect_animation_players(root, players)
	root.free()
	return {"scenePath": request.get("scenePath", ""), "players": players}

func collect_animation_players(node: Node, result: Array) -> void:
	if node.get_class() == "AnimationPlayer":
		var libraries := {}
		for library_name in node.get_animation_library_list():
			var library = node.get_animation_library(library_name)
			libraries[library_name] = library.get_animation_list()
		result.append({"path": node.get_path().to_string(), "libraries": libraries})
	for child in node.get_children():
		collect_animation_players(child, result)

func inspect_tilemaps(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var tilemaps := []
	collect_tilemaps(root, tilemaps)
	root.free()
	return {"scenePath": request.get("scenePath", ""), "tilemaps": tilemaps}

func collect_tilemaps(node: Node, result: Array) -> void:
	if node.get_class() in ["TileMap", "TileMapLayer"]:
		result.append({"path": node.get_path().to_string(), "type": node.get_class(), "hasTileSet": node.get("tile_set") != null})
	for child in node.get_children():
		collect_tilemaps(child, result)

func set_tile_cell(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	var node := root.get_node_or_null(NodePath(String(request.get("nodePath", ""))))
	if node == null or not node.has_method("set_cell"):
		root.free()
		return {"error": "TileMap or TileMapLayer not found: %s" % request.get("nodePath", "")}
	var coordinates := Vector2i(int(request.get("x", 0)), int(request.get("y", 0)))
	var source_id := int(request.get("sourceId", 0))
	var atlas_coordinates := Vector2i(int(request.get("atlasX", 0)), int(request.get("atlasY", 0)))
	var alternative_tile := int(request.get("alternativeTile", 0))
	if node.get_class() == "TileMapLayer":
		node.call("set_cell", coordinates, source_id, atlas_coordinates, alternative_tile)
	else:
		node.call("set_cell", int(request.get("layer", 0)), coordinates, source_id, atlas_coordinates, alternative_tile)
	var result := save_root(root, String(request.get("scenePath", "")))
	root.free()
	if result.has("error"):
		return result
	return {"nodePath": request.get("nodePath", ""), "coordinates": [coordinates.x, coordinates.y], "sourceId": source_id, "saved": true}

func simulate_input(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	get_root().add_child(root)
	await process_frame
	var event
	var event_type := String(request.get("eventType", ""))
	if event_type == "key":
		event = InputEventKey.new()
		event.keycode = int(request.get("keycode", 0))
		event.physical_keycode = event.keycode
		event.pressed = bool(request.get("pressed", true))
	elif event_type == "mouse_button":
		event = InputEventMouseButton.new()
		event.button_index = int(request.get("buttonIndex", 1))
		event.pressed = bool(request.get("pressed", true))
	else:
		root.queue_free()
		return {"error": "Unsupported eventType: %s" % event_type}
	Input.parse_input_event(event)
	for _frame in range(clampi(int(request.get("durationFrames", 3)), 1, 120)):
		await process_frame
	root.queue_free()
	return {"eventType": event_type, "processed": true, "frames": int(request.get("durationFrames", 3))}

func profile_scene(request: Dictionary):
	var loaded := load_scene(request)
	if loaded.has("error"):
		return loaded
	var root: Node = loaded.root
	get_root().add_child(root)
	var frames := clampi(int(request.get("frames", 60)), 1, 300)
	var started := Time.get_ticks_usec()
	for _frame in range(frames):
		await process_frame
	var elapsed := Time.get_ticks_usec() - started
	var result := {
		"scenePath": request.get("scenePath", ""),
		"frames": frames,
		"elapsedMs": float(elapsed) / 1000.0,
		"averageFrameMs": float(elapsed) / 1000.0 / float(frames),
		"objectCount": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodeCount": root.get_child_count(),
	}
	root.queue_free()
	return result

func quit_with_error(message: String) -> void:
	var file := FileAccess.open(response_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"ok": false, "error": message}))
		file.close()
	quit(1)
