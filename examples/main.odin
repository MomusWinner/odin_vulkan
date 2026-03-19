package main

import ve ".."
import "core:fmt"
import "core:log"
import "core:mem"
import "core:time"

current_scene: Scene

TARGET_FPS :: 120

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf(
					"=== %v allocations not freed: ===\n",
					len(track.allocation_map),
				);for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	ve.init(
		{
			gfx = {swapchain_sample_count = ._4, attachments = {.Depth, .Stencil}},
			window = {width = 800, height = 400, title = "Examples"},
		},
	)

	current_scene = create_model_scene()
	// current_scene = create_postprocessing_scene()
	// current_scene = create_light_scene()
	// current_scene = create_skybox_scene()
	// current_scene = create_outline_scene()
	// current_scene = create_hdr_scene()
	// current_scene = create_instancing_scene()
	// current_scene = create_compute_scene()
	// current_scene = create_text_scene()
	// current_scene = create_empty_scene()

	current_scene.init(&current_scene)

	prev: time.Time
	for !ve.should_close() {
		if (ve.is_key_pressed(.Escape)) {
			break
		}

		if (ve.is_key_pressed(.R)) {
			ve.hot_reload_shaders()
		}

		current_scene.update(&current_scene)
		current_scene.draw(&current_scene)

		target_delta_time: f64 = (1.0 / TARGET_FPS) * f64(time.Second)
		target_delta_duration := time.Duration(target_delta_time)
		frame_duration := time.diff(prev, time.now())
		if frame_duration < target_delta_duration {
			time.accurate_sleep(target_delta_duration - frame_duration)
		}
		prev = time.now()
	}

	ve.wait_render_completion()
	current_scene.destroy(&current_scene)

	ve.close()

	log.info("Successfuly close")
}
