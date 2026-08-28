##
## CollisionLayers
##
## Single source of truth for the project's collision matrix. Layer numbers in
## the Godot inspector are 1-based; the bit constants below are the values you
## assign to collision_layer / collision_mask in code.
##
## | Layer | Name             | Objects                       | Masks against            |
## |-------|------------------|-------------------------------|--------------------------|
## | 1     | PitchWorld       | Walls, goalposts, boundaries  | Players (2), Ball (3)    |
## | 2     | PlayerBodies     | Player CharacterBody2D        | PitchWorld (1), Players (2) |
## | 3     | BallPhysicsBody  | Ball CharacterBody2D          | PitchWorld (1) only      |
## | 4     | FootSensorArea   | Area2D at player feet         | BallPhysicsBody (3)      |
## | 5     | AerialHitboxZone | Area2D above player shoulders | BallPhysicsBody (3)      |
##
## CRITICAL: the ball (layer 3) must never mask layer 2, and player bodies must
## never mask layer 3. If the ball is a solid obstacle to a CharacterBody2D, the
## move_and_slide() solver zeroes the player's velocity the instant they touch
## it — which destroys the momentum model in HeavyPlayerController. All
## player/ball contact is resolved programmatically through the foot sensor
## (layer 4) and the aerial hitbox (layer 5).
##
## Depends on: nothing.
## Exposes: LAYER_* bit constants and the MASK_* presets used by each entity.
##

class_name CollisionLayers
extends RefCounted

const LAYER_PITCH_WORLD: int = 1 << 0        # layer 1
const LAYER_PLAYER_BODIES: int = 1 << 1      # layer 2
const LAYER_BALL_PHYSICS: int = 1 << 2       # layer 3
const LAYER_FOOT_SENSOR: int = 1 << 3        # layer 4
const LAYER_AERIAL_HITBOX: int = 1 << 4      # layer 5

## Pitch walls / goal frames: collide with players and the ball.
const MASK_PITCH_WORLD: int = LAYER_PLAYER_BODIES | LAYER_BALL_PHYSICS

## Player body: walls and other players. Deliberately NOT the ball.
const MASK_PLAYER_BODIES: int = LAYER_PITCH_WORLD | LAYER_PLAYER_BODIES

## Ball body: walls only. Deliberately NOT players.
const MASK_BALL_PHYSICS: int = LAYER_PITCH_WORLD

## Foot sensor and aerial hitbox: detect the ball, nothing else.
const MASK_FOOT_SENSOR: int = LAYER_BALL_PHYSICS
const MASK_AERIAL_HITBOX: int = LAYER_BALL_PHYSICS
