#version 450

#include "buildin:bindless.h"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;

// instance
layout(location = 4) in vec3 inInstancePos;
layout(location = 5) in vec3 inInstanceColor;
layout(location = 6) in float inInstanceScale;

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec3 fragPos;
layout(location = 3) out vec3 fragColor;


void main() {
	gl_Position = getCamera().projection * getCamera().view * getModel() * (vec4(inInstancePos + inInstanceScale * inPosition, 1.0));

	fragTexCoord = inTexCoord;
	fragNormal = mat3(transpose(inverse(getModel()))) * inNormal;
	fragPos = vec3(getModel() * vec4(inPosition, 1.0f));
	fragColor = inInstanceColor;
}
