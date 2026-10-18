extends Resource
## Configuration only: run state belongs to the services, never this resource.
@export var goal_money := 150
@export var max_strikes := 3
@export var pickup_range := 3.6
@export var door_range := 3.6
@export var van_range := 3.8
@export var deadline_start := 82.0
@export var deadline_floor := 45.0
@export var deadline_decrease := 3.0
@export var base_pay := 10
@export var pay_per_pizza := 2
@export var max_tip := 8
@export var stopped_speed := 0.25
@export var exit_clearance := 0.20
@export var exit_max_step := 0.45
@export var exit_max_drop := 0.75
@export var exit_floor_gap := 0.04
