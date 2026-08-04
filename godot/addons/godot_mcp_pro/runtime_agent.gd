extends Node

const DEFAULT_RUNTIME_PORT := 6505
const BINDING_MODE := "one_to_one"
const BINDING_LEASE_MILLISECONDS := 90000

var tcp_server := TCPServer.new()
var peers: Array[WebSocketPeer] = []
var logs: Array[String] = []
var runtime_port := DEFAULT_RUNTIME_PORT + 1
var bound_session_id := ""
var binding_last_seen_milliseconds := 0
var frames_before_pause := 0
const MAX_FRAME_SAMPLES := 240
const MAX_OBSERVATION_EVENTS := 1000
const MAX_LOG_ENTRIES := 1000
var frame_times_milliseconds: Array[float] = []
var observed_properties: Array[Dictionary] = []
var observed_values := {}
var observation_events: Array[Dictionary] = []
var observation_sequence := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	start_bridge()

func _exit_tree() -> void:
	stop_bridge()

func _process(delta: float) -> void:
	expire_binding_if_needed()
	record_frame_sample(delta)
	poll_observed_properties()
	if frames_before_pause > 0:
		frames_before_pause -= 1
		if frames_before_pause == 0:
			get_tree().paused = true
	if tcp_server.is_connection_available():
		var stream := tcp_server.take_connection()
		var peer := WebSocketPeer.new()
		var accept_error := peer.accept_stream(stream)
		if accept_error == OK:
			peers.append(peer)
		else:
			log_message("Runtime WebSocket accept failed: %s" % accept_error)
	poll_peers()

func start_bridge() -> void:
	var requested_port := int(OS.get_environment("GODOT_MCP_RUNTIME_PORT"))
	if requested_port <= 0:
		requested_port = int(ProjectSettings.get_setting("godot_mcp/runtime_port", 0))
	if requested_port <= 0:
		requested_port = default_runtime_port()
	for offset in range(0, 16):
		var candidate := requested_port + offset
		if tcp_server.listen(candidate, "127.0.0.1") == OK:
			runtime_port = candidate
			log_message("Runtime bridge listening on 127.0.0.1:%s" % runtime_port)
			return
	log_message("Runtime bridge failed to listen from %s to %s" % [requested_port, requested_port + 15])

func default_runtime_port() -> int:
	var project_path := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").to_lower()
	var hash_value := 0
	for index in project_path.length():
		hash_value = (hash_value * 31 + project_path.unicode_at(index)) % 500
	return DEFAULT_RUNTIME_PORT + hash_value + 1

func stop_bridge() -> void:
	for peer in peers:
		peer.close()
	peers.clear()
	tcp_server.stop()

func poll_peers() -> void:
	for index in range(peers.size() - 1, -1, -1):
		var peer: WebSocketPeer = peers[index]
		peer.poll()
		var peer_state := peer.get_ready_state()
		if peer_state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				handle_packet(peer, peer.get_packet().get_string_from_utf8())
		elif peer_state == WebSocketPeer.STATE_CLOSED:
			peers.remove_at(index)

func handle_packet(peer: WebSocketPeer, text: String) -> void:
	var request = JSON.parse_string(text)
	if request == null or not request is Dictionary:
		send_response(peer, "", false, null, "Request JSON is invalid")
		return
	var request_id := String(request.get("id", ""))
	var operation := String(request.get("operation", ""))
	var params = request.get("params", {})
	var response := execute_operation(operation, params if params is Dictionary else {})
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
		"get_runtime_info":
			return ok_result(get_runtime_info())
		"get_scene_tree":
			return get_scene_tree(params)
		"get_node_properties":
			return get_node_properties(params)
		"set_property":
			return set_property(params)
		"call_method":
			return call_method(params)
		"pause":
			get_tree().paused = true
			frames_before_pause = 0
			return ok_result({"paused": true})
		"resume":
			get_tree().paused = false
			frames_before_pause = 0
			return ok_result({"paused": false})
		"step":
			return step_runtime(params)
		"send_input":
			return send_input(params)
		"inject_pointer":
			return inject_pointer(params)
		"configure_observability":
			return configure_observability(params)
		"poll_observability":
			return poll_observability(params)
		"capture_viewport":
			return capture_viewport(params)
		"query_physics":
			return query_physics(params)
		"get_audio_state":
			return ok_result(get_audio_state())
		"set_audio_bus":
			return set_audio_bus(params)
		"play_audio":
			return play_audio(params)
		"get_logs":
			var tail_lines := clampi(int(params.get("tailLines", 200)), 1, 1000)
			return ok_result({"logs": logs.slice(-tail_lines), "latestEvent": observation_sequence})
		_:
			return error_result("Unknown runtime operation: %s" % operation)

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
	log_message("Runtime binding lease expired")

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
		return error_result("Runtime bridge requires a valid MCP sessionId", {"code": "missing_session_id"})
	var requested_project_path := String(params.get("projectPath", ""))
	if not requested_project_path.is_empty() and normalize_project_path(requested_project_path) != normalize_project_path(current_project_path()):
		return error_result("Runtime project does not match the requested MCP project", {"code": "project_mismatch", "projectPath": current_project_path()})
	if not bound_session_id.is_empty() and bound_session_id != session_id:
		return error_result("Runtime is already bound to another MCP conversation", {"code": "runtime_binding_conflict", "projectPath": current_project_path(), "leaseSecondsRemaining": get_binding_status().leaseSecondsRemaining})
	bound_session_id = session_id
	binding_last_seen_milliseconds = Time.get_ticks_msec()
	return ok_result({"projectPath": current_project_path(), "binding": get_binding_status()})

