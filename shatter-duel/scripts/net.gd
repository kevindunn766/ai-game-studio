extends Node
# Networking layer for the 2-device block-battle prototype.
#
# Transport: Godot high-level multiplayer over ENet (reliable UDP on the LAN).
# Discovery: the host broadcasts a small UDP "beacon" once a second; a joining
#            device listens for it and grabs the host's IP automatically, so the
#            player never types an address. Works over a phone hotspot because
#            both devices share one subnet regardless of the hotspot's IP scheme.
# Manual IP entry is kept as a fallback for when broadcast is blocked.

signal peer_ready
signal opponent_left
signal status_changed(text)
signal garbage_received(count)
signal opponent_count_changed(n)
signal opponent_declared_win

const GAME_PORT := 8123
const BEACON_PORT := 8124
const BEACON_MSG := "SHATTERDUEL_V1"

var is_host := false

var _beacon: PacketPeerUDP
var _discover: PacketPeerUDP
var _beacon_accum := 0.0
var _signals_bound := false

func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, 1)
	if err != OK:
		_emit_status("Host failed (err %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	_bind_mp_signals()
	_start_beacon()
	_emit_status("Hosting - waiting for a player to join...")

func join_auto() -> void:
	is_host = false
	_discover = PacketPeerUDP.new()
	var err := _discover.bind(BEACON_PORT)
	if err != OK:
		_emit_status("Discovery failed (err %d) - try Join by IP" % err)
		_discover = null
		return
	_emit_status("Searching for a host on this network...")

func join_ip(ip: String) -> void:
	is_host = false
	var addr := ip.strip_edges()
	if addr == "":
		addr = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr, GAME_PORT)
	if err != OK:
		_emit_status("Join failed (err %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	_bind_mp_signals()
	_emit_status("Connecting to %s ..." % addr)

func _bind_mp_signals() -> void:
	if _signals_bound:
		return
	_signals_bound = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", BEACON_PORT)

func _process(delta: float) -> void:
	if _beacon != null:
		_beacon_accum += delta
		if _beacon_accum >= 1.0:
			_beacon_accum = 0.0
			_beacon.put_packet(BEACON_MSG.to_utf8_buffer())
	if _discover != null:
		while _discover.get_available_packet_count() > 0:
			var data := _discover.get_packet()
			var ip := _discover.get_packet_ip()
			if ip != "" and data.get_string_from_utf8() == BEACON_MSG:
				_emit_status("Found host at %s - connecting..." % ip)
				_discover.close()
				_discover = null
				join_ip(ip)
				break

# --- multiplayer callbacks ---
func _on_peer_connected(_id: int) -> void:
	# Host side: a client just joined. Stop advertising and start the match.
	if _beacon != null:
		_beacon.close()
		_beacon = null
	emit_signal("peer_ready")

func _on_connected_to_server() -> void:
	# Client side: handshake with the host succeeded.
	emit_signal("peer_ready")

func _on_connection_failed() -> void:
	_emit_status("Connection failed")

func _on_peer_disconnected(_id: int) -> void:
	emit_signal("opponent_left")

func _on_server_disconnected() -> void:
	emit_signal("opponent_left")

func _emit_status(t: String) -> void:
	emit_signal("status_changed", t)

# --- gameplay sync (thin wrappers so game.gd never touches rpc plumbing) ---
func send_garbage(count: int) -> void:
	rpc_recv_garbage.rpc(count)

func send_count(n: int) -> void:
	rpc_recv_count.rpc(n)

func send_win() -> void:
	rpc_recv_win.rpc()

@rpc("any_peer", "call_remote", "reliable")
func rpc_recv_garbage(count: int) -> void:
	emit_signal("garbage_received", count)

@rpc("any_peer", "call_remote", "reliable")
func rpc_recv_count(n: int) -> void:
	emit_signal("opponent_count_changed", n)

@rpc("any_peer", "call_remote", "reliable")
func rpc_recv_win() -> void:
	emit_signal("opponent_declared_win")
