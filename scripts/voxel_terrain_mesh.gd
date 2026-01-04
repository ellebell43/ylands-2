@tool
extends MeshInstance3D


var rd = RenderingServer.create_local_rendering_device()
var pipeline : RID
var shader : RID
var buffers: Array
var uniform_set : RID
const uniform_set_index : int = 0

var output
var total_time : float = 0.0

var data : Texture3D
@export var SIZE : Vector3i = Vector3i(128, 128, 128)
## defines what value represent whether a vertex is inside or outside of the mesh. Interpolated from noise luminance with an inclusive range from 0.0 to 1.0
@export var ISO:float = 0.75
@export var FLAT_SHADED:bool = false

@export var GENERATE: bool:
	set(value):
		var time = Time.get_ticks_msec()
		compute()
		var elapsed = (Time.get_ticks_msec()-time)/1000.0
		print("===============================================")
		print("Terrain generated in: " + str(elapsed) + "s")
		print("===============================================")

# Called when the node enters the scene tree for the first time.
func _ready():
	data = _create_data(SIZE)
	init_compute()
	setup_bindings()
	#compute()
	print("ready in: " + str(total_time) + "s")
	
## Generates a noise volume at a specfied size, then returns that nose as a Texture3D object
func _create_data(size: Vector3i) -> Texture3D:
	var time = Time.get_ticks_msec()
	# create and configure noise
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# create image array from 3d noise volume
	# invert=false, normalize=true
	var img_array : Array[Image] = noise.get_image_3d(size.x, size.y, size.z, false, true)
	
	# create texture3d from 3d image
	# use_mipmaps=false
	var tex3d = ImageTexture3D.new()
	tex3d.create(img_array[0].get_format(), size.x, size.y, size.z, false, img_array)
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed
	print("noise texture generated in: " + str(elapsed) + "s")
	
	return tex3d

func _notification(type):
	if type == NOTIFICATION_PREDELETE:
		release()