func release_session(params: Dictionary) -> Dictionary:
	expire_binding_if_needed()
	var session_id := String(params.get("sessionId", "")).strip_edges()
	if bound_session_id.is_empty():
		return ok_result({"released": false, "binding": get_binding_status()})
	if session_id != bound_session_id:
		return error_result("Only the bound MCP conversation can release this runtime", {"code": "runtime_binding_conflict", "projectPath": current_project_path()})
	bound_session_id = ""
	binding_last_seen_milliseconds = 0
	return ok_result({"released": true, "binding": get_binding_status()})

func get_runtime_info() -> Dictionary:
	var root := get_tree().current_scene
	return {
		"projectPath": current_project_path(),
		"runtimePort": runtime_port,
		"processId": OS.get_process_id(),
		"paused": get_tree().paused,
		"processFrames": Engine.get_process_frames(),
		"scenePath": root.scene_file_path if root else "",
		"sceneName": root.name if root else "",
		"binding": get_binding_status(),
	}

func runtime_root() -> Node:
	return get_tree().current_scene

func resolve_runtime_node(path: String) -> Node:
	var root := runtime_root()
	if root == null:
		return null
	if path.is_empty() or path == ".":
		return root
	if path.begins_with("/root/"):
		return get_tree().root.get_node_or_null(NodePath(path))
	return root.get_node_or_null(NodePath(path))

func get_scene_tree(params: Dictionary) -> Dictionary:
	var root := runtime_root()
	if root == null:
		return error_result("No runtime scene is active")
	return ok_result({"scenePath": root.scene_file_path, "tree": describe_node(root, 0, clampi(int(params.get("maxDepth", 16)), 0, 64))})

func get_node_properties(params: Dictionary) -> Dictionary:
	var node := resolve_runtime_node(String(params.get("nodePath", ".")))
	if node == null:
		return error_result("Runtime node not found")
	return ok_result(describe_properties(node))

func set_property(params: Dictionary) -> Dictionary:
	var node := resolve_runtime_node(String(params.get("nodePath", "")))
	var property_name := String(params.get("property", ""))
	if node == null or property_name.is_empty() or not has_property(node, property_name):
		return error_result("Runtime node property not found")
	var previous_value = serialize_value(node.get(property_name))
	node.set(property_name, decode_value(params.get("value")))
	return ok_result({"nodePath": String(node.get_path()), "property": property_name, "previousValue": previous_value, "value": serialize_value(node.get(property_name)), "updated": true})

func call_method(params: Dictionary) -> Dictionary:
	var node := resolve_runtime_node(String(params.get("nodePath", "")))
	var method_name := String(params.get("method", ""))
	if node == null or method_name.is_empty() or not node.has_method(method_name):
		return error_result("Runtime node method not found")
	var decoded_args := []
	for value in params.get("args", []):
		decoded_args.append(decode_value(value))
	var result = node.callv(method_name, decoded_args)
	return ok_result({"nodePath": String(node.get_path()), "method": method_name, "result": serialize_value(result), "called": true})

func step_runtime(params: Dictionary) -> Dictionary:
	var frame_count := clampi(int(params.get("frames", 1)), 1, 120)
	get_tree().paused = false
	frames_before_pause = frame_count
	return ok_result({"paused": false, "frames": frame_count, "stepping": true})

