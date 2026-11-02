
extends Area2D

# Arraste outro portal da cena pra esse campo no Inspetor
@export var destino: Area2D

var pode_usar := true


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not pode_usar:
		return
	if body is CharacterBody2D and destino:
		# Evita ficar indo e voltando sem parar
		destino.pode_usar = false
		body.global_position = destino.global_position
		body.velocity = Vector2.ZERO


func _on_body_exited(body: Node2D) -> void:
	if body is CharacterBody2D:
		pode_usar = true
