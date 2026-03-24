#version 450

#include "./examples/assets/shaders/gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
	vec3 hdrColor = texture(gTextures2D[getHDRUBO(H0()).scene], fragTexCoord).rgb;
	vec3 bloomColor = texture(gTextures2D[getHDRUBO(H0()).bloom], fragTexCoord).rgb;
	hdrColor += bloomColor;

	// exposure tone mapping
	vec3 mapped = vec3(1.0) - exp(-hdrColor * getHDRUBO(H0()).exposure);

	outColor = vec4(mapped, 1);
}