func send_input(params: Dictionary) -> Dictionary:
	var event_type := String(params.get("eventType", "key"))
	if event_type == "key":
		var key_event := InputEventKey.new()
		key_event.keycode = int(params.get("keycode", 0))
		key_event.physical_keycode = int(params.get("physicalKeycode", 0))
		key_event.pressed = bool(params.get("pressed", true))
		key_event.echo = bool(params.get("echo", false))
		Input.parse_input_event(key_event)
		return ok_result({"eventType": "key", "injected": true})
	if event_type == "mouse_button":
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = int(params.get("buttonIndex", 1))
		mouse_event.pressed = bool(params.get("pressed", true))
		var position = params.get("position", {})
		if position is Dictionary:
			mouse_event.position = Vector2(float(position.get("x", 0)), float(position.get("y", 0)))
		Input.parse_input_event(mouse_event)
		return ok_result({"eventType": "mouse_button", "injected": true})
	return error_result("Unsupported runtime input event type")

func inject_pointer(params: Dictionary) -> Dictionary:
	var pointer_type := String(params.get("pointerType", "move"))
	var position := vector2_from(params.get("position", {}))
	if pointer_type == "move":
		var move_event := InputEventMouseMotion.new()
		move_event.position = position
		move_event.relative = vector2_from(params.get("relative", {}))
		Input.parse_input_event(move_event)
		return ok_result({"pointerType": pointer_type, "position": serialize_value(position), "injected": true})
	if pointer_type == "wheel":
		var scroll_y := int(params.get("scrollY", 0))
		if scroll_y == 0:
			return error_result("scrollY must be non-zero for a wheel event")
		var wheel_steps := clampi(absi(scroll_y), 1, 24)
		var wheel_button := MOUSE_BUTTON_WHEEL_UP if scroll_y > 0 else MOUSE_BUTTON_WHEEL_DOWN
		for _index in range(wheel_steps):
			var wheel_event := InputEventMouseButton.new()
			wheel_event.position = position
			wheel_event.button_index = wheel_button
			wheel_event.pressed = true
			Input.parse_input_event(wheel_event)
		return ok_result({"pointerType": pointer_type, "steps": wheel_steps, "injected": true})
	if pointer_type == "touch":
		var touch_event := InputEventScreenTouch.new()
		touch_event.index = int(params.get("touchIndex", 0))
		touch_event.position = position
		touch_event.pressed = bool(params.get("pressed", true))
		Input.parse_input_event(touch_event)
		return ok_result({"pointerType": pointer_type, "touchIndex": touch_event.index, "injected": true})
	if pointer_type == "touch_drag":
		var touch_drag := InputEventScreenDrag.new()
		touch_drag.index = int(params.get("touchIndex", 0))
		touch_drag.position = position
		touch_drag.relative = vector2_from(params.get("relative", {}))
		Input.parse_input_event(touch_drag)
		return ok_result({"pointerType": pointer_type, "touchIndex": touch_drag.index, "injected": true})
	if pointer_type == "drag":
		var from_position := vector2_from(params.get("from", {}))
		var to_position := vector2_from(params.get("to", {}))
		var button_index := int(params.get("buttonIndex", MOUSE_BUTTON_LEFT))
		var drag_steps := clampi(int(params.get("steps", 8)), 1, 120)
		var press_event := InputEventMouseButton.new()
		press_event.position = from_position
		press_event.button_index = button_index
		press_event.pressed = true
		Input.parse_input_event(press_event)
		for index in range(1, drag_steps + 1):
			var fraction := float(index) / float(drag_steps)
			var drag_event := InputEventMouseMotion.new()
			drag_event.position = from_position.lerp(to_position, fraction)
			drag_event.relative = (to_position - from_position) / float(drag_steps)
			Input.parse_input_event(drag_event)
		var release_event := InputEventMouseButton.new()
		release_event.position = to_position
		release_event.button_index = button_index
		release_event.pressed = false
		Input.parse_input_event(release_event)
		return ok_result({"pointerType": pointer_type, "steps": drag_steps, "injected": true})
	return error_result("Unsupported runtime pointer type")

func configure_observability(params: Dictionary) -> Dictionary:
	observed_properties.clear()
	observed_values.clear()
	var invalid_watches := []
	for watch_value in params.get("watches", []):
		if not watch_value is Dictionary:
			invalid_watches.append(watch_value)
			continue
		var node_path := String(watch_value.get("nodePath", ""))
		var property_name := String(watch_value.get("property", ""))
		var node := resolve_runtime_node(node_path)
		if node == null or property_name.is_empty() or not has_property(node, property_name):
			invalid_watches.append({"nodePath": node_path, "property": property_name})
			continue
		var watch := {"nodePath": node_path, "property": property_name}
		observed_properties.append(watch)
		observed_values[observation_key(node_path, property_name)] = serialize_value(node.get(property_name))
	append_observation_event("watch_configured", {"count": observed_properties.size()})
	return ok_result({"watches": observed_properties, "invalidWatches": invalid_watches, "latestEvent": observation_sequence})

