#version 450

#include "./examples/assets/shaders/gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
	float a = texture(gTextures2D[getTextUBO(H0()).glyph], fragTexCoord).r;
	outColor = vec4(getTextUBO(H0()).color, a);
}
