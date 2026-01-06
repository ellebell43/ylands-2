extends MeshInstance3D
class_name VoxelTerrainChunk

# Compute shader variables
var rd = RenderingServer.create_local_rendering_device()
var pipeline : RID
var shader : RID
var buffers: Array
var uniform_set : RID
const uniform_set_index : int = 0

var output
var total_time : float = 0.0
var VERBOSE : bool

var DATA : Texture3D
var CHUNK_POSITION : Vector3i
var CHUNK_SIZE : Vector3i
var TERRAIN_SIZE : Vector3i
var ISO : float
var FLAT_SHADED : bool

func _init(chunk_position: Vector3i, chunk_size: Vector3i, terrain_size: Vector3i, iso: float, flat_shaded: bool, data: Texture3D, verbose: bool) -> void:
	self.CHUNK_POSITION = chunk_position
	self.CHUNK_SIZE = chunk_size
	self.TERRAIN_SIZE = terrain_size
	self.ISO = iso
	self.FLAT_SHADED = flat_shaded
	self.DATA = data
	self.VERBOSE = verbose

# Called when the node enters the scene tree for the first time.
func _ready():
	if (VERBOSE) : 
		print("===========================================")
		print("creating chunk at " + str(CHUNK_POSITION))
	init_compute() # initialize compute shader file and pipelin
	setup_bindings() # setup buffers and bindings
	compute() # update buffers and compute the mesh
	position = CHUNK_POSITION * CHUNK_SIZE # place chunk in the correct spot
	if (VERBOSE) : print("chunk at " + str(CHUNK_POSITION) + " ready in: " + str(total_time) + "s")

func init_compute():
	var time = Time.get_ticks_msec()

	# Create shader and pipeline
	var shader_file = load("res://shaders/marching_cubes.glsl")
	var shader_spirv = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed

func release():
	for b in buffers:
		rd.free_rid(b)
	buffers.clear()
	
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()

func get_params():
	var voxel_grid := MarchingCubes.VoxelGrid.new(CHUNK_SIZE, CHUNK_POSITION, TERRAIN_SIZE)
	voxel_grid.set_data(DATA)
	
	var params = PackedFloat32Array()
	params.append(CHUNK_SIZE.x)
	params.append(CHUNK_SIZE.y)
	params.append(CHUNK_SIZE.z)
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
	var total_cells = CHUNK_SIZE.x * CHUNK_SIZE.y * CHUNK_SIZE.z
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


func compute():
	var time = Time.get_ticks_msec()
	# Update input buffers and clear output ones
	# This one is actually not always needed. Comment to see major speed optimization
	var time_send: int = Time.get_ticks_usec()
	var input = get_params()
	var input_bytes = input.to_byte_array()
	rd.buffer_update(buffers[0], 0, input_bytes.size(), input_bytes)

	var total_cells = CHUNK_SIZE.x * CHUNK_SIZE.y * CHUNK_SIZE.z
	var vertices = PackedColorArray()
	vertices.resize(total_cells * 5 * (3 + 1)) # 5 triangles max per cell, 3 vertices and 1 normal per triangle
	var vertices_bytes = vertices.to_byte_array()

	var counter_bytes = PackedFloat32Array([0]).to_byte_array()
	rd.buffer_update(buffers[1], 0, counter_bytes.size(), counter_bytes)

	# Dispatch compute and uniforms
	time_send = Time.get_ticks_usec()
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, uniform_set_index)
	rd.compute_list_dispatch(compute_list, CHUNK_SIZE.x / 8, CHUNK_SIZE.y / 8, CHUNK_SIZE.z / 8)
	rd.compute_list_end()

	# Submit to GPU and wait for sync
	time_send = Time.get_ticks_usec()
	rd.submit()
	rd.sync()

	# Read back the data from the buffer
	time_send = Time.get_ticks_usec()
	var total_triangles = rd.buffer_get_data(buffers[1]).to_int32_array()[0]
	var output_array := rd.buffer_get_data(buffers[2]).to_float32_array()

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

	print("total vertices at " + str(CHUNK_POSITION) + " : ", output["vertices"].size())
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed

	create_mesh()

func create_mesh():
	var time = Time.get_ticks_msec()
	
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
	release()
	
	var elapsed = (Time.get_ticks_msec()-time)/1000.0
	total_time += elapsed
