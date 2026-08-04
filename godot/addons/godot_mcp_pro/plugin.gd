@tool
extends EditorPlugin

const STATE_PATH := "user://godot_mcp_pro_state.json"
const CURRENT_STATE_VERSION := 3
const PLUGIN_VERSION := "0.3.0"
const MAX_LOG_ENTRIES := 1000
const DEFAULT_PORT := 6505
const BINDING_MODE := "one_to_one"
const BINDING_LEASE_MILLISECONDS := 90000

var tcp_server := TCPServer.new()
var peers: Array[WebSocketPeer] = []
var logs: Array[String] = []
var panel: VBoxContainer
var status_label: Label
var binding_label: Label
var release_binding_button: Button
var state := {}
var bridge_port := DEFAULT_PORT
var bound_session_id := ""
var binding_last_seen_milliseconds := 0

func _enter_tree() -> void:
	state = load_state()
	migrate_state()
	var configured_port := int(ProjectSettings.get_setting("godot_mcp/bridge_port", 0))
	bridge_port = configured_port if configured_port > 0 else default_bridge_port()
	ensure_runtime_agent_autoload()
	panel = VBoxContainer.new()
	status_label = Label.new()
	binding_label = Label.new()
	release_binding_button = Button.new()
	release_binding_button.text = "Release conversation binding"
	release_binding_button.pressed.connect(release_binding_from_panel)
	panel.add_child(status_label)
	panel.add_child(binding_label)
	panel.add_child(release_binding_button)
	add_control_to_bottom_panel(panel, "Godot MCP Toolkit")
	start_bridge()
	refresh_status()

func _exit_tree() -> void:
	save_state()
	stop_bridge()
	if panel:
		remove_control_from_bottom_panel(panel)
		panel.queue_free()

func _process(_delta: float) -> void:
	expire_binding_if_needed()
	if not tcp_server.is_connection_available():
		poll_peers()
		return
	var stream := tcp_server.take_connection()
	var peer := WebSocketPeer.new()
	var accept_error := peer.accept_stream(stream)
	if accept_error != OK:
		log_message("WebSocket accept failed: %s" % accept_error)
	else:
		peers.append(peer)
	poll_peers()


func ensure_runtime_agent_autoload() -> void:
	var autoload_name := "GodotMcpRuntimeAgent"
	var setting_name := "autoload/%s" % autoload_name
	var runtime_agent_path := "*res://addons/godot_mcp_pro/runtime_agent.gd"
	if not FileAccess.file_exists("res://addons/godot_mcp_pro/runtime_agent.gd"):
		log_message("Runtime agent file is unavailable")
		return
	if String(ProjectSettings.get_setting(setting_name, "")) == runtime_agent_path:
		return
	ProjectSettings.set_setting(setting_name, runtime_agent_path)
	ProjectSettings.save()
	log_message("Enabled runtime agent autoload")

func start_bridge() -> void:
	var requested_port := bridge_port
	var started := false
	for offset in range(0, 32):
		var candidate := requested_port + offset
		var error := tcp_server.listen(candidate, "127.0.0.1")
		if error == OK:
			bridge_port = candidate
			log_message("Bridge listening on 127.0.0.1:%s" % bridge_port)
			started = true
			break
	if not started:
		log_message("Bridge listen failed from %s to %s" % [requested_port, requested_port + 31])
	set_process(true)

func default_bridge_port() -> int:
	var project_path := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var hash_value := 0
	for index in project_path.length():
		hash_value = (hash_value * 31 + project_path.unicode_at(index)) % 500
	return DEFAULT_PORT + hash_value

func stop_bridge() -> void:
	for peer in peers:
		peer.close()
	peers.clear()
	tcp_server.stop()

func poll_peers() -> void:
	for index in range(peers.size() - 1, -1, -1):
		var peer: WebSocketPeer = peers[index]
		peer.poll()
		var state_value := peer.get_ready_state()
		if state_value == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				handle_packet(peer, peer.get_packet().get_string_from_utf8())
		elif state_value == WebSocketPeer.STATE_CLOSED:
			peers.remove_at(index)

func handle_packet(peer: WebSocketPeer, text: String) -> void:
	var request = JSON.parse_string(text)
	if request == null or not request is Dictionary:
		send_response(peer, "", false, null, "Request JSON is invalid")
		return
	var request_id := String(request.get("id", ""))
	var operation := String(request.get("operation", ""))
	var params = request.get("params", {})
	var request_params: Dictionary = params if params is Dictionary else {}
	var response := execute_operation(operation, request_params)
	send_response(peer, request_id, bool(response.get("ok", false)), response.get("result"), response.get("error", ""), response.get("details", {}))

func send_response(peer: WebSocketPeer, request_id: String, ok: bool, result, error: String, details = {}) -> void:
	peer.send_text(JSON.stringify({"id": request_id, "ok": ok, "result": result, "error": error, "details": details}))

func execute_operation(operation: String, params: Dictionary) -> Dictionary:
	if operation == "bind_session":
		return bind_session(params)
	if operation == "get_binding":
		expire_binding_if_needed()
		return ok_result(get_binding_status())
	if operation == "release_session":
		return release_session(params)
	var binding_result := bind_session(params)
	if not bool(binding_result.get("ok", false)):
		return binding_result
	match operation:
		"get_editor_info":
			return ok_result(get_editor_info())
		"get_scene_tree":
			return get_scene_tree(params)
		"open_scene":
			return open_scene(params)
		"save_current_scene":
			return save_current_scene()
		"play_current_scene":
			return play_current_scene()
		"stop_running_scene":
			return stop_running_scene()
		"get_selection":
			return ok_result(get_selection())
		"select_nodes":
			return select_nodes(params)
		"clear_selection":
			return clear_selection()
		"add_node":
			return add_node(params)
		"delete_node":
			return delete_node(params)
		"duplicate_node":
			return duplicate_node(params)
		"move_node":
			return move_node(params)
		"rename_node":
			return rename_node(params)
		"get_node_properties":
			return get_node_properties(params)
		"set_property":
			return set_property(params)
		"capture_viewport":
			return capture_viewport(params)
		"create_ui_screen":
			return create_ui_screen(params)
		"configure_control_layout":
			return configure_control_layout(params)
		"set_theme_override":
			return set_theme_override(params)
		"inspect_ui_layout":
			return inspect_ui_layout(params)
		"create_particles":
			return create_particles(params)
		"configure_particles":
			return configure_particles(params)
		"create_shader_effect":
			return create_shader_effect(params)
		"set_shader_parameter":
			return set_shader_parameter(params)
		"create_screen_flash":
			return create_screen_flash(params)
		"create_post_process":
			return create_post_process(params)
		"configure_stylized_rendering":
			return configure_stylized_rendering(params)
		"create_animation_effect":
			return create_animation_effect(params)
		"set_canvas_modulate":
			return set_canvas_modulate(params)
		"inspect_visual_effects":
			return inspect_visual_effects(params)
		"reload_filesystem":
			return reload_filesystem()
		"execute_script":
			return execute_script(params)
		"get_script_editor_state":
			return get_script_editor_state()
		"open_editor_script":
			return open_editor_script(params)
		"goto_editor_script_line":
			return goto_editor_script_line(params)
		"get_editor_breakpoints":
			return ok_result(get_editor_breakpoints())
		"save_editor_scripts":
			return save_editor_scripts()
		"get_editor_debugger_state":
			return get_editor_debugger_state()
		"create_primitive_mesh":
			return create_primitive_mesh(params)
		"create_3d_camera":
			return create_3d_camera(params)
		"create_3d_light":
			return create_3d_light(params)
		"create_2d_camera":
			return create_2d_camera(params)
		"create_2d_light":
			return create_2d_light(params)
		"create_ui_component":
			return create_ui_component(params)
		"set_editor_transform":
			return set_editor_transform(params)
		"inspect_3d_scene":
			return inspect_3d_scene(params)
		"create_standard_material":
			return create_standard_material(params)
		"assign_editor_material":
			return assign_editor_material(params)
		"create_animation_track":
			return create_animation_track(params)
		"set_animation_key":
			return set_animation_key(params)
		"inspect_animation_timeline":
			return inspect_animation_timeline(params)
		"set_animation_tree_state":
			return set_animation_tree_state(params)
		"create_navigation_node":
			return create_navigation_node(params)
		"configure_navigation_agent":
			return configure_navigation_agent(params)
		"inspect_navigation":
			return inspect_navigation(params)
		"create_collision_shape":
			return create_collision_shape(params)
		"configure_physics_node":
			return configure_physics_node(params)
		"inspect_physics":
			return inspect_physics(params)
		"get_editor_audio_buses":
			return ok_result(get_audio_bus_state())
		"set_editor_audio_bus":
			return set_audio_bus_state(params)
		"configure_editor_audio_player":
			return configure_editor_audio_player(params)
		"inspect_editor_audio_nodes":
			return inspect_editor_audio_nodes(params)
		"create_theme_resource":
			return create_theme_resource(params)
		"list_editor_plugins":
			return list_editor_plugins()
		"set_editor_plugin_enabled":
			return set_editor_plugin_enabled(params)
		"get_editor_workspace":
			return get_editor_workspace()
		"set_editor_main_screen":
			return set_editor_main_screen(params)
		"set_distraction_free_mode":
			return set_distraction_free_mode(params)
		"reimport_editor_resources":
			return reimport_editor_resources(params)
		"get_logs":
			return ok_result({"logs": logs.slice(-clampi(int(params.get("tailLines", 200)), 1, 1000))})
		"undo":
			EditorInterface.get_editor_undo_redo().undo()
			return ok_result({"undone": true})
		"redo":
			EditorInterface.get_editor_undo_redo().redo()
			return ok_result({"redone": true})
		_:
			return error_result("Unknown editor operation: %s" % operation)

