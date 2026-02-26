package ve

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"

read_file :: proc(name: string, allocator := context.allocator) -> ([]byte, bool) {
	data, ok := os.read_entire_file(name, allocator)
	return data, ok
}

wirte_file :: proc(name: string, data: []byte) -> bool {
	return os.write_entire_file(name, data)
}

assert_not_nil :: #force_inline proc(obj: ^$T, loc := #caller_location) {
	assert(obj != nil, fmt.tprintf("%T is nil", obj), loc = loc)
}

merge :: proc(a: []$T, b: []T, allocator := context.allocator, loc := #caller_location) -> []T {
	result := make([]T, len(a) + len(b), allocator)
	copy(result, a)
	copy(result[len(a):], b)
	return result
}

@(private)
assert_gfx_ctx :: #force_inline proc(loc := #caller_location) {
	assert(
		ctx.gfx.initialized == true,
		"Graphics not initialized. Call 'graphics.init()' before using any graphics functions.",
		loc = loc,
	)
}

@(private)
must :: proc(result: vk.Result, msg: string = "", loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %s (%v)", msg, result, location = loc)
	}
}

@(private)
assert_frame_data :: #force_inline proc(frame_data: Frame_Data, loc := #caller_location) {
	assert(frame_data.surface_info.type != .None, "Frame data has uninitialized surface information.", loc = loc)
}

@(private)
_set_debug_object_name :: #force_inline proc(handle: u64, type: vk.ObjectType, name: string) {
	when ENABLE_VALIDATION_LAYERS {
		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectType   = type,
			objectHandle = handle,
			pObjectName  = strings.clone_to_cstring(name, context.temp_allocator),
		}
		vk.SetDebugUtilsObjectNameEXT(ctx.gfx.vk_state.device, &name_info)
	}
}