func init_compute():
	var time = Time.get_ticks_msec()

	# Create shader and pipeline
	var shader_file = load("res://shaders/marching_cubes.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed
	print("shader initialized in: " + str(elapsed) + "s")

func release():
	for b in buffers:
		rd.free_rid(b)
	buffers.clear()
	
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()

func get_params():
	var voxel_grid_size := Vector3(data.get_width(), data.get_height(), data.get_width())
	var voxel_grid := MarchingCubes.VoxelGrid.new(voxel_grid_size)
	voxel_grid.set_data(data)
	
	var params = PackedFloat32Array()
	params.append(voxel_grid_size.x)
	params.append(voxel_grid_size.y)
	params.append(voxel_grid_size.z)
	params.append(ISO)
	params.append(int(FLAT_SHADED))
	
	params.append_array(voxel_grid.data)
	
	return params

func setup_bindings():
	var time = Time.get_ticks_msec()
	
	# Create the input params buffer
	var input = get_params()
	var input_bytes = input.to_byte_array()
	buffers.push_back(rd.storage_buffer_create(input_bytes.size(), input_bytes))
	
	var input_params_uniform := RDUniform.new()
	input_params_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	input_params_uniform.binding = 0
	input_params_uniform.add_id(buffers[0])
	
	# Create counter buffer
	var counter_bytes = PackedFloat32Array([0]).to_byte_array()
	buffers.push_back(rd.storage_buffer_create(counter_bytes.size(), counter_bytes))
	
	var counter_uniform = RDUniform.new()
	counter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	counter_uniform.binding = 1
	counter_uniform.add_id(buffers[1])
	
	# Create the triangles buffer
	var total_cells = data.get_width() * data.get_height() * data.get_depth()
	var vertices = PackedColorArray()
	vertices.resize(total_cells * 5 * (3 + 1)) # 5 triangles max per cell, 3 vertices and 1 normal per triangle
	var vertices_bytes = vertices.to_byte_array()
	buffers.push_back(rd.storage_buffer_create(vertices_bytes.size(), vertices_bytes))
	
	var vertices_uniform := RDUniform.new()
	vertices_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	vertices_uniform.binding = 2
	vertices_uniform.add_id(buffers[2])
#
	# Create the LUT buffer
	var lut_array = PackedInt32Array()
	for i in range(MarchingCubes.LUT.size()):
		lut_array.append_array(MarchingCubes.LUT[i])
	var lut_array_bytes = lut_array.to_byte_array()
	buffers.push_back(rd.storage_buffer_create(lut_array_bytes.size(), lut_array_bytes))

	var lut_uniform := RDUniform.new()
	lut_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	lut_uniform.binding = 3
	lut_uniform.add_id(buffers[3])
#
	uniform_set = rd.uniform_set_create([
		input_params_uniform,
		counter_uniform,
		vertices_uniform,
		lut_uniform,
	], shader, uniform_set_index)
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed
	print("bindings set in: " + str(elapsed) + "s")


func compute():
	print("===============Begin Compute===================")
	var time = Time.get_ticks_msec()
	# Update input buffers and clear output ones
	# This one is actually not always needed. Comment to see major speed optimization
	var time_send: int = Time.get_ticks_usec()
	var input = get_params()
	var input_bytes = input.to_byte_array()
	rd.buffer_update(buffers[0], 0, input_bytes.size(), input_bytes)

	var total_cells = data.get_width() * data.get_height() * data.get_depth()
	var vertices = PackedColorArray()
	vertices.resize(total_cells * 5 * (3 + 1)) # 5 triangles max per cell, 3 vertices and 1 normal per triangle
	var vertices_bytes = vertices.to_byte_array()

	var counter_bytes = PackedFloat32Array([0]).to_byte_array()
	rd.buffer_update(buffers[1], 0, counter_bytes.size(), counter_bytes)
	print("buffer updated in: " + Utils.parse_time(Time.get_ticks_usec() - time_send))

	# Dispatch compute and uniforms
	time_send = Time.get_ticks_usec()
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, uniform_set_index)
	rd.compute_list_dispatch(compute_list, data.get_width() / 8, data.get_height() / 8, data.get_depth() / 8)
	rd.compute_list_end()
	print("uniforms dispatched in: " + Utils.parse_time(Time.get_ticks_usec() - time_send))

	# Submit to GPU and wait for sync
	time_send = Time.get_ticks_usec()
	rd.submit()
	rd.sync()
	print("submitted and synced in: " + Utils.parse_time(Time.get_ticks_usec() - time_send))

	# Read back the data from the buffer
	time_send = Time.get_ticks_usec()
	var total_triangles = rd.buffer_get_data(buffers[1]).to_int32_array()[0]
	var output_array := rd.buffer_get_data(buffers[2]).to_float32_array()
	print("read back buffer in: " + Utils.parse_time(Time.get_ticks_usec() - time_send))

	time_send = Time.get_ticks_usec()
	output = {
		"vertices": PackedVector3Array(),
		"normals": PackedVector3Array(),
	}

	for i in range(0, total_triangles * 16, 16): # Each triangle spans for 16 floats
		output["vertices"].push_back(Vector3(output_array[i+0], output_array[i+1], output_array[i+2]))
		output["vertices"].push_back(Vector3(output_array[i+4], output_array[i+5], output_array[i+6]))
		output["vertices"].push_back(Vector3(output_array[i+8], output_array[i+9], output_array[i+10]))

		var normal = Vector3(output_array[i+12], output_array[i+13], output_array[i+14])
		# Each vector will point to the same normal
		for j in range(3):
			output["normals"].push_back(normal)

	print("iterated vertices in: " + Utils.parse_time(Time.get_ticks_usec() - time_send))
	print("total vertices: ", output["vertices"].size())
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed
	print("mesh computed in: " + str(elapsed) + "s")
	print("===============================================")

	create_mesh()

func create_mesh():
	var time = Time.get_ticks_msec()
	print("creating mesh...")
	
	var mesh_data = []
	mesh_data.resize(Mesh.ARRAY_MAX)
	mesh_data[Mesh.ARRAY_VERTEX] = output["vertices"]
	mesh_data[Mesh.ARRAY_NORMAL] = output["normals"]

	var array_mesh = ArrayMesh.new()
	array_mesh.clear_surfaces()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.DARK_KHAKI
	array_mesh.surface_set_material(0, mat)
	
	call_deferred("set_mesh", array_mesh)
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed
	print("mesh created in: " + str(elapsed) + "s")
	
	#var surface_tool = SurfaceTool.new()
	#surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
#
	#if FLAT_SHADED:
		#surface_tool.set_smooth_group(-1)
	#
	#print("adding vertices to mesh...")
	#
	#for vert in output["vertices"]:
		#surface_tool.add_vertex(vert)
		#surface_tool.set_color(Color.BISQUE)
	#
	#var elapsed = (Time.get_ticks_msec()-time)/1000.0
	#total_time += elapsed
	#print("vertices added to mesh in: " + str(elapsed) + "s")
#
	#surface_tool.generate_normals()
	#surface_tool.index()
	#
	#var mat = StandardMaterial3D.new()
	#mat.vertex_color_use_as_albedo = true
	#surface_tool.set_material(mat)
	#
	#mesh = surface_tool.commit()
