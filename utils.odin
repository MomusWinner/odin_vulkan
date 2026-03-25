package ve

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import vk "vendor:vulkan"

read_file :: proc(name: string, allocator := context.allocator) -> ([]byte, bool) {
	data, err := os.read_entire_file(name, allocator)
	return data, err == nil
}

wirte_file :: proc(name: string, data: []byte) -> bool {
	return os.write_entire_file(name, data) == nil
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
must :: proc(result: vk.Result, msg: string = "", loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure: %s (%v)", msg, result, location = loc)
	}
}

@(private)
_location_to_string :: proc(loc: runtime.Source_Code_Location, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%s(%d:%d)", loc.file_path, loc.line, loc.column, allocator = allocator)
}

@(private)
_vk_set_debug_object_name :: #force_inline proc(handle: $T, type: vk.ObjectType, name: string) {
	when ENABLE_VALIDATION_LAYERS {
		name_info := vk.DebugUtilsObjectNameInfoEXT {
			sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
			objectType   = type,
			// TODO: add intrinsics
			objectHandle = cast(u64)handle,
			pObjectName  = strings.clone_to_cstring(name, context.temp_allocator),
		}
		vk.SetDebugUtilsObjectNameEXT(ctx.gfx.vk_state.device, &name_info)
	}
}
