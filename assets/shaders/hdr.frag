#version 450

#include "gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

void main() {
	vec3 hdrColor = texture(uGlobalTextures2D[getMtrlHDR().scene], fragTexCoord).rgb;
	vec3 bloomColor = texture(uGlobalTextures2D[getMtrlHDR().bloom], fragTexCoord).rgb;
	hdrColor += bloomColor;

	// exposure tone mapping
	vec3 mapped = vec3(1.0) - exp(-hdrColor * getMtrlHDR().exposure);

	outColor = vec4(mapped, 1);
}
