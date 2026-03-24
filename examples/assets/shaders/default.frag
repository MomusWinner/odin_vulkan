#version 450

#include "./examples/assets/shaders/gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
	if (!isHandleValid(getBaseUBO(H0()).texture) ) {
		outColor = getBaseUBO(H0()).color;
	}
	else {
		outColor = texture(gTextures2D[getBaseUBO(H0()).texture], fragTexCoord);
	}
}
