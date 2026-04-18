package ve

import hm "container/handle_map"
import "core:fmt"
import "core:log"
import "core:mem"
import "lib/vma"
import vk "vendor:vulkan"

Buffer_Usage_Flags :: distinct bit_set[Buffer_Usage_Flag]
Buffer_Usage_Flag :: enum {
	// GPU
	Vertex,
	Index,
	Uniform,
	Storage,
	Transfer,
	// CPU
	Host_Read,
	Host_Write,
}

Uniform_Buffer :: distinct hm.Handle
INVALID_UNIFORM_BUFFER_HANDLE :: Uniform_Buffer{max(u32), max(u32)}
Storage_Buffer :: distinct hm.Handle
INVALID_STORAGE_BUFFER_HANDLE :: Storage_Buffer{max(u32), max(u32)}

Cached_Buffer :: struct {
	buffer: Buffer,
	dirty:  bool,
	apply:  proc(data: ^Cached_Buffer, loc := #caller_location),
	data:   rawptr,
	type:   typeid,
}

Uniform_Buffer_Data :: Cached_Buffer
Storage_Buffer_Data :: Cached_Buffer

@(require_results)
create_buffer :: proc(
	usage: Buffer_Usage_Flags,
	size: Device_Size,
	data: rawptr = nil,
	loc := #caller_location,
) -> Buffer {
	data := _create_buffer(usage, size, data, loc)
	return _store_buffer(data)
}

destroy_buffer :: proc(b: Buffer, loc := #caller_location) {
	b_data := _acquire_buffer_h(b)
	_deffered_destructor_add(b_data)
}

buffer_fill :: proc(b: Buffer, data: rawptr, size: Device_Size, offset: Device_Size = 0, loc := #caller_location) {
	b_data := _get_buffer_h(b)
	_buffer_fill(b_data, data, size, offset, loc)
}

buffer_read :: proc(b: Buffer, loc := #caller_location) -> (data: rawptr, size: Device_Size) {
	b_data := _get_buffer_h(b)
	return _buffer_read(b_data, loc)
}

// used for generated uniform and storage object structs

ubo_get_buffer :: proc(h: Uniform_Buffer) -> Buffer {
	b := get_uniform_buffer(h)
	return b.buffer
}

store_uniform_buffer :: proc(ubo: Uniform_Buffer_Data) -> Uniform_Buffer {
	return hm.insert(&ctx.gfx.buffer_manager.uniform_buffers, ubo)
}

get_uniform_buffer :: proc(handle: Uniform_Buffer, loc := #caller_location) -> ^Uniform_Buffer_Data {
	b, ok := hm.get(&ctx.gfx.buffer_manager.uniform_buffers, handle)
	assert(ok, "Invalid uniform buffer handle", loc)
	return b
}

has_uniform_buffer :: proc(handle: Uniform_Buffer) -> bool {
	return hm.has_handle(&ctx.gfx.buffer_manager.uniform_buffers, handle)
}

destroy_uniform_buffer :: proc(handle: Uniform_Buffer) -> bool {
	uniform_buffer, ok := hm.remove(&ctx.gfx.buffer_manager.uniform_buffers, handle)
	if !ok do return false
	b := _acquire_buffer_h(uniform_buffer.buffer)
	_destroy_buffer(&b)
	return true
}

sbo_get_buffer :: proc(h: Storage_Buffer) -> Buffer {
	b := get_storage_buffer(h)
	return b.buffer
}

store_storage_buffer :: proc(sbo: Storage_Buffer_Data) -> Storage_Buffer {
	return hm.insert(&ctx.gfx.buffer_manager.storage_buffers, sbo)
}

has_storage_buffer :: proc(handle: Storage_Buffer) -> bool {
	return hm.has_handle(&ctx.gfx.buffer_manager.storage_buffers, handle)
}

get_storage_buffer :: proc(handle: Storage_Buffer, loc := #caller_location) -> ^Storage_Buffer_Data {
	b, ok := hm.get(&ctx.gfx.buffer_manager.storage_buffers, handle)
	assert(ok, "Invalid uniform buffer handle", loc)
	return b
}

destroy_storage_buffer :: proc(handle: Storage_Buffer) -> bool {
	storage_buffer, ok := hm.remove(&ctx.gfx.buffer_manager.storage_buffers, handle)
	if !ok do return false
	b := _acquire_buffer_h(storage_buffer.buffer)
	_destroy_buffer(&b)
	return true
}