func poll_observability(params: Dictionary) -> Dictionary:
	var since := maxi(int(params.get("since", 0)), 0)
	var limit := clampi(int(params.get("limit", 200)), 1, 1000)
	var events := []
	for event in observation_events:
		if int(event.get("sequence", 0)) <= since:
			continue
		events.append(event)
		if events.size() >= limit:
			break
	return ok_result({"events": events, "latestEvent": observation_sequence, "watches": observed_properties, "metrics": get_runtime_metrics()})

func record_frame_sample(delta: float) -> void:
	frame_times_milliseconds.append(maxf(delta, 0.0) * 1000.0)
	if frame_times_milliseconds.size() > MAX_FRAME_SAMPLES:
		frame_times_milliseconds.pop_front()

func get_runtime_metrics() -> Dictionary:
	var total := 0.0
	var minimum := 0.0
	var maximum := 0.0
	for frame_time in frame_times_milliseconds:
		total += frame_time
		if minimum == 0.0 or frame_time < minimum:
			minimum = frame_time
		if frame_time > maximum:
			maximum = frame_time
	var average := total / float(frame_times_milliseconds.size()) if not frame_times_milliseconds.is_empty() else 0.0
	return {"sampleCount": frame_times_milliseconds.size(), "averageFrameMs": average, "minFrameMs": minimum, "maxFrameMs": maximum, "fps": Engine.get_frames_per_second(), "processFrames": Engine.get_process_frames(), "physicsFrames": Engine.get_physics_frames(), "paused": get_tree().paused}

func poll_observed_properties() -> void:
	for watch in observed_properties:
		var node_path := String(watch.get("nodePath", ""))
		var property_name := String(watch.get("property", ""))
		var node := resolve_runtime_node(node_path)
		var key := observation_key(node_path, property_name)
		if node == null or not has_property(node, property_name):
			if observed_values.has(key):
				append_observation_event("watch_unavailable", {"nodePath": node_path, "property": property_name})
				observed_values.erase(key)
			continue
		var current_value = serialize_value(node.get(property_name))
		if not observed_values.has(key) or JSON.stringify(observed_values[key]) != JSON.stringify(current_value):
			var previous_value = observed_values.get(key, null)
			observed_values[key] = current_value
			append_observation_event("property_changed", {"nodePath": node_path, "property": property_name, "previousValue": previous_value, "value": current_value})

func observation_key(node_path: String, property_name: String) -> String:
	return "%s:%s" % [node_path, property_name]

func append_observation_event(kind: String, payload: Dictionary) -> void:
	observation_sequence += 1
	observation_events.append({"sequence": observation_sequence, "timeMs": Time.get_ticks_msec(), "kind": kind, "payload": payload})
	if observation_events.size() > MAX_OBSERVATION_EVENTS:
		observation_events.pop_front()

func vector2_from(value, fallback := Vector2.ZERO) -> Vector2:
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)))
	return fallback

func capture_viewport(params: Dictionary) -> Dictionary:
	var output_path := String(params.get("outputPath", ""))
	if output_path.is_empty():
		return error_result("outputPath is required")
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return error_result("Runtime viewport image is unavailable")
	var save_error := image.save_png(output_path)
	if save_error != OK:
		return error_result("Runtime screenshot could not be saved", {"errorCode": save_error})
	return ok_result({"outputPath": output_path, "captured": true})

