# ve 
A small Vulkan Rendering Engine. 

> [!WARNING]
> **`ve` is currently under active development** and is not recommended for production use. The API may change significantly between versions.

#### Platforms
 - Linux
 - Windows

#### Requirements
 - Odin version [`2026-03`](https://odin-lang.org/docs/install/)
 - libstdc++

#### Dependencies
 - [glfw](https://github.com/glfw/glfw)
 - [vma](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator)
 - [shaderc](https://github.com/google/shaderc)
 - [stb](https://github.com/nothings/stb)

## Installetion

```bash
# Clone the repository
git clone https://github.com/MomusWinner/ve.git
cd ve

# For Linux
./examples.sh gen
./examples.sh run

# For Windows
examples.bat gen
examples.bat run
```

##  Key Features

The key features of ve are `shader hot reloading`, `bindless rendering`, and `gpu buffer code generation`.

### Shader Hot Reloading
Supports real-time shader recompilation while the engine is running. This feature can be disabled using -define:ENABLE_SHADER_COMPILATION=false.
By default, it is enabled only in debug builds.
```odin
if (ve.key_is_pressed(.R)) {
    ve.shaders_hot_reload()
}
```

> [!NOTE]
> Shader hot reloading is intended for use only in development.

### Buffer Types Generation
Automatic buffer type generation system from Odin structures. A key advantage of this approach is type-safe buffer interfaces.
The generator also handles `std140` and `std430` memory alignment layouts by automatically adding necessary padding.

Example:
```odin
package main

import "ve"

@(buffer) // defaults to std140
My_UBO :: struct {
	color:   ve.vec4,
	texture: ve.Texture,
	ubo:     ve.Buffer,
}

@(buffer = "storage") // defaults to std430
My_SBO :: struct {
    ...
}

@(buffer = "storage,std140")
My_Second_SBO :: struct {
    ...
}
```

After defining your buffer struct, run:
```bash
odin run ./tools/shadertypegen/ -- \
    -output-glsl-dir:path_to_your_shaders \
    -src-dir:path_to_your_project \
    -ve-import:"ve .."
```
This generates two files:
1. An Odin source file in your project package.
2. A shader header file at `path_to_your_shaders/gen_types.h`.

The generated Odin source file provides type-safe getter and setter procedures for each field of your struct:
```odin
ubo: ve.Uniform_Buffer = create_ubo_my()

ubo_my_set_color(ubo, vec3{1, 0, 0})
ubo_my_set_texture(ubo, texture)
ubo_my_set_ubo(ubo, other_ubo)

ubo_buffer: ve.Buffer = ve.ubo_get_buffer(ubo)

ve.destroy_uniform_buffer(ubo)
```

### Bindless Rendering
Leverages modern GPU bindless descriptors to eliminate explicit texture and buffer bind calls, improving performance and simplifying resource management.
Bindless rendering allows access to buffers and textures by index in an array. For example: gTextures[your_index].

## CPU to GPU Data Transfer
Ve supports transferring `textures`, `uniform buffers`, and `storage buffers`.
Uniform and storage buffers can be created in two ways: manually or by type generation ([described below](#buffer-types-generation)).

In a draw operation, you can pass a mesh, pipeline, transformation matrix, and a list of handles from 0 to 9 (h0, h1, h2...).
But what is h0? Because ve uses a bindless rendering approach, it's very useful to pass some indices to the shader.

For example, we can pass any type of resource (`ve.Buffer`, `ve.Texture`, `ve.Unifrom_Buffer`, `ve.Storage_Buffer`) to h0, h1, etc., and later access it in a GLSL shader.
> [!NOTE]
> `ve.Unifrom_Buffer` and `ve.Storage_Buffer` are wrappers around ve.Buffer. They are needed for type generation.
```odin
ve.draw_mesh(d.mesh, d.pipeline, ve.trf_get_matrix(d.trf), {h0 = buffer, h1 = ubo, h2 = texture})
```

> [!NOTE]
> `#include "buildin:bindless.h"` is needed for bindless rendering.

```glsl
#include "buildin:bindless.h"
#include "your_path/gen_types.h"

RegisterUniform(MyBuffer1, { // manual uniform buffer registration
	vec3 color;
});

layout(location = 0) in vec2 fragTexCoord;

int main() {
    vec3 color =  texture(gTextures2D[H2()], fragTexCoord).rgb;

    MyBuffer1 b1 = GetResource(MyBuffer1, H0()); // manual
    MyBuffer2 b2 = getMyBufferUBO(H1()); // same thing, but auto-generated
    ...
}
```

## Examples
The `./examples` folder contains various examples demonstrating how to use ve correctly.

#### Postprocessing
<img width="1920" height="1080" alt="screenshot_20260425_104335" src="https://github.com/user-attachments/assets/33f690c5-f6d3-462c-abf4-f4a8bc71acb1" />

#### Text
<img width="1920" height="1080" alt="screenshot_20260425_104659" src="https://github.com/user-attachments/assets/6c157d34-aa46-4585-9925-5b144a3c55f4" />

#### Light
Example of simple lighting with ambient, diffuse components.
<img width="1920" height="1080" alt="screenshot_20260425_104203" src="https://github.com/user-attachments/assets/dd76c602-9e56-4d6f-b21a-707aa0a5d464" />

#### HDR + Bloom
<img width="1920" height="1080" alt="screenshot_20260425_104818" src="https://github.com/user-attachments/assets/59486fa5-84a9-43d8-aad3-124bc2570e7d" />

#### Instancing
<img width="1920" height="1080" alt="screenshot_20260425_104923" src="https://github.com/user-attachments/assets/b295f799-42d4-4ae0-91e4-a30bbd84219c" />

#### Compute
<img width="1920" height="1080" alt="screenshot_20260425_105214" src="https://github.com/user-attachments/assets/d1b4af08-33b4-4692-bcdd-47c88f44b89a" />

#### Skybox
<img width="1920" height="1080" alt="screenshot_20260425_105421" src="https://github.com/user-attachments/assets/aa3640a4-7043-493f-b383-30b4c1335ac3" />

#### Outline
<img width="1920" height="1080" alt="screenshot_20260425_105556" src="https://github.com/user-attachments/assets/17a18dd3-fce1-4923-8aa5-03b6ee866d09" />