func current_project_path() -> String:
	return ProjectSettings.globalize_path("res://")

func normalize_project_path(project_path: String) -> String:
	return project_path.replace("\\", "/").trim_suffix("/").to_lower()

func binding_is_active() -> bool:
	return not bound_session_id.is_empty() and Time.get_ticks_msec() - binding_last_seen_milliseconds < BINDING_LEASE_MILLISECONDS

func expire_binding_if_needed() -> void:
	if bound_session_id.is_empty() or binding_is_active():
		return
	bound_session_id = ""
	binding_last_seen_milliseconds = 0
	log_message("Conversation binding lease expired")
	refresh_status()

func get_binding_status() -> Dictionary:
	var remaining_milliseconds := 0
	if binding_is_active():
		remaining_milliseconds = max(BINDING_LEASE_MILLISECONDS - (Time.get_ticks_msec() - binding_last_seen_milliseconds), 0)
	return {
		"mode": BINDING_MODE,
		"bound": binding_is_active(),
		"projectPath": current_project_path(),
		"sessionFingerprint": bound_session_id.left(8) if binding_is_active() else "",
		"leaseSecondsRemaining": int(ceil(float(remaining_milliseconds) / 1000.0)),
	}

func bind_session(params: Dictionary) -> Dictionary:
	expire_binding_if_needed()
	var session_id := String(params.get("sessionId", "")).strip_edges()
	if session_id.length() < 8 or session_id.length() > 128:
		return error_result("Editor bridge requires a valid MCP sessionId", {"code": "missing_session_id"})
	var requested_project_path := String(params.get("projectPath", ""))
	if not requested_project_path.is_empty() and normalize_project_path(requested_project_path) != normalize_project_path(current_project_path()):
		return error_result("Editor project does not match the requested MCP project", {"code": "project_mismatch", "projectPath": current_project_path()})
	if not bound_session_id.is_empty() and bound_session_id != session_id:
		return error_result("Editor is already bound to another MCP conversation", {"code": "editor_binding_conflict", "projectPath": current_project_path(), "leaseSecondsRemaining": get_binding_status().leaseSecondsRemaining})
	var was_unbound := bound_session_id.is_empty()
	bound_session_id = session_id
	binding_last_seen_milliseconds = Time.get_ticks_msec()
	if was_unbound:
		log_message("Bound editor to MCP conversation %s" % session_id.left(8))
	refresh_status()
	return ok_result({"projectPath": current_project_path(), "binding": get_binding_status()})

func release_session(params: Dictionary) -> Dictionary:
	expire_binding_if_needed()
	var session_id := String(params.get("sessionId", "")).strip_edges()
	if bound_session_id.is_empty():
		return ok_result({"released": false, "binding": get_binding_status()})
	if session_id != bound_session_id:
		return error_result("Only the bound MCP conversation can release this editor", {"code": "editor_binding_conflict", "projectPath": current_project_path()})
	bound_session_id = ""
	binding_last_seen_milliseconds = 0
	log_message("Released MCP conversation binding")
	refresh_status()
	return ok_result({"released": true, "binding": get_binding_status()})

func release_binding_from_panel() -> void:
	if bound_session_id.is_empty():
		return
	bound_session_id = ""
	binding_last_seen_milliseconds = 0
	log_message("Released MCP conversation binding from editor panel")
	refresh_status()

func get_editor_info() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var version_info := Engine.get_version_info()
	return {
		"godotVersion": String(version_info.get("string", "unknown")),
		"projectPath": current_project_path(),
		"binding": get_binding_status(),
		"scenePath": root.scene_file_path if root else "",
		"sceneName": root.name if root else "",
		"selection": get_selection().paths,
		"bridgePort": bridge_port,
		"features": {
			"tileMapLayer": ClassDB.class_exists("TileMapLayer"),
			"animationLibrary": ClassDB.class_exists("AnimationLibrary"),
			"resourceUID": ClassDB.class_exists("ResourceUID"),
		},
	}

