package ve

import hm "container/handle_map"
import sm "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

texture_is_valid :: proc(handle: Texture) -> bool {
	return _has_texture_h(handle)
}

buffer_is_valid :: proc(handle: Buffer) -> bool {
	return _has_buffer_h(handle)
}



