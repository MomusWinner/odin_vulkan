package ve

texture_is_valid :: proc(handle: Texture) -> bool {
	return _has_texture_h(handle)
}

buffer_is_valid :: proc(handle: Buffer) -> bool {
	return _has_buffer_h(handle)
}
