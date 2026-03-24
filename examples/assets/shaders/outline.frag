#version 450

#include "./examples/assets/shaders/gen_types.h"

layout(location = 0) out vec4 outColor;

void main() {
	outColor = getOutlineUBO(H0()).color;
}