func get_scene_tree(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return error_result("No edited scene is open")
	return ok_result({"scenePath": root.scene_file_path, "tree": describe_node(root, 0, clampi(int(params.get("maxDepth", 16)), 0, 64))})

func open_scene(params: Dictionary) -> Dictionary:
	var scene_path := String(params.get("scenePath", ""))
	if not scene_path.begins_with("res://") or not scene_path.ends_with(".tscn"):
		return error_result("scenePath must be a res:// .tscn path")
	EditorInterface.open_scene_from_path(scene_path)
	log_message("Opened scene %s" % scene_path)
	return ok_result({"scenePath": scene_path, "opened": true})

func save_current_scene() -> Dictionary:
	EditorInterface.save_scene()
	return ok_result({"saved": true})

func play_current_scene() -> Dictionary:
	EditorInterface.play_current_scene()
	return ok_result({"playing": true})

func stop_running_scene() -> Dictionary:
	EditorInterface.stop_playing_scene()
	return ok_result({"stopped": true})

func get_selection() -> Dictionary:
	var selected_paths := []
	for node in EditorInterface.get_selection().get_selected_nodes():
		selected_paths.append(String(node.get_path()))
	return {"paths": selected_paths}

func select_nodes(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return error_result("No edited scene is open")
	var selection := EditorInterface.get_selection()
	selection.clear()
	var selected := []
	for path_value in params.get("nodePaths", []):
		var node := root.get_node_or_null(NodePath(String(path_value)))
		if node:
			selection.add_node(node)
			selected.append(String(node.get_path()))
	return ok_result({"paths": selected})

func clear_selection() -> Dictionary:
	EditorInterface.get_selection().clear()
	return ok_result({"cleared": true})

func add_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return error_result("No edited scene is open")
	var parent := root.get_node_or_null(NodePath(String(params.get("parentPath", "."))))
	if parent == null:
		return error_result("Parent node not found")
	var object = ClassDB.instantiate(String(params.get("nodeType", "Node")))
	if object == null or not object is Node:
		return error_result("Unsupported node type")
	var node: Node = object
	node.name = String(params.get("nodeName", "Node"))
	apply_properties(node, params.get("properties", {}))
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Add Node")
	undo.add_do_method(parent, "add_child", node)
	undo.add_do_method(node, "set_owner", root)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()
	return ok_result({"path": String(node.get_path()), "type": node.get_class(), "undoable": true})

func delete_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or node == root or node.get_parent() == null:
		return error_result("Node not found or root cannot be deleted")
	var parent := node.get_parent()
	var index := node.get_index()
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Delete Node")
	undo.add_do_method(parent, "remove_child", node)
	undo.add_undo_method(parent, "add_child", node)
	undo.add_undo_method(parent, "move_child", node, index)
	undo.commit_action()
	return ok_result({"path": String(node.get_path()), "deleted": true, "undoable": true})

func duplicate_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var source := resolve_node(root, String(params.get("nodePath", "")))
	if source == null or source.get_parent() == null:
		return error_result("Node not found")
	var copy := source.duplicate()
	copy.name = String(params.get("newName", "%sCopy" % source.name))
	var parent := source.get_parent()
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Duplicate Node")
	undo.add_do_method(parent, "add_child", copy)
	undo.add_do_method(parent, "move_child", copy, source.get_index() + 1)
	undo.add_undo_method(parent, "remove_child", copy)
	undo.commit_action()
	return ok_result({"path": String(copy.get_path()), "duplicated": true, "undoable": true})

func move_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	var new_parent := resolve_node(root, String(params.get("parentPath", "")))
	if node == null or new_parent == null or node == root or node == new_parent:
		return error_result("Node or parent not found")
	var old_parent := node.get_parent()
	var old_index := node.get_index()
	var new_index := int(params.get("index", -1))
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Move Node")
	undo.add_do_method(old_parent, "remove_child", node)
	undo.add_do_method(new_parent, "add_child", node)
	if new_index >= 0:
		undo.add_do_method(new_parent, "move_child", node, new_index)
	undo.add_undo_method(new_parent, "remove_child", node)
	undo.add_undo_method(old_parent, "add_child", node)
	undo.add_undo_method(old_parent, "move_child", node, old_index)
	undo.commit_action()
	return ok_result({"path": String(node.get_path()), "parentPath": String(new_parent.get_path()), "moved": true, "undoable": true})

func rename_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or node == root:
		return error_result("Node not found or root cannot be renamed")
	var old_name := node.name
	var new_name := String(params.get("newName", ""))
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Rename Node")
	undo.add_do_property(node, "name", new_name)
	undo.add_undo_property(node, "name", old_name)
	undo.commit_action()
	return ok_result({"oldName": old_name, "newName": new_name, "renamed": true, "undoable": true})

func get_node_properties(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", ".")))
	if node == null:
		return error_result("Node not found")
	return ok_result(describe_properties(node))

func set_property(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	var property_name := String(params.get("property", ""))
	if node == null:
		return error_result("Node not found")
	if not has_property(node, property_name):
		return error_result("Property not found: %s" % property_name)
	var value = decode_value(params.get("value"))
	var old_value = node.get(property_name)
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Set Property")
	undo.add_do_property(node, property_name, value)
	undo.add_undo_property(node, property_name, old_value)
	undo.commit_action()
	return ok_result({"nodePath": String(node.get_path()), "property": property_name, "value": serialize_value(value), "set": true, "undoable": true})

func capture_viewport(params: Dictionary) -> Dictionary:
	var viewport_name := String(params.get("viewport", "2d"))
	var target = EditorInterface.get_editor_viewport_2d() if viewport_name == "2d" else EditorInterface.get_editor_viewport_3d()
	if target == null:
		return error_result("Editor viewport is unavailable")
	var viewport = target.get_viewport() if target is Control else target
	if viewport == null or not viewport.has_method("get_texture"):
		return error_result("Editor viewport texture is unavailable")
	var image: Image = viewport.get_texture().get_image()
	var output_path := String(params.get("outputPath", ""))
	if output_path.is_empty():
		return error_result("outputPath is required")
	var save_error := image.save_png(output_path)
	if save_error != OK:
		return error_result("Cannot save editor screenshot: %s" % save_error)
	return ok_result({"outputPath": output_path, "viewport": viewport_name, "width": image.get_width(), "height": image.get_height()})

func create_ui_screen(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if root == null or parent == null:
		return error_result("Parent node not found")
	var screen := Control.new()
	screen.name = String(params.get("rootName", "UIScreen"))
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin_value := int(params.get("margin", 24))
	for property_name in ["theme_override_constants/margin_left", "theme_override_constants/margin_top", "theme_override_constants/margin_right", "theme_override_constants/margin_bottom"]:
		margin.set(property_name, margin_value)
	margin.add_child(screen_child_container("VBoxContainer", "ContentStack"))
	screen.add_child(margin)
	var stack: VBoxContainer = margin.get_child(0)
	if bool(params.get("addHeader", true)):
		var header := PanelContainer.new()
		header.name = "Header"
		header.custom_minimum_size = Vector2(0, 64)
		stack.add_child(header)
	if bool(params.get("addContent", true)):
		var content := Control.new()
		content.name = "Content"
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(content)
	if bool(params.get("addFooter", true)):
		var footer := HBoxContainer.new()
		footer.name = "Footer"
		footer.custom_minimum_size = Vector2(0, 48)
		footer.alignment = BoxContainer.ALIGNMENT_END
		stack.add_child(footer)
	var result := add_node_undo(parent, screen, root, "Godot MCP Create UI Screen")
	result["structure"] = ["Margin", "ContentStack", "Header" if bool(params.get("addHeader", true)) else "", "Content" if bool(params.get("addContent", true)) else "", "Footer" if bool(params.get("addFooter", true)) else ""]
	return ok_result(result)

func screen_child_container(node_type: String, node_name: String) -> Control:
	var object = ClassDB.instantiate(node_type)
	var control: Control = object
	control.name = node_name
	return control

func configure_control_layout(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node is Control:
		return error_result("Control node not found")
	var values := {}
	var anchors = params.get("anchors", {})
	var offsets = params.get("offsets", {})
	var size_flags = params.get("sizeFlags", {})
	var grow_direction = params.get("growDirection", {})
	for key in anchors.keys():
		values["anchor_%s" % key] = float(anchors[key])
	for key in offsets.keys():
		values["offset_%s" % key] = float(offsets[key])
	if size_flags.has("horizontal"):
		values["size_flags_horizontal"] = int(size_flags.horizontal)
	if size_flags.has("vertical"):
		values["size_flags_vertical"] = int(size_flags.vertical)
	if grow_direction.has("horizontal"):
		values["grow_horizontal"] = int(grow_direction.horizontal)
	if grow_direction.has("vertical"):
		values["grow_vertical"] = int(grow_direction.vertical)
	return ok_result(apply_properties_undo(node, values, "Godot MCP Configure Control Layout"))

func set_theme_override(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node is Control:
		return error_result("Control node not found")
	var kind := String(params.get("kind", "color"))
	var override_name := String(params.get("name", ""))
	var value = params.get("value")
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Theme Override")
	match kind:
		"color":
			var color := parse_color(value)
			var old_color: Color = node.get_theme_color(override_name) if not node.has_theme_color_override(override_name) else node.get_theme_color(override_name)
			undo.add_do_method(node, "add_theme_color_override", override_name, color)
			undo.add_undo_method(node, "add_theme_color_override", override_name, old_color)
		"font_size":
			var old_size: int = node.get_theme_font_size(override_name)
			undo.add_do_method(node, "add_theme_font_size_override", override_name, int(value))
			undo.add_undo_method(node, "add_theme_font_size_override", override_name, old_size)
		"constant":
			var old_constant: int = node.get_theme_constant(override_name)
			undo.add_do_method(node, "add_theme_constant_override", override_name, int(value))
			undo.add_undo_method(node, "add_theme_constant_override", override_name, old_constant)
		"stylebox":
			var stylebox := make_stylebox(value)
			if stylebox == null:
				return error_result("stylebox value is invalid")
			var old_stylebox = node.get_theme_stylebox(override_name)
			undo.add_do_method(node, "add_theme_stylebox_override", override_name, stylebox)
			undo.add_undo_method(node, "add_theme_stylebox_override", override_name, old_stylebox)
		_:
			return error_result("Unsupported theme override kind: %s" % kind)
	undo.commit_action()
	return ok_result({"nodePath": String(node.get_path()), "kind": kind, "name": override_name, "set": true, "undoable": true})

func inspect_ui_layout(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", ".")))
	if node == null or not node is Control:
		return error_result("Control node not found")
	return ok_result({
		"nodePath": String(node.get_path()),
		"type": node.get_class(),
		"position": [node.position.x, node.position.y],
		"size": [node.size.x, node.size.y],
		"anchors": {"left": node.anchor_left, "top": node.anchor_top, "right": node.anchor_right, "bottom": node.anchor_bottom},
		"offsets": {"left": node.offset_left, "top": node.offset_top, "right": node.offset_right, "bottom": node.offset_bottom},
		"sizeFlags": {"horizontal": node.size_flags_horizontal, "vertical": node.size_flags_vertical},
		"mouseFilter": node.mouse_filter,
	})

func create_particles(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if root == null or parent == null:
		return error_result("Parent node not found")
	var dimension := String(params.get("dimension", "2d"))
	var particles: Node = GPUParticles3D.new() if dimension == "3d" else GPUParticles2D.new()
	particles.name = String(params.get("nodeName", "McpParticles"))
	particles.set("amount", int(params.get("amount", 64)))
	particles.set("lifetime", float(params.get("lifetime", 1.5)))
	particles.set("one_shot", bool(params.get("oneShot", false)))
	particles.set("explosiveness", float(params.get("explosiveness", 0.0)))
	particles.set("randomness", float(params.get("randomness", 0.0)))
	var material := ParticleProcessMaterial.new()
	material.color = parse_color(params.get("color", "#ffffff"))
	particles.set("process_material", material)
	if dimension == "2d" and not String(params.get("texturePath", "")).is_empty():
		particles.set("texture", ResourceLoader.load(String(params.get("texturePath"))))
	if dimension == "3d":
		var quad := QuadMesh.new()
		quad.size = Vector2(0.15, 0.15)
		particles.set("draw_pass_1", quad)
	var result := add_node_undo(parent, particles, root, "Godot MCP Create Particles")
	result["dimension"] = dimension
	result["amount"] = particles.get("amount")
	return ok_result(result)

func configure_particles(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node.get_class() in ["GPUParticles2D", "GPUParticles3D"]:
		return error_result("Particle node not found")
	var result := apply_properties_undo(node, params.get("properties", {}), "Godot MCP Configure Particles")
	var material_values = params.get("material", {})
	if material_values is Dictionary and not material_values.is_empty():
		var material = node.get("process_material")
		if material == null:
			material = ParticleProcessMaterial.new()
			apply_properties_undo(node, {"process_material": material}, "Godot MCP Create Particle Material")
		result["material"] = apply_properties_undo(material, material_values, "Godot MCP Configure Particle Material")
	return ok_result(result)

func create_shader_effect(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not has_property(node, "material"):
		return error_result("Target node has no material property")
	var shader := Shader.new()
	shader.code = String(params.get("shaderCode", ""))
	if shader.code.is_empty():
		return error_result("shaderCode is required")
	var material := ShaderMaterial.new()
	material.shader = shader
	var save_path := String(params.get("savePath", ""))
	if not save_path.is_empty():
		var save_error := ResourceSaver.save(material, save_path)
		if save_error != OK:
			return error_result("Cannot save ShaderMaterial: %s" % save_error)
	return ok_result(apply_properties_undo(node, {"material": material}, "Godot MCP Create Shader Effect"))

func set_shader_parameter(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not has_property(node, "material"):
		return error_result("Target node has no material property")
	var material = node.get("material")
	if material == null or not material is ShaderMaterial:
		return error_result("Target node does not have a ShaderMaterial")
	var parameter := String(params.get("parameter", ""))
	var value = decode_value(params.get("value"))
	var old_value = material.get_shader_parameter(parameter)
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Set Shader Parameter")
	undo.add_do_method(material, "set_shader_parameter", parameter, value)
	undo.add_undo_method(material, "set_shader_parameter", parameter, old_value)
	undo.commit_action()
	return ok_result({"nodePath": String(node.get_path()), "parameter": parameter, "set": true, "undoable": true})

func create_screen_flash(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if root == null or parent == null:
		return error_result("Parent node not found")
	var layer := CanvasLayer.new()
	layer.name = String(params.get("nodeName", "McpScreenFlash"))
	var rect := ColorRect.new()
	rect.name = "Overlay"
	rect.color = parse_color(params.get("color", "#ffffff00"))
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var result := add_node_undo(parent, layer, root, "Godot MCP Create Screen Flash")
	result["overlayPath"] = "%s/%s/Overlay" % [String(parent.get_path()), layer.name]
	return ok_result(result)

func create_post_process(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if root == null or parent == null:
		return error_result("Parent node not found")
	var world := WorldEnvironment.new()
	world.name = String(params.get("nodeName", "McpWorldEnvironment"))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = parse_color(params.get("backgroundColor", "#101522"))
	environment.glow_enabled = bool(params.get("glowEnabled", true))
	environment.fog_enabled = bool(params.get("fogEnabled", false))
	world.environment = environment
	return ok_result(add_node_undo(parent, world, root, "Godot MCP Create Post Process"))

func create_animation_effect(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var player := resolve_node(root, String(params.get("animationPlayerPath", "")))
	if player == null or player.get_class() != "AnimationPlayer":
		return error_result("AnimationPlayer not found")
	var library = player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		player.add_animation_library("", library)
	var animation_name := String(params.get("animationName", ""))
	if library.has_animation(animation_name):
		return error_result("Animation already exists")
	var animation := Animation.new()
	animation.length = float(params.get("length", 0.5))
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath("%s:%s" % [String(params.get("targetNodePath", ".")), String(params.get("property", ""))]))
	for key in params.get("keys", []):
		animation.track_insert_key(track, float(key.get("time", 0.0)), decode_value(key.get("value")))
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action("Godot MCP Create Animation Effect")
	undo.add_do_method(library, "add_animation", animation_name, animation)
	undo.add_undo_method(library, "remove_animation", animation_name)
	undo.commit_action()
	return ok_result({"animationName": animation_name, "track": String(params.get("targetNodePath", ".")), "created": true, "undoable": true})

func set_canvas_modulate(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or node.get_class() != "CanvasModulate":
		return error_result("CanvasModulate node not found")
	return ok_result(apply_properties_undo(node, {"color": parse_color(params.get("color", "#ffffff"))}, "Godot MCP Set Canvas Modulate"))

func inspect_visual_effects(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("rootPath", ".")))
	if node == null:
		return error_result("Root node not found")
	var effects := []
	collect_visual_effects(node, effects)
	return ok_result({"rootPath": String(node.get_path()), "effects": effects})

func collect_visual_effects(node: Node, result: Array) -> void:
	var type_name := node.get_class()
	if type_name in ["GPUParticles2D", "GPUParticles3D", "AnimationPlayer", "WorldEnvironment", "CanvasModulate", "CanvasLayer"]:
		result.append({"path": String(node.get_path()), "type": type_name})
	if has_property(node, "material") and node.get("material") is ShaderMaterial:
		result.append({"path": String(node.get_path()), "type": "ShaderMaterial"})
	for child in node.get_children():
		collect_visual_effects(child, result)


func get_script_editor_state() -> Dictionary:
	var script_editor = EditorInterface.get_script_editor()
	var current_script = script_editor.get_current_script()
	var current_editor = script_editor.get_current_editor()
	var result := {"currentScript": current_script.resource_path if current_script else "", "openScripts": [], "unsavedScripts": [], "breakpoints": get_editor_breakpoints()}
	for script in script_editor.get_open_scripts():
		result["openScripts"].append(script.resource_path if script else "")
	for script_path in script_editor.get_unsaved_files():
		result["unsavedScripts"].append(String(script_path))
	if current_editor:
		if current_editor.has_method("get_caret_line"):
			result["caretLine"] = int(current_editor.call("get_caret_line"))
		if current_editor.has_method("get_caret_column"):
			result["caretColumn"] = int(current_editor.call("get_caret_column"))
		if current_editor.has_method("get_selection_text"):
			result["selection"] = String(current_editor.call("get_selection_text"))
	return ok_result(result)

func open_editor_script(params: Dictionary) -> Dictionary:
	var script_path := String(params.get("scriptPath", ""))
	if not script_path.begins_with("res://"):
		return error_result("scriptPath must be a res:// path")
	var script = ResourceLoader.load(script_path)
	if script == null or not script is Script:
		return error_result("Script cannot be loaded: %s" % script_path)
	EditorInterface.edit_script(script)
	return ok_result({"scriptPath": script_path, "opened": true})

func goto_editor_script_line(params: Dictionary) -> Dictionary:
	var script_editor = EditorInterface.get_script_editor()
	var line := maxi(int(params.get("line", 1)) - 1, 0)
	script_editor.goto_line(line)
	return ok_result({"line": line + 1, "moved": true})

func get_editor_breakpoints() -> Array:
	var script_editor = EditorInterface.get_script_editor()
	if script_editor and script_editor.has_method("get_breakpoints"):
		return serialize_value(script_editor.call("get_breakpoints"))
	return []

func save_editor_scripts() -> Dictionary:
	var script_editor = EditorInterface.get_script_editor()
	if script_editor.has_method("save_all_scripts"):
		script_editor.call("save_all_scripts")
	return ok_result({"saved": true})

func get_editor_debugger_state() -> Dictionary:
	return {"available": false, "isPlaying": EditorInterface.is_playing_scene(), "playingScene": EditorInterface.get_playing_scene(), "message": "Godot exposes runtime debugger state through the runtime agent; editor debugger session APIs vary by engine build."}

func create_2d_camera(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null:
		return error_result("2D camera parent node not found")
	var camera := Camera2D.new()
	camera.name = String(params.get("nodeName", "McpCamera2D"))
	camera.position = vector2_from_params(params.get("position", {}), Vector2.ZERO)
	camera.zoom = vector2_from_params(params.get("zoom", {}), Vector2.ONE)
	camera.rotation = deg_to_rad(float(params.get("rotationDegrees", 0.0)))
	camera.enabled = bool(params.get("enabled", true))
	camera.position_smoothing_enabled = bool(params.get("positionSmoothing", false))
	camera.position_smoothing_speed = float(params.get("positionSmoothingSpeed", 5.0))
	return ok_result(add_node_undo(parent, camera, root, "Godot MCP Create Camera2D"))

func create_2d_light(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null:
		return error_result("2D light parent node not found")
	var light_type := String(params.get("lightType", "point"))
	var light: Light2D = DirectionalLight2D.new() if light_type == "directional" else PointLight2D.new()
	light.name = String(params.get("nodeName", "McpLight2D"))
	light.position = vector2_from_params(params.get("position", {}), Vector2.ZERO)
	light.rotation = deg_to_rad(float(params.get("rotationDegrees", 0.0)))
	light.color = parse_color(params.get("color", "#ffffff"))
	light.energy = float(params.get("energy", 1.0))
	if light is PointLight2D and params.has("textureScale"):
		light.texture_scale = float(params.get("textureScale"))
	return ok_result(add_node_undo(parent, light, root, "Godot MCP Create Light2D"))

func create_ui_component(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null:
		return error_result("UI component parent node not found")
	var component_type := String(params.get("componentType", "PanelContainer"))
	if not component_type in ["PanelContainer", "Label", "Button", "TextureRect", "ProgressBar", "ColorRect", "HBoxContainer", "VBoxContainer", "MarginContainer", "CenterContainer"]:
		return error_result("Unsupported UI component type: %s" % component_type)
	var instance = ClassDB.instantiate(component_type)
	if instance == null or not instance is Control:
		return error_result("Cannot create UI component: %s" % component_type)
	var control: Control = instance
	control.name = String(params.get("nodeName", "Mcp%s" % component_type))
	if bool(params.get("fullRect", false)):
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if params.has("minimumSize"):
		control.custom_minimum_size = vector2_from_params(params.get("minimumSize"), Vector2.ZERO)
	if params.has("text") and has_property(control, "text"):
		control.set("text", String(params.get("text")))
	if params.has("color") and has_property(control, "color"):
		control.set("color", parse_color(params.get("color")))
	if params.has("texturePath") and has_property(control, "texture"):
		control.set("texture", ResourceLoader.load(String(params.get("texturePath"))))
	if params.has("value") and has_property(control, "value"):
		control.set("value", float(params.get("value")))
	if params.has("maxValue") and has_property(control, "max_value"):
		control.set("max_value", float(params.get("maxValue")))
	apply_properties(control, params.get("properties", {}))
	return ok_result(add_node_undo(parent, control, root, "Godot MCP Create UI Component"))

func configure_stylized_rendering(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if root == null or parent == null:
		return error_result("Stylized rendering parent node not found")
	var dimension := String(params.get("dimension", "2d"))
	if dimension == "2d":
		var modulate := resolve_node(root, String(params.get("nodePath", "")))
		if modulate == null:
			modulate = CanvasModulate.new()
			modulate.name = String(params.get("nodeName", "McpCanvasPalette"))
			modulate.color = parse_color(params.get("paletteColor", "#ffffff"))
			var create_result := add_node_undo(parent, modulate, root, "Godot MCP Create Canvas Palette")
			return ok_result({"dimension": "2d", "node": create_result, "paletteColor": serialize_value(modulate.color)})
		if not modulate is CanvasModulate:
			return error_result("nodePath must resolve to CanvasModulate for 2D stylized rendering")
		return ok_result({"dimension": "2d", "updated": apply_properties_undo(modulate, {"color": parse_color(params.get("paletteColor", "#ffffff"))}, "Godot MCP Set Canvas Palette")})
	if dimension != "3d":
		return error_result("dimension must be 2d or 3d")
	var world_node := resolve_node(root, String(params.get("nodePath", "")))
	var created := false
	if world_node == null:
		world_node = WorldEnvironment.new()
		world_node.name = String(params.get("nodeName", "McpStylizedEnvironment"))
		created = true
	if not world_node is WorldEnvironment:
		return error_result("nodePath must resolve to WorldEnvironment for 3D stylized rendering")
	var world: WorldEnvironment = world_node
	var environment := world.environment
	if environment == null:
		environment = Environment.new()
		world.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = parse_color(params.get("backgroundColor", "#1b2135"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = parse_color(params.get("ambientColor", "#a9c4ff"))
	environment.ambient_light_energy = float(params.get("ambientEnergy", 0.8))
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = bool(params.get("glowEnabled", true))
	environment.glow_intensity = float(params.get("glowIntensity", 0.8))
	environment.adjustment_enabled = true
	environment.adjustment_saturation = float(params.get("saturation", 1.1))
	environment.adjustment_contrast = float(params.get("contrast", 1.05))
	environment.adjustment_brightness = float(params.get("brightness", 1.0))
	environment.fog_enabled = bool(params.get("fogEnabled", false))
	if environment.fog_enabled:
		environment.fog_light_color = parse_color(params.get("fogColor", "#aab8d0"))
		environment.fog_density = float(params.get("fogDensity", 0.01))
	if created:
		return ok_result({"dimension": "3d", "node": add_node_undo(parent, world, root, "Godot MCP Create Stylized Environment"), "created": true})
	return ok_result({"dimension": "3d", "nodePath": String(world.get_path()), "updated": true})

func vector2_from_params(value, fallback: Vector2) -> Vector2:
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback

func create_primitive_mesh(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null or not parent is Node3D:
		return error_result("3D parent node not found")
	var node := MeshInstance3D.new()
	node.name = String(params.get("nodeName", "McpMesh"))
	var primitive := String(params.get("primitive", "box"))
	var mesh: PrimitiveMesh
	match primitive:
		"box":
			mesh = BoxMesh.new()
			var box_size = params.get("size", {})
			if box_size is Dictionary and box_size.has("x"):
				mesh.size = Vector3(float(box_size.get("x", 1)), float(box_size.get("y", 1)), float(box_size.get("z", 1)))
		"sphere":
			mesh = SphereMesh.new()
		"capsule":
			mesh = CapsuleMesh.new()
		"cylinder":
			mesh = CylinderMesh.new()
		"plane":
			mesh = PlaneMesh.new()
		"quad":
			mesh = QuadMesh.new()
		_:
			return error_result("Unsupported primitive mesh: %s" % primitive)
	node.mesh = mesh
	apply_properties(node, params.get("properties", {}))
	return ok_result(add_node_undo(parent, node, root, "Godot MCP Create Primitive Mesh"))

func create_3d_camera(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null or not parent is Node3D:
		return error_result("3D parent node not found")
	var node := Camera3D.new()
	node.name = String(params.get("nodeName", "McpCamera3D"))
	apply_transform(node, params.get("transform", {}))
	if params.has("current"):
		node.current = bool(params.get("current"))
	return ok_result(add_node_undo(parent, node, root, "Godot MCP Create Camera3D"))

func create_3d_light(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null or not parent is Node3D:
		return error_result("3D parent node not found")
	var light_type := String(params.get("lightType", "directional"))
	var node: Light3D
	match light_type:
		"directional": node = DirectionalLight3D.new()
		"omni": node = OmniLight3D.new()
		"spot": node = SpotLight3D.new()
		_: return error_result("Unsupported 3D light type: %s" % light_type)
	node.name = String(params.get("nodeName", "McpLight3D"))
	node.color = parse_color(params.get("color", "#ffffff"))
	node.light_energy = float(params.get("energy", 1.0))
	apply_transform(node, params.get("transform", {}))
	return ok_result(add_node_undo(parent, node, root, "Godot MCP Create Light3D"))

func set_editor_transform(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node is Node3D:
		return error_result("Node3D not found")
	var values := {}
	var transform = params.get("position", {})
	if transform is Dictionary and transform.has("x"):
		values["position"] = Vector3(float(transform.get("x", 0)), float(transform.get("y", 0)), float(transform.get("z", 0)))
	transform = params.get("rotationDegrees", {})
	if transform is Dictionary and transform.has("x"):
		values["rotation_degrees"] = Vector3(float(transform.get("x", 0)), float(transform.get("y", 0)), float(transform.get("z", 0)))
	transform = params.get("scale", {})
	if transform is Dictionary and transform.has("x"):
		values["scale"] = Vector3(float(transform.get("x", 1)), float(transform.get("y", 1)), float(transform.get("z", 1)))
	return ok_result(apply_properties_undo(node, values, "Godot MCP Set 3D Transform"))

func apply_transform(node: Node3D, values) -> void:
	if not values is Dictionary:
		return
	if values.has("position"):
		var position = values.position
		node.position = Vector3(float(position.get("x", 0)), float(position.get("y", 0)), float(position.get("z", 0)))
	if values.has("rotationDegrees"):
		var rotation = values.rotationDegrees
		node.rotation_degrees = Vector3(float(rotation.get("x", 0)), float(rotation.get("y", 0)), float(rotation.get("z", 0)))
	if values.has("scale"):
		var scale_value = values.scale
		node.scale = Vector3(float(scale_value.get("x", 1)), float(scale_value.get("y", 1)), float(scale_value.get("z", 1)))

func inspect_3d_scene(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("rootPath", ".")))
	if node == null:
		return error_result("3D root node not found")
	var nodes := []
	collect_3d_nodes(node, nodes)
	return ok_result({"rootPath": String(node.get_path()), "nodes": nodes})

func collect_3d_nodes(node: Node, result: Array) -> void:
	if node is Node3D:
		var item := {"path": String(node.get_path()), "name": node.name, "type": node.get_class(), "position": serialize_value(node.position), "rotationDegrees": serialize_value(node.rotation_degrees), "scale": serialize_value(node.scale)}
		if node is GeometryInstance3D:
			item["materialOverride"] = serialize_value(node.material_override)
		if node is MeshInstance3D:
			item["mesh"] = serialize_value(node.mesh)
		result.append(item)
	for child in node.get_children():
		collect_3d_nodes(child, result)

func create_standard_material(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node is GeometryInstance3D:
		return error_result("GeometryInstance3D not found")
	var material := StandardMaterial3D.new()
	material.albedo_color = parse_color(params.get("albedoColor", "#ffffff"))
	material.metallic = float(params.get("metallic", 0.0))
	material.roughness = float(params.get("roughness", 0.5))
	if params.has("emissionColor"):
		material.emission_enabled = true
		material.emission = parse_color(params.get("emissionColor"))
	var save_path := String(params.get("savePath", ""))
	if not save_path.is_empty():
		if not save_path.begins_with("res://"):
			return error_result("savePath must be a res:// path")
		var save_error := ResourceSaver.save(material, save_path)
		if save_error != OK:
			return error_result("Cannot save StandardMaterial3D: %s" % save_error)
	return ok_result(apply_properties_undo(node, {"material_override": material}, "Godot MCP Create Standard Material"))

func assign_editor_material(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	var material = ResourceLoader.load(String(params.get("materialPath", "")))
	if node == null or not node is GeometryInstance3D or material == null or not material is Material:
		return error_result("GeometryInstance3D or Material resource not found")
	return ok_result(apply_properties_undo(node, {"material_override": material}, "Godot MCP Assign Material"))

func get_or_create_animation(player: AnimationPlayer, animation_name: String) -> Animation:
	var library := player.get_animation_library("")
	if library == null:
		library = AnimationLibrary.new()
		player.add_animation_library("", library)
	var animation := library.get_animation(animation_name)
	if animation == null:
		animation = Animation.new()
		library.add_animation(animation_name, animation)
	return animation

func find_animation_value_track(animation: Animation, track_path: NodePath) -> int:
	return animation.find_track(track_path, Animation.TYPE_VALUE)

func create_animation_track(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var player := resolve_node(root, String(params.get("animationPlayerPath", "")))
	if player == null or not player is AnimationPlayer:
		return error_result("AnimationPlayer not found")
	var animation := get_or_create_animation(player, String(params.get("animationName", "")))
	var track_path := NodePath("%s:%s" % [String(params.get("targetNodePath", "")), String(params.get("property", ""))])
	var track := find_animation_value_track(animation, track_path)
	if track < 0:
		track = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, track_path)
	return ok_result({"animationName": String(params.get("animationName", "")), "track": track, "path": String(track_path), "created": true})

func set_animation_key(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var player := resolve_node(root, String(params.get("animationPlayerPath", "")))
	if player == null or not player is AnimationPlayer:
		return error_result("AnimationPlayer not found")
	var animation := get_or_create_animation(player, String(params.get("animationName", "")))
	var track_path := NodePath("%s:%s" % [String(params.get("targetNodePath", "")), String(params.get("property", ""))])
	var track := find_animation_value_track(animation, track_path)
	if track < 0:
		track = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track, track_path)
	var time := float(params.get("time", 0.0))
	animation.length = max(animation.length, time)
	animation.track_insert_key(track, time, decode_value(params.get("value")))
	return ok_result({"animationName": String(params.get("animationName", "")), "track": track, "time": time, "keyInserted": true})

func inspect_animation_timeline(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var player := resolve_node(root, String(params.get("animationPlayerPath", "")))
	if player == null or not player is AnimationPlayer:
		return error_result("AnimationPlayer not found")
	var animations := []
	for animation_name in player.get_animation_list():
		var animation: Animation = player.get_animation(animation_name)
		var tracks := []
		for track in range(animation.get_track_count()):
			tracks.append({"index": track, "type": animation.track_get_type(track), "path": String(animation.track_get_path(track)), "keys": animation.track_get_key_count(track)})
		animations.append({"name": animation_name, "length": animation.length, "tracks": tracks})
	return ok_result({"nodePath": String(player.get_path()), "animations": animations})

func set_animation_tree_state(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var tree := resolve_node(root, String(params.get("nodePath", "")))
	if tree == null or not tree is AnimationTree:
		return error_result("AnimationTree not found")
	var values := {}
	if params.has("active"):
		values["active"] = bool(params.get("active"))
	if params.get("parameters", {}) is Dictionary:
		for key in params.parameters.keys():
			values[String(key)] = decode_value(params.parameters[key])
	return ok_result(apply_properties_undo(tree, values, "Godot MCP Set AnimationTree State"))

func create_navigation_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null:
		return error_result("Navigation parent node not found")
	var node_type := String(params.get("nodeType", "NavigationRegion2D"))
	var node: Node
	match node_type:
		"NavigationRegion2D": node = NavigationRegion2D.new()
		"NavigationRegion3D": node = NavigationRegion3D.new()
		"NavigationAgent2D": node = NavigationAgent2D.new()
		"NavigationAgent3D": node = NavigationAgent3D.new()
		_: return error_result("Unsupported navigation node: %s" % node_type)
	node.name = String(params.get("nodeName", "McpNavigation"))
	return ok_result(add_node_undo(parent, node, root, "Godot MCP Create Navigation Node"))

func configure_navigation_agent(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node is NavigationAgent2D and not node is NavigationAgent3D:
		return error_result("NavigationAgent2D or NavigationAgent3D not found")
	var values = params.get("properties", {})
	if params.get("targetPosition", {}) is Dictionary:
		var target = params.targetPosition
		if node is NavigationAgent3D:
			values["target_position"] = Vector3(float(target.get("x", 0)), float(target.get("y", 0)), float(target.get("z", 0)))
		else:
			values["target_position"] = Vector2(float(target.get("x", 0)), float(target.get("y", 0)))
	return ok_result(apply_properties_undo(node, values, "Godot MCP Configure Navigation Agent"))

func inspect_navigation(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("rootPath", ".")))
	if node == null:
		return error_result("Navigation root node not found")
	var result := []
	collect_nodes_by_prefix(node, result, ["Navigation"])
	return ok_result({"rootPath": String(node.get_path()), "nodes": result})

func create_collision_shape(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var parent := resolve_node(root, String(params.get("parentPath", ".")))
	if parent == null:
		return error_result("Physics parent node not found")
	var dimension := String(params.get("dimension", "2d"))
	var shape_name := String(params.get("shape", "rectangle"))
	var node: Node
	var shape: Resource
	if dimension == "3d":
		var shape_3d: Shape3D
		if shape_name == "box": shape_3d = BoxShape3D.new()
		elif shape_name == "sphere": shape_3d = SphereShape3D.new()
		else: return error_result("3D shape must be box or sphere")
		node = CollisionShape3D.new()
		shape = shape_3d
	else:
		if shape_name == "rectangle": shape = RectangleShape2D.new()
		elif shape_name == "circle": shape = CircleShape2D.new()
		else: return error_result("2D shape must be rectangle or circle")
		node = CollisionShape2D.new()
	var size = params.get("size", {})
	if size is Dictionary:
		if shape is RectangleShape2D and size.has("x"):
			shape.size = Vector2(float(size.get("x", 32)), float(size.get("y", 32)))
		elif shape is CircleShape2D and size.has("radius"):
			shape.radius = float(size.get("radius", 16))
		elif shape is BoxShape3D and size.has("x"):
			shape.size = Vector3(float(size.get("x", 1)), float(size.get("y", 1)), float(size.get("z", 1)))
		elif shape is SphereShape3D and size.has("radius"):
			shape.radius = float(size.get("radius", 0.5))
	node.name = String(params.get("nodeName", "McpCollisionShape"))
	node.set("shape", shape)
	return ok_result(add_node_undo(parent, node, root, "Godot MCP Create Collision Shape"))

func configure_physics_node(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null:
		return error_result("Physics node not found")
	return ok_result(apply_properties_undo(node, params.get("properties", {}), "Godot MCP Configure Physics Node"))

func inspect_physics(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("rootPath", ".")))
	if node == null:
		return error_result("Physics root node not found")
	var result := []
	collect_nodes_by_prefix(node, result, ["Collision", "Area", "StaticBody", "RigidBody", "CharacterBody", "AnimatableBody"])
	return ok_result({"rootPath": String(node.get_path()), "nodes": result})

func get_audio_bus_state() -> Dictionary:
	var buses := []
	for index in range(AudioServer.bus_count):
		buses.append({"index": index, "name": AudioServer.get_bus_name(index), "volumeDb": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index), "solo": AudioServer.is_bus_solo(index), "effectCount": AudioServer.get_bus_effect_count(index)})
	return {"buses": buses}

func set_audio_bus_state(params: Dictionary) -> Dictionary:
	var index := AudioServer.get_bus_index(String(params.get("bus", "Master")))
	if index < 0:
		return error_result("Audio bus not found")
	if params.has("volumeDb"): AudioServer.set_bus_volume_db(index, float(params.volumeDb))
	if params.has("mute"): AudioServer.set_bus_mute(index, bool(params.mute))
	if params.has("solo"): AudioServer.set_bus_solo(index, bool(params.solo))
	return ok_result(get_audio_bus_state())

func configure_editor_audio_player(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("nodePath", "")))
	if node == null or not node is AudioStreamPlayer and not node is AudioStreamPlayer2D and not node is AudioStreamPlayer3D:
		return error_result("Audio player node not found")
	var values := {}
	if params.has("streamPath"): values["stream"] = ResourceLoader.load(String(params.streamPath))
	if params.has("bus"): values["bus"] = String(params.bus)
	if params.has("volumeDb"): values["volume_db"] = float(params.volumeDb)
	if params.has("pitchScale"): values["pitch_scale"] = float(params.pitchScale)
	if params.has("autoplay"): values["autoplay"] = bool(params.autoplay)
	return ok_result(apply_properties_undo(node, values, "Godot MCP Configure Audio Player"))

func inspect_editor_audio_nodes(params: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := resolve_node(root, String(params.get("rootPath", ".")))
	if node == null:
		return error_result("Audio root node not found")
	var result := []
	collect_nodes_by_prefix(node, result, ["AudioStreamPlayer"])
	return ok_result({"rootPath": String(node.get_path()), "nodes": result})

func create_theme_resource(params: Dictionary) -> Dictionary:
	var save_path := String(params.get("savePath", ""))
	if not save_path.begins_with("res://"):
		return error_result("savePath must be a res:// path")
	var theme := Theme.new()
	if params.has("defaultFontSize"): theme.default_font_size = int(params.defaultFontSize)
	if params.get("panelStyle", {}) is Dictionary:
		theme.set_stylebox("panel", "Panel", make_stylebox(params.panelStyle))
	var save_error := ResourceSaver.save(theme, save_path)
	if save_error != OK:
		return error_result("Cannot save Theme resource: %s" % save_error)
	return ok_result({"resourcePath": save_path, "created": true})

func list_editor_plugins() -> Dictionary:
	var result := []
	var addons := DirAccess.open("res://addons")
	if addons:
		for entry in addons.get_directories():
			var plugin_path := "res://addons/%s/plugin.cfg" % entry
			if FileAccess.file_exists(plugin_path):
				result.append({"path": plugin_path, "enabled": EditorInterface.is_plugin_enabled(plugin_path)})
	return ok_result({"plugins": result})

func set_editor_plugin_enabled(params: Dictionary) -> Dictionary:
	var plugin_path := String(params.get("pluginPath", ""))
	if not plugin_path.begins_with("res://") or not FileAccess.file_exists(plugin_path):
		return error_result("Plugin configuration is unavailable")
	EditorInterface.set_plugin_enabled(plugin_path, bool(params.get("enabled", true)))
	return ok_result({"pluginPath": plugin_path, "enabled": EditorInterface.is_plugin_enabled(plugin_path)})

func get_editor_workspace() -> Dictionary:
	return {"openScenes": serialize_value(EditorInterface.get_open_scenes()), "unsavedScenes": serialize_value(EditorInterface.get_unsaved_scenes()), "selectedPaths": serialize_value(EditorInterface.get_selected_paths()), "currentPath": EditorInterface.get_current_path(), "currentDirectory": EditorInterface.get_current_directory(), "selection": get_selection(), "distractionFree": EditorInterface.is_distraction_free_mode_enabled()}

func set_editor_main_screen(params: Dictionary) -> Dictionary:
	var screen := String(params.get("screen", "2D"))
	EditorInterface.set_main_screen_editor(screen)
	return ok_result({"screen": screen, "changed": true})

func set_distraction_free_mode(params: Dictionary) -> Dictionary:
	var enabled := bool(params.get("enabled", false))
	EditorInterface.set_distraction_free_mode(enabled)
	return ok_result({"enabled": EditorInterface.is_distraction_free_mode_enabled()})

func reimport_editor_resources(params: Dictionary) -> Dictionary:
	var filesystem := EditorInterface.get_resource_filesystem()
	var paths := params.get("paths", [])
	if filesystem.has_method("reimport_files") and paths is Array and not paths.is_empty():
		filesystem.call("reimport_files", PackedStringArray(paths))
	else:
		filesystem.scan()
	return ok_result({"paths": paths, "reimported": true})

func collect_nodes_by_prefix(node: Node, result: Array, prefixes: Array) -> void:
	var type_name := node.get_class()
	for prefix in prefixes:
		if type_name.begins_with(String(prefix)):
			result.append({"path": String(node.get_path()), "name": node.name, "type": type_name, "properties": describe_properties(node).properties})
			break
	for child in node.get_children():
		collect_nodes_by_prefix(child, result, prefixes)

func add_node_undo(parent: Node, node: Node, root: Node, action_name: String) -> Dictionary:
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action(action_name)
	undo.add_do_method(parent, "add_child", node)
	undo.add_do_method(self, "set_owner_recursive", node, root)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()
	return {"path": "%s/%s" % [String(parent.get_path()), node.name], "type": node.get_class(), "created": true, "undoable": true}

func set_owner_recursive(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children():
		set_owner_recursive(child, root)

func apply_properties_undo(object: Object, values, action_name: String) -> Dictionary:
	if not values is Dictionary:
		return {"updated": false}
	var undo := EditorInterface.get_editor_undo_redo()
	undo.create_action(action_name)
	var changed := []
	for key in values.keys():
		var property_name := String(key)
		if has_property(object, property_name):
			var old_value = object.get(property_name)
			var new_value = decode_value(values[key])
			undo.add_do_property(object, property_name, new_value)
			undo.add_undo_property(object, property_name, old_value)
			changed.append(property_name)
	undo.commit_action()
	return {"properties": changed, "updated": true, "undoable": true}

func parse_color(value) -> Color:
	if value is Color:
		return value
	return Color.from_string(String(value), Color.WHITE)

func make_stylebox(value) -> StyleBoxFlat:
	if not value is Dictionary:
		return null
	var stylebox := StyleBoxFlat.new()
	stylebox.bg_color = parse_color(value.get("bgColor", "#00000000"))
	for corner in ["topLeft", "topRight", "bottomRight", "bottomLeft"]:
		if value.has("cornerRadius"):
			stylebox.set("corner_radius_%s" % snake_case(corner), int(value.cornerRadius))
	if value.has("borderWidth"):
		for side in ["left", "top", "right", "bottom"]:
			stylebox.set("border_width_%s" % side, int(value.borderWidth))
	if value.has("borderColor"):
		stylebox.border_color = parse_color(value.borderColor)
	return stylebox

func snake_case(value: String) -> String:
	return value.replace("topLeft", "top_left").replace("topRight", "top_right").replace("bottomRight", "bottom_right").replace("bottomLeft", "bottom_left")

func reload_filesystem() -> Dictionary:
	EditorInterface.get_resource_filesystem().scan()
	return ok_result({"reloaded": true})

func execute_script(params: Dictionary) -> Dictionary:
	var script_path := String(params.get("scriptPath", ""))
	var script = ResourceLoader.load(script_path)
	if script == null or not script is Script:
		return error_result("Script cannot be loaded: %s" % script_path)
	var instance = script.new()
	if instance == null or not instance.has_method(String(params.get("method", "run"))):
		return error_result("Script method is unavailable")
	var result = instance.callv(String(params.get("method", "run")), params.get("args", []))
	return ok_result({"result": serialize_value(result), "executed": true})

func resolve_node(root: Node, path: String) -> Node:
	if root == null:
		return null
	if path.is_empty() or path == ".":
		return root
	return root.get_node_or_null(NodePath(path))

func describe_node(node: Node, depth: int, max_depth: int) -> Dictionary:
	var item := {"name": node.name, "path": String(node.get_path()), "type": node.get_class(), "children": []}
	if depth >= max_depth:
		item["truncated"] = node.get_child_count() > 0
		return item
	for child in node.get_children():
		item["children"].append(describe_node(child, depth + 1, max_depth))
	return item

func describe_properties(node: Node) -> Dictionary:
	var properties := {}
	for property in node.get_property_list():
		var name := String(property.name)
		if name in ["script", "owner"]:
			continue
		properties[name] = serialize_value(node.get(name))
	return {"name": node.name, "path": String(node.get_path()), "type": node.get_class(), "properties": properties}

func has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if String(property.name) == property_name:
			return true
	return false

func apply_properties(node: Node, values) -> void:
	if not values is Dictionary:
		return
	for key in values.keys():
		var property_name := String(key)
		if has_property(node, property_name):
			node.set(property_name, decode_value(values[key]))

func decode_value(value):
	if value is Dictionary:
		if value.has("resourcePath"):
			return ResourceLoader.load(String(value.resourcePath))
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
		var converted := {}
		for key in value.keys():
			converted[key] = decode_value(value[key])
		return converted
	if value is Array:
		var converted_array := []
		for item in value:
			converted_array.append(decode_value(item))
		return converted_array
	return value

func serialize_value(value):
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return {"type": "Vector2", "value": [value.x, value.y]}
	if value is Vector3:
		return {"type": "Vector3", "value": [value.x, value.y, value.z]}
	if value is Color:
		return {"type": "Color", "value": value.to_html(true)}
	if value is NodePath:
		return {"type": "NodePath", "value": String(value)}
	if value is Array:
		var converted_array := []
		for item in value:
			converted_array.append(serialize_value(item))
		return converted_array
	if value is Dictionary:
		var converted := {}
		for key in value.keys():
			converted[String(key)] = serialize_value(value[key])
		return converted
	if value is Resource and not value.resource_path.is_empty():
		return {"resourcePath": value.resource_path}
	return str(value)

func ok_result(result) -> Dictionary:
	return {"ok": true, "result": result}

func error_result(message: String, details = {}) -> Dictionary:
	log_message(message)
	return {"ok": false, "error": message, "details": details}

func log_message(message: String) -> void:
	logs.append("[%s] %s" % [Time.get_time_string_from_system(), message])
	if logs.size() > MAX_LOG_ENTRIES:
		logs.pop_front()

func load_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {"schemaVersion": CURRENT_STATE_VERSION}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if parsed is Dictionary:
		return parsed
	return {"schemaVersion": CURRENT_STATE_VERSION}

func migrate_state() -> void:
	var version := int(state.get("schemaVersion", 0))
	while version < CURRENT_STATE_VERSION:
		if version == 0:
			state["schemaVersion"] = 1
		if version == 1:
			state["port"] = DEFAULT_PORT
		version += 1
	state["schemaVersion"] = CURRENT_STATE_VERSION
	save_state()

func save_state() -> void:
	var file := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))
		file.close()

func refresh_status() -> void:
	if not status_label:
		return
	var version_info := Engine.get_version_info()
	var godot_version := String(version_info.get("string", "unknown"))
	var running := tcp_server.is_connection_available() or not peers.is_empty()
	var binding_status := get_binding_status()
	var binding_text := "unbound" if not binding_status.bound else "bound %s (%ss)" % [binding_status.sessionFingerprint, binding_status.leaseSecondsRemaining]
	status_label.text = "Godot MCP Toolkit %s | Godot %s | ws://127.0.0.1:%s | clients: %s" % [PLUGIN_VERSION, godot_version, bridge_port, peers.size() if running else 0]
	if binding_label:
		binding_label.text = "Conversation binding: one-to-one | %s" % binding_text
	if release_binding_button:
		release_binding_button.disabled = not bool(binding_status.bound)

