#version 450

#include "gen_types.h"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec4 inColor;

// instance
layout(location = 4) in vec3 inInstancePos;
layout(location = 5) in vec3 inInstanceColor;
layout(location = 6) in float inInstanceScale;

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec4 fragColor;
layout(location = 2) out vec3 fragNormal;
layout(location = 3) out vec3 fragPos;
layout(location = 4) out vec3 fragColorIn;


void main() {
	gl_Position = getCamera().projection * getCamera().view * getModel() * (vec4(inInstancePos + inInstanceScale * inPosition, 1.0));

	fragTexCoord = inTexCoord;
	fragColor = inColor;
	fragNormal = mat3(transpose(inverse(getModel()))) * inNormal;
	fragPos = vec3(getModel() * vec4(inPosition, 1.0f));
	fragColorIn = inInstanceColor;
}
