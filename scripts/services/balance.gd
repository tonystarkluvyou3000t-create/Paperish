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
@export var preparation_duration := 1.25
@export var base_pay := 10
@export var pay_per_pizza := 2
@export var max_tip := 8
@export var max_queued_orders := 3
@export var van_capacity := 6
@export var player_carry_capacity := 3
@export var quality_bonus := 2
@export var quality_penalty := 2
@export var quality_bonus_threshold := 0.72
@export var quality_penalty_threshold := 0.18
@export var conservative_route_speed := 4.2
@export var route_parking_allowance := 8.0

# Navigation (Phase 11). A ticket budget is the conservative route estimate plus
# preparation-independent allowances, so no deadline ever assumes a zero-second
# hop-out, walk and handoff. Guidance is advice: the van still follows the
# player's driving.
@export var route_walk_speed := 1.35
@export var route_exit_allowance := 2.0
@export var route_handoff_allowance := 2.5
@export var route_stop_service := 6.0
@export var deadline_min_slack := 12.0
@export var route_deviate_m := 22.0
@export var route_deviate_foot_m := 12.0
@export var route_recompute_cooldown := 0.8
@export var route_arrive_m := 6.0
@export var unstuck_time_cost := 15.0
@export var unstuck_min_remaining := 3.0
@export var stopped_speed := 0.25
@export var exit_clearance := 0.20
@export var exit_max_step := 0.45
@export var exit_max_drop := 0.75
@export var exit_floor_gap := 0.04

# Camera. Boom = full 3D distance from the head-level pivot; pitch = boom
# elevation in degrees. Defaults reproduce the Phase 03 framing.
@export var cam_mouse_sensitivity := 0.0032     # radians per pixel
@export var cam_pad_sensitivity := 2.6          # radians per second at full stick
@export var cam_invert_y := false
@export var cam_zoom_step := 1.6                # metres per wheel notch
@export var cam_foot_dist_min := 6.5
@export var cam_foot_dist_max := 24.0
@export var cam_foot_dist_default := 14.6
@export var cam_foot_pitch_min := 8.0
@export var cam_foot_pitch_max := 74.0
@export var cam_foot_pitch_default := 30.0
@export var cam_foot_recenter_offset := 140.0
@export var cam_chase_dist_min := 9.0
@export var cam_chase_dist_max := 30.0
@export var cam_chase_dist_default := 19.6
@export var cam_chase_pitch_min := 6.0
@export var cam_chase_pitch_max := 55.0
@export var cam_chase_pitch_default := 30.0
@export var cam_recenter_grace := 1.2           # seconds of manual look before chase recenters
@export var cam_recenter_rate := 2.4
@export var cam_transition_rate := 3.2
@export var cam_extend_rate := 5.0
@export var cam_pitch_ease := 70.0              # degrees per second into a mode's range
@export var cam_collision_radius := 0.35
@export var cam_collision_skin := 0.25
@export var cam_foot_min_boom := 1.1
@export var cam_chase_min_boom := 2.2
@export var cam_occlude_fade_start := 4.5
@export var cam_occlude_fade_end := 1.5
@export var cam_occlude_fade_max := 0.55
@export var cam_free_speed := 9.0
@export var cam_free_boost := 3.0
@export var cam_free_extent := 320.0
@export var cam_free_floor := -8.0
@export var cam_free_ceiling := 150.0
@export var cam_free_return_time := 0.35
