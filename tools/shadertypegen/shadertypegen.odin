package shadertypegen

import "core:flags"
import "core:fmt"
import "core:log"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:strings"

MATERIAL_ATTRIBUTE :: "material"
UNIFORM_BUFFER_ATTRIBUTE :: "uniform_buffer"

STRUCT_RULES :: `
/// RULES /////////////////////////////////////////////////////////////////////
1. Only the following simple types are allowed:
   i32, f32, b32, math.vec2, math.vec3, math.vec4,
   math.mat3, math.mat4, ve.Texture_Handle, ve.Buffer_Handle.

Example:
--
Rule_1 :: struct {
  a: i32,
  b: f32,
  c: vec3,
  ...
}
--

2. The user's types should consist of the types described in rule 1.

Example:
--
Custom :: struct {
  a: vec4,
  b: mat4,
  ..
}

Rule_2 :: struct {
  a: i32,
  b: Custom,
}
--

3. Arrays must have a predefined size, and the element type must match:
   math.vec4, math.mat4, or a custom structure that conforms to rule 2.

Example
--
Custom :: struct {
  a: vec4,
  b: i32,
}

Rule_3 :: struct {
  values:        [5]vec4,
  custom_values: [3]Custom
}
--
////////////////////////////////////////////////////////////////////////////////
`


main :: proc() {
	context.logger = log.create_console_logger(lowest = .Info, opt = {.Terminal_Color})

	Options :: struct {
		src_dir:          string `args:"required" usage:"Package directory containing original material types @(material)."`,
		outpute_glsl_dir: string `args:"required" usage:"Shaders directory."`,
		ve_import:        string `usage:"Path to ve package. (libs/ve, <empty>)"`,
		rules:            bool `usage:"See rules."`,
	}

	opt: Options
	style: flags.Parsing_Style = .Odin

	flags.parse_or_exit(&opt, os.args, style)

	if opt.rules == true {
		log.error(STRUCT_RULES)
		return
	}

	gfx_pkg_info := parse_package_info(opt.ve_import)

	generate_shader_types(
		filepath.clean(opt.src_dir, context.temp_allocator),
		filepath.join({opt.outpute_glsl_dir, "gen_types.h"}, context.temp_allocator),
		filepath.join({opt.src_dir, "gen_materials.odin"}, context.temp_allocator),
		gfx_pkg_info,
	)
}

// All allocations are performed in temp_allocator
generate_shader_types :: proc(
	src_path: string,
	outpute_glsl_path: string,
	outpute_odin_path: string,
	gfx_package: Ve_Package_Info,
	loc := #caller_location,
) -> bool {
	if !os.is_dir_path(src_path) {
		log.errorf("Unable to find directory src-path: \"%s\"", src_path)
	}

	if !os.is_dir_path(filepath.dir(outpute_glsl_path, context.temp_allocator)) {
		log.errorf("Unable to find outpute-glsl dir: \"%s\"", outpute_glsl_path)
	}

	if !os.is_dir_path(filepath.dir(outpute_odin_path, context.temp_allocator)) {
		log.errorf("Unable to find outpute-odin dir: \"%s\"", outpute_odin_path)
	}

	c := context
	context.allocator = context.temp_allocator

	pkg, ok_p := parser.parse_package_from_path(src_path)
	if !ok_p {
		log.errorf("Failed to parse package by path %", src_path)
		return false
	}

	d, ok := parse_structures(pkg, loc)
	if !ok do return ok

	ok = generate_odin(d, outpute_odin_path, pkg.name, gfx_package)
	ok = generate_glsl(d, outpute_glsl_path, pkg.name, loc)

	return true
}