func query_physics(params: Dictionary) -> Dictionary:
	var dimension := String(params.get("dimension", "2d"))
	var from_value = params.get("from", {})
	var to_value = params.get("to", {})
	var collision_mask := int(params.get("collisionMask", 0x7fffffff))
	if dimension == "3d":
		var root_3d := runtime_root() as Node3D
		if root_3d == null:
			return error_result("A Node3D runtime scene is required for a 3D physics query")
		var query_3d := PhysicsRayQueryParameters3D.new()
		query_3d.from = Vector3(float(from_value.get("x", 0)), float(from_value.get("y", 0)), float(from_value.get("z", 0)))
		query_3d.to = Vector3(float(to_value.get("x", 0)), float(to_value.get("y", 0)), float(to_value.get("z", 0)))
		query_3d.collision_mask = collision_mask
		var result_3d := root_3d.get_world_3d().direct_space_state.intersect_ray(query_3d)
		return ok_result({"dimension": "3d", "hit": not result_3d.is_empty(), "result": serialize_value(result_3d)})
	var root_2d := runtime_root() as Node2D
	if root_2d == null:
		return error_result("A Node2D runtime scene is required for a 2D physics query")
	var query_2d := PhysicsRayQueryParameters2D.new()
	query_2d.from = Vector2(float(from_value.get("x", 0)), float(from_value.get("y", 0)))
	query_2d.to = Vector2(float(to_value.get("x", 0)), float(to_value.get("y", 0)))
	query_2d.collision_mask = collision_mask
	var result_2d := root_2d.get_world_2d().direct_space_state.intersect_ray(query_2d)
	return ok_result({"dimension": "2d", "hit": not result_2d.is_empty(), "result": serialize_value(result_2d)})

func get_audio_state() -> Dictionary:
	var buses := []
	for index in range(AudioServer.bus_count):
		var effects := []
		for effect_index in range(AudioServer.get_bus_effect_count(index)):
			var effect = AudioServer.get_bus_effect(index, effect_index)
			effects.append({"index": effect_index, "type": effect.get_class() if effect else ""})
		buses.append({"index": index, "name": AudioServer.get_bus_name(index), "volumeDb": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index), "solo": AudioServer.is_bus_solo(index), "effects": effects})
	return {"buses": buses}

func set_audio_bus(params: Dictionary) -> Dictionary:
	var bus_name := String(params.get("bus", "Master"))
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return error_result("Audio bus not found: %s" % bus_name)
	if params.has("volumeDb"):
		AudioServer.set_bus_volume_db(index, float(params.get("volumeDb")))
	if params.has("mute"):
		AudioServer.set_bus_mute(index, bool(params.get("mute")))
	if params.has("solo"):
		AudioServer.set_bus_solo(index, bool(params.get("solo")))
	return ok_result({"index": index, "name": AudioServer.get_bus_name(index), "volumeDb": AudioServer.get_bus_volume_db(index), "mute": AudioServer.is_bus_mute(index), "solo": AudioServer.is_bus_solo(index)})

func play_audio(params: Dictionary) -> Dictionary:
	var node := resolve_runtime_node(String(params.get("nodePath", "")))
	if node == null or not (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D):
		return error_result("Audio player node not found")
	if params.has("volumeDb") and has_property(node, "volume_db"):
		node.set("volume_db", float(params.get("volumeDb")))
	if params.has("pitchScale") and has_property(node, "pitch_scale"):
		node.set("pitch_scale", float(params.get("pitchScale")))
	node.play(float(params.get("fromPosition", 0.0)))
	return ok_result({"nodePath": String(node.get_path()), "playing": true})

func describe_node(node: Node, depth: int, max_depth: int) -> Dictionary:
	var item := {"name": node.name, "path": String(node.get_path()), "type": node.get_class(), "groups": node.get_groups(), "children": []}
	if node is Node2D:
		item["position"] = [node.global_position.x, node.global_position.y]
	if node is Node3D:
		item["position"] = [node.global_position.x, node.global_position.y, node.global_position.z]
	if depth >= max_depth:
		item["truncated"] = node.get_child_count() > 0
		return item
	for child in node.get_children():
		item["children"].append(describe_node(child, depth + 1, max_depth))
	return item

func describe_properties(node: Node) -> Dictionary:
	var properties := {}
	for property_info in node.get_property_list():
		var property_name := String(property_info.name)
		if property_name in ["script", "owner"]:
			continue
		properties[property_name] = serialize_value(node.get(property_name))
	return {"name": node.name, "path": String(node.get_path()), "type": node.get_class(), "properties": properties}

func has_property(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if String(property_info.name) == property_name:
			return true
	return false

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
	if value is Node:
		return {"type": "Node", "path": String(value.get_path())}
	if value is Resource and not value.resource_path.is_empty():
		return {"resourcePath": value.resource_path}
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
	return str(value)

func ok_result(result) -> Dictionary:
	return {"ok": true, "result": result}

func error_result(message: String, details = {}) -> Dictionary:
	log_message(message)
	return {"ok": false, "error": message, "details": details}

func log_message(message: String) -> void:
	logs.append("[%s] %s" % [Time.get_time_string_from_system(), message])
	append_observation_event("runtime_log", {"message": message})
	if logs.size() > MAX_LOG_ENTRIES:
		logs.pop_front()
