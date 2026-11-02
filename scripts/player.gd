extends CharacterBody2D

# ==========================================
# ESTADOS (animacoes)
# ==========================================
enum State { IDLE, RUN, JUMP, FALL, DASH, HURT, DIE }
var current_state: State = State.IDLE

# ==========================================
# MOVIMENTO
# ==========================================
const SPEED := 300.0
const ACCELERATION := 1500.0
const FRICTION := 1200.0

# ==========================================
# PULO
# ==========================================
const JUMP_VELOCITY := -400.0
const MAX_JUMPS := 2
const JUMP_CUT := 0.5
const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.1

# ==========================================
# PAREDE
# ==========================================
const WALL_SLIDE_SPEED := 60.0
const WALL_JUMP_VELOCITY := Vector2(350.0, -380.0)

# ==========================================
# DASH
# ==========================================
const DASH_SPEED := 700.0
const DASH_TIME := 0.15
const DASH_COOLDOWN := 0.5

# ==========================================
# VISUAL
# ==========================================
const BODY_SIZE := Vector2(32, 48)
const DASH_COLOR := Color(1.0, 0.9, 0.3)
const SPRITE_OLHA_PRA_DIREITA := true

# ==========================================
# VARIAVEIS
# ==========================================
var foot_offset := 10.0

var jumps_left := MAX_JUMPS
var coyote_timer := 0.0
var jump_buffer_timer := 0.0

var dash_timer := 0.0
var dash_cooldown_timer := 0.0
var dash_direction := 1.0

var facing := 1.0
var can_dash := true

# Efeitos
var body_scale := Vector2.ONE
var was_on_floor := false
var ghosts: Array = []
var dust: Array = []
var shake := 0.0

# Sprite (achado automaticamente, qualquer nome)
var anim: AnimatedSprite2D = null
var sprite_base_scale := Vector2.ONE

# Camera
var main_camera: Camera2D = null
var camera_original_offset := Vector2.ZERO


func _ready() -> void:
	randomize()

	# Procura o AnimatedSprite2D filho do player, com qualquer nome
	for child in get_children():
		if child is AnimatedSprite2D:
			anim = child
			sprite_base_scale = anim.scale.abs()
			break

	# Camera: o script move a camera direto
	var camera = get_tree().get_first_node_in_group("main_camera")
	if camera:
		main_camera = camera
		camera_original_offset = camera.offset
		camera.global_position = global_position
		print("CAMERA OK: ", camera.get_path())
	else:
		push_warning("CAMERA NAO ACHADA: nenhum no no grupo main_camera")


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")

	if direction != 0.0:
		facing = sign(direction)

	# ---------- TIMERS ----------
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	jump_buffer_timer = maxf(jump_buffer_timer - delta, 0.0)

	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER_TIME

	# ---------- DASH ----------
	if Input.is_action_just_pressed("dash"):
		if can_dash and dash_cooldown_timer <= 0.0:
			dash_timer = DASH_TIME
			dash_cooldown_timer = DASH_COOLDOWN
			dash_direction = facing
			can_dash = false
			shake = 6.0
			body_scale = Vector2(1.5, 0.6)

	if dash_timer > 0.0:
		dash_timer = maxf(dash_timer - delta, 0.0)

		velocity.x = dash_direction * DASH_SPEED
		velocity.y = 0.0

		ghosts.append({
			"pos": global_position,
			"scale": body_scale,
			"life": 0.25
		})

		move_and_slide()
		update_state(direction)
		play_state_animation()
		_update_effects(delta)
		return

	# ---------- CHAO E GRAVIDADE ----------
	if is_on_floor():
		jumps_left = MAX_JUMPS
		coyote_timer = COYOTE_TIME
		can_dash = true
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)
		velocity += get_gravity() * delta

	# ---------- PAREDE ----------
	var on_wall := is_on_wall_only()

	if on_wall and velocity.y > 0.0:
		velocity.y = minf(velocity.y, WALL_SLIDE_SPEED)

		if randf() < 0.3:
			_spawn_dust(global_position + Vector2(-get_wall_normal().x * 16, foot_offset), 1)

	# ---------- PULO ----------
	if jump_buffer_timer > 0.0:
		if on_wall:
			velocity.x = get_wall_normal().x * WALL_JUMP_VELOCITY.x
			velocity.y = WALL_JUMP_VELOCITY.y
			jump_buffer_timer = 0.0
			jumps_left = MAX_JUMPS - 1
			_jump_fx()

		elif coyote_timer > 0.0:
			velocity.y = JUMP_VELOCITY
			jump_buffer_timer = 0.0
			coyote_timer = 0.0
			jumps_left = MAX_JUMPS - 1
			_jump_fx()

		elif jumps_left > 0:
			velocity.y = JUMP_VELOCITY
			jump_buffer_timer = 0.0
			jumps_left -= 1
			_jump_fx()

	# ---------- PULO VARIAVEL ----------
	if Input.is_action_just_released("ui_accept") and velocity.y < 0.0:
		velocity.y *= JUMP_CUT

	# ---------- MOVIMENTO HORIZONTAL ----------
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * SPEED, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	move_and_slide()

	# ---------- ATERRISSAGEM ----------
	if is_on_floor() and not was_on_floor:
		body_scale = Vector2(1.4, 0.65)
		_spawn_dust(global_position + Vector2(0, foot_offset), 8)
		shake = 3.0

	was_on_floor = is_on_floor()

	# ---------- POEIRA AO CORRER ----------
	if is_on_floor() and abs(velocity.x) > SPEED * 0.8 and randf() < 0.25:
		_spawn_dust(global_position + Vector2(-facing * 12, foot_offset), 1)

	# ---------- ANIMACAO ----------
	update_state(direction)
	play_state_animation()

	_update_effects(delta)


