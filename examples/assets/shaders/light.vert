#version 450

#include "./examples/assets/shaders/gen_types.h"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;

layout(location = 0) out vec2 fragTexCoord;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec3 fragPos;
layout(location = 3) out vec4 fragPosLightSpace;


const mat4 biasMat = mat4( 
	0.5, 0.0, 0.0, 0.0,
	0.0, 0.5, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.5, 0.5, 0.0, 1.0 );


#define getLightData() getLightDataUBO(H1())

void main() {
	gl_Position = getCamera().projection * getCamera().view * getModel() * vec4(inPosition, 1.0);

	fragTexCoord = inTexCoord;
	fragNormal = mat3(transpose(inverse(getModel()))) * inNormal;
  fragPos = vec3(getModel() * vec4(inPosition, 1.0f));

	mat4 projection = getCameraByHandle(getLightData().camera).projection;
	mat4 view = getCameraByHandle(getLightData().camera).view;
	fragPosLightSpace = (biasMat * projection * view * getModel()) * vec4(inPosition, 1.0f);
}
