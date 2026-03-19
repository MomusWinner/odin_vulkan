package ve

import "core:log"
import lin "core:math/linalg/glsl"
import vemath "math"
import vk "vendor:vulkan"

@(private)
DEFAULT_FOV :: 45
@(private)
DEFAULT_NEAR :: 0.01
@(private)
DEFAULT_FAR :: 100

Camera_UBO :: struct {
	view:       mat4,
	projection: mat4,
	position:   vec3,
}

Camera_Projection_Type :: enum {
	Perspective,
	Orthographic,
	Custom,
}

Camera_Custom_Projection_Proc :: #type proc "c" (user_data: rawptr, camera: ^Camera, aspect: f32) -> mat4

Camera :: struct {
	type:        Camera_Projection_Type,
	position:    vec3,
	zoom:        vec3,
	target:      vec3,
	up:          vec3,
	fov:         f32,
	near:        f32,
	far:         f32,
	dirty:       bool,
	last_aspect: f32,
	custom:      struct {
		projection: Camera_Custom_Projection_Proc,
		user_data:  rawptr,
	},
	buffer_h:    Buffer_Handle, // Camera_UBO
}

// Sets a custom projection for the camera.
// NOTE: The caller is responsible for cleaning up user_data.
camera_init_custom :: proc(
	camera: ^Camera,
	user_data: rawptr,
	projection: Camera_Custom_Projection_Proc,
	loc := #caller_location,
) {
	assert_not_nil(camera, loc)
	assert(projection != nil, loc = loc)

	camera.fov = DEFAULT_FOV
	camera.near = DEFAULT_NEAR
	camera.far = DEFAULT_FAR
	camera.zoom = 1
	camera.type = .Custom
	camera.dirty = true

	camera.custom.projection = projection
	camera.custom.user_data = user_data
}

camera_init :: proc(camera: ^Camera, type: Camera_Projection_Type = .Perspective, loc := #caller_location) {
	assert_not_nil(camera, loc)
	assert(
		type != .Custom,
		"Cannot use camera_init for custom projection cameras. Use camera_init_custom instead.",
		loc,
	)

	camera.fov = DEFAULT_FOV
	camera.near = DEFAULT_NEAR
	camera.far = DEFAULT_FAR
	camera.zoom = 1
	camera.type = type
	camera.dirty = true

	buffer := create_buffer({.Uniform, .Host_Write}, size_of(Camera_UBO))

	camera.buffer_h = store_buffer(buffer, loc)
}

camera_get_up :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return lin.normalize_vec3(camera.up)
}

camera_get_forward :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return lin.normalize_vec3(camera.target - camera.position)
}

camera_get_right :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return lin.normalize(lin.cross(camera_get_forward(camera), camera_get_up(camera)))
}

camera_get_left :: proc(camera: ^Camera, loc := #caller_location) -> vec3 {
	assert_not_nil(camera, loc)

	return -camera_get_right(camera)
}

camera_move :: proc(camera: ^Camera, translation: vec3) {
	camera.position += translation
	camera.target += translation

	camera.dirty = true
}

camera_set_position :: proc(camera: ^Camera, position: vec3) {
	forward := camera_get_forward(camera)
	camera.position = position
	camera.target = camera.position + forward

	camera.dirty = true
}

camera_set_position_only :: proc(camera: ^Camera, position: vec3) {
	camera.position = position

	camera.dirty = true
}

camera_set_target_only :: proc(camera: ^Camera, position: vec3) {
	camera.target = position

	camera.dirty = true
}

camera_set_yaw :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	target_position := camera.target - camera.position
	trans := lin.mat4Rotate(camera_get_up(camera), angle)
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz

	camera.dirty = true
}

// Rotates the camera around its right vector
camera_set_pitch :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	target_position := camera.target - camera.position
	trans := lin.mat4Rotate(camera_get_right(camera), angle)
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz

	camera.dirty = true
}