# ==========================================
# ESTADOS E ANIMACOES
# ==========================================
func update_state(direction: float) -> void:
	if current_state == State.DIE or current_state == State.HURT:
		return

	if dash_timer > 0.0:
		current_state = State.DASH
	elif not is_on_floor():
		if velocity.y < 0.0:
			current_state = State.JUMP
		else:
			current_state = State.FALL
	elif direction != 0.0:
		current_state = State.RUN
	else:
		current_state = State.IDLE


func play_state_animation() -> void:
	match current_state:
		State.IDLE:
			_play("idle")
		State.RUN:
			_play("run")
		State.JUMP:
			_play("jump")
		State.FALL:
			_play("fall", "jump")
		State.DASH:
			_play("dash", "run")
		State.HURT:
			_play("hurt")
		State.DIE:
			_play("die")


# Toca a animacao se ela existir (senao tenta a reserva, senao nao faz nada)
func _play(nome: String, reserva: String = "") -> void:
	if not anim or not anim.sprite_frames:
		return

	var alvo := nome
	if not anim.sprite_frames.has_animation(alvo):
		alvo = reserva

	if alvo == "" or not anim.sprite_frames.has_animation(alvo):
		return

	if anim.animation != alvo or not anim.is_playing():
		anim.play(alvo)


# ==========================================
# EFEITO DO PULO
# ==========================================
func _jump_fx() -> void:
	body_scale = Vector2(0.7, 1.4)
	_spawn_dust(global_position + Vector2(0, foot_offset), 5)


# ==========================================
# CRIAR POEIRA
# ==========================================
func _spawn_dust(pos: Vector2, amount: int) -> void:
	for i in range(amount):
		dust.append({
			"pos": pos,
			"vel": Vector2(randf_range(-60.0, 60.0), randf_range(-70.0, -10.0)),
			"life": randf_range(0.25, 0.5),
			"max": 0.5
		})


# ==========================================
# ATUALIZAR EFEITOS
# ==========================================
func _update_effects(delta: float) -> void:
	# Camera presa no dragao
	if main_camera:
		main_camera.global_position = global_position

	# Squash e stretch
	body_scale = body_scale.lerp(Vector2.ONE, minf(12.0 * delta, 1.0))

	if not is_on_floor():
		var stretch := clampf(abs(velocity.y) / 1500.0, 0.0, 0.25)
		body_scale = body_scale.lerp(Vector2(1.0 - stretch, 1.0 + stretch), minf(6.0 * delta, 1.0))

	# Vira o sprite pelo scale (sem flip_h, pra nao virar duas vezes)
	if anim:
		var lado := facing if SPRITE_OLHA_PRA_DIREITA else -facing
		anim.scale = Vector2(
			lado * body_scale.x * sprite_base_scale.x,
			body_scale.y * sprite_base_scale.y
		)

	# Fantasmas do dash
	for g in ghosts:
		g["life"] -= delta
	ghosts = ghosts.filter(func(g): return g["life"] > 0.0)

	# Poeira
	for d in dust:
		d["life"] -= delta
		d["pos"] += d["vel"] * delta
		d["vel"].y += 150.0 * delta
	dust = dust.filter(func(d): return d["life"] > 0.0)

	# Camera shake
	shake = move_toward(shake, 0.0, 30.0 * delta)

	if main_camera:
		main_camera.offset = camera_original_offset + Vector2(
			randf_range(-shake, shake),
			randf_range(-shake, shake)
		)

	queue_redraw()


# ==========================================
# DESENHAR EFEITOS
# ==========================================
func _draw() -> void:
	# Rastro do dash
	for g in ghosts:
		var a: float = g["life"] / 0.25
		var size: Vector2 = BODY_SIZE * g["scale"]
		var local: Vector2 = g["pos"] - global_position
		draw_rect(Rect2(local - size / 2.0, size), Color(DASH_COLOR, a * 0.5))

	# Poeira
	for d in dust:
		var a: float = d["life"] / d["max"]
		draw_circle(d["pos"] - global_position, 3.0 * a + 1.0, Color(1.0, 1.0, 1.0, a * 0.7))