camera_set_roll :: proc(camera: ^Camera, angle: f32, loc := #caller_location) {
	assert_not_nil(camera, loc)

	target_position := camera.target - camera.position
	trans := lin.mat4Rotate(camera_get_forward(camera), angle)
	target := trans * vec4{target_position.x, target_position.y, target_position.z, 0}
	camera.target = target.xyz

	camera.dirty = true
}

camera_set_zoom :: proc(camera: ^Camera, zoom: vec3, loc := #caller_location) {
	assert_not_nil(camera, loc)

	camera.zoom = zoom

	camera.dirty = true
}

camera_get_view :: proc(camera: ^Camera, loc := #caller_location) -> mat4 {
	assert_not_nil(camera, loc)

	return(
		lin.mat4LookAt(camera.position, camera.position + camera_get_forward(camera), camera_get_up(camera)) *
		lin.mat4Scale(camera.zoom) \
	)
}

camera_get_projection :: proc(camera: ^Camera, aspect: f32, loc := #caller_location) -> mat4 {
	assert_not_nil(camera, loc)
	projection: mat4

	switch camera.type {
	case .Perspective:
		projection = vemath.perspective(lin.radians_f32(camera.fov), aspect, camera.near, camera.far)
	case .Orthographic:
		top := camera.fov / 2.0
		right := top * aspect
		projection = vemath.ortho(-right, right, -top, top, camera.near, camera.far)
	case .Custom:
		assert(camera.custom.projection != nil)
		projection = camera.custom.projection(camera.custom.user_data, camera, aspect)
	}

	return projection
}

@(private)
_camera_get_buffer :: proc(camera: ^Camera, aspect: f32, loc := #caller_location) -> Buffer_Handle {
	assert_not_nil(camera, loc)

	if !camera.dirty && aspect == camera.last_aspect {
		return camera.buffer_h
	}

	camera.last_aspect = aspect

	view := camera_get_view(camera)
	projection := camera_get_projection(camera, aspect)

	buffer := get_buffer_h(camera.buffer_h)
	camera_ubo := Camera_UBO {
		view       = view,
		projection = projection,
		position   = camera.position,
	}
	buffer_fill(buffer, &camera_ubo, size_of(Camera_UBO))
	camera.dirty = false

	return camera.buffer_h
}

camera_update_simple_controller :: proc(
	camera: ^Camera,
	speed: f32 = 2.0,
	mouse_sens: f32 = 0.05,
	zoom_speed: f32 = 2.5,
) {
	speed := speed
	speed *= get_delta_time()

	m_delta := get_mouse_delta()
	if lin.length_vec2(m_delta) > 0.0001 {
		up := camera_get_up(camera)
		forward := camera_get_forward(camera)

		{ 	// set camera pitch
			angle: f32 = -m_delta.y * get_delta_time() * mouse_sens

			maxAngleUp := vemath.vec3_angle(up, forward)
			maxAngleUp -= 0.001
			if angle > maxAngleUp do angle = maxAngleUp

			maxAngleDown := -vemath.vec3_angle(-up, forward)
			maxAngleDown += 0.01
			if (angle < maxAngleDown) do angle = maxAngleDown

			camera_set_pitch(camera, angle)
		}

		{ 	// set camera yaw
			camera_set_yaw(camera, -m_delta.x * get_delta_time() * mouse_sens)
		}
	}

	camera_set_zoom(camera, camera.zoom + get_scroll_f32() * get_delta_time() * zoom_speed)

	camera.zoom = lin.clamp_vec3(camera.zoom, 0.01, 5)

	if is_key_down(.LeftShift) {
		speed *= 2
	}

	if is_key_down(.W) {
		camera_move(camera, camera_get_forward(camera) * speed)
	}
	if is_key_down(.S) {
		camera_move(camera, -camera_get_forward(camera) * speed)
	}
	if is_key_down(.A) {
		camera_move(camera, camera_get_left(camera) * speed)
	}
	if is_key_down(.D) {
		camera_move(camera, camera_get_right(camera) * speed)
	}
}
