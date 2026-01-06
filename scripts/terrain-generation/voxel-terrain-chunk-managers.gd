#@tool
extends MeshInstance3D
class_name VoxelTerrainChunkManager

## Reference to player object. Used to determine loaded chunks
@export var PLAYER : CharacterBody3D
## Total size of the area. Should be a multiple of CHUNK_SIZE
@export var SIZE : Vector3i = Vector3i(1280, 128, 1280) # 1280 * 128 * 1280 takes about 2s to generate noise texture
## The volume a single chunk is.
@export var CHUNK_SIZE : Vector3i = Vector3i(32, 32, 32)
@export var RENDER_DISTANCE : int = 5
## defines what value represent whether a vertex is inside or outside of the mesh. Interpolated from noise luminance with an inclusive range from -1.0 to 1.0
@export var ISO : float = 0.1
@export var FLAT_SHADED : bool = false
@export var VERBOSE : bool = false

var data : NoiseTexture3D
var rendered_chunks : = {}
var mesh_update_needed : bool = true

var total_time : float = 0.1

# Called when the node enters the scene tree for the first time.
func _ready():
	create_data() # create noise data to generate terrain from
	if (VERBOSE):
		print("===============================================")
		print("chunk manager ready in: " + str(total_time) + "s")
		print("===============================================")


func _process(_delta: float) -> void:
	# calculate player chunk position
	var player_chunk_position : Vector3i = Vector3i(int(PLAYER.global_position.x / CHUNK_SIZE.x),int(PLAYER.global_position.y / CHUNK_SIZE.y),int(PLAYER.global_position.z / CHUNK_SIZE.z))
	# Iterate through chunks within range, and load chunks that haven't been loaded yet if it's in the range of the total SIZE
	for x in range(player_chunk_position.x - RENDER_DISTANCE, player_chunk_position.x + RENDER_DISTANCE):
		for y in range(player_chunk_position.y - RENDER_DISTANCE, player_chunk_position.y + RENDER_DISTANCE):
			for z in range(player_chunk_position.z - RENDER_DISTANCE, player_chunk_position.z + RENDER_DISTANCE):
				# determine chunk position and position relative to the player
				var chunk_position : Vector3i = Vector3i(x, y, z)
				var relative_chunk_position = abs(chunk_position - player_chunk_position)
				
				# determine if the chunk is out of range
				var is_out_of_range = false
				if (relative_chunk_position.x > RENDER_DISTANCE or chunk_position.x < 0 or chunk_position.x > SIZE.x / CHUNK_SIZE.x) : is_out_of_range = true
				if (relative_chunk_position.y > RENDER_DISTANCE or chunk_position.y < 0 or chunk_position.y > SIZE.y / CHUNK_SIZE.y) : is_out_of_range = true
				if (relative_chunk_position.z > RENDER_DISTANCE or chunk_position.z < 0 or chunk_position.z > SIZE.z / CHUNK_SIZE.z) : is_out_of_range = true
				
				# if not rendered and in range, load the chunk.
				if not rendered_chunks.has(str(chunk_position)) and not is_out_of_range : load_chunk(chunk_position)
	
	# Iterate through rendered chunks and confirm all are in range, otherwise, unload
	for key in rendered_chunks:
		var new_string : String = key.erase(0,1) # remove opening parenthesis from string
		new_string = new_string.erase(new_string.length() - 1, 1) # remove closing parenthesis
		var coords : PackedStringArray = new_string.split(", ") # split string into 3 values
		var chunk_position : Vector3i = Vector3i(int(coords[0]), int(coords[1]), int(coords[2])) # package values into Vector3i
		var relative_chunk_position = abs(chunk_position - player_chunk_position)
		
		var is_out_of_range = false
		if (relative_chunk_position.x > RENDER_DISTANCE) : is_out_of_range = true
		if (relative_chunk_position.y > RENDER_DISTANCE) : is_out_of_range = true
		if (relative_chunk_position.z > RENDER_DISTANCE) : is_out_of_range = true
		
		if is_out_of_range : unload_chunk(chunk_position)
	
	if mesh_update_needed : update_mesh()

## Generates a noise volume at the specfied SIZE, then returns that noise as a Texture3D object
func create_data() -> void:
	var time: int = Time.get_ticks_msec()
	# create and configure noise
	var noise : FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	var tex3d : NoiseTexture3D = NoiseTexture3D.new()
	tex3d.noise = noise
	tex3d.width = SIZE.x
	tex3d.height = SIZE.y
	tex3d.depth = SIZE.z
	tex3d.seamless = true
	tex3d.normalize = true
	
	var elapsed: float = (Time.get_ticks_msec() - time)/1000.0
	total_time += elapsed
	
	data = tex3d

func load_chunk(chunk_position: Vector3i):
	var new_chunk :VoxelTerrainChunk = VoxelTerrainChunk.new(chunk_position, CHUNK_SIZE, SIZE, ISO, FLAT_SHADED, data, VERBOSE)
	add_child(new_chunk)
	rendered_chunks[str(chunk_position)] = new_chunk
	mesh_update_needed = true
	
func unload_chunk(chunk_position: Vector3i):
	if rendered_chunks.has(str(chunk_position)):
		var chunk : VoxelTerrainChunk = rendered_chunks[str(chunk_position)]
		chunk.queue_free()
		rendered_chunks.erase(str(chunk_position))
		mesh_update_needed = true
		if (VERBOSE) : print("chunk unloaded at: " + str(chunk_position))

func update_mesh() -> void:
	var time: int = Time.get_ticks_msec()
	var mesh_data = []
	mesh_data.resize(Mesh.ARRAY_MAX)
	mesh_data[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	mesh_data[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	
	for child in get_children():
		if child is VoxelTerrainChunk:
			for vert in child.output["vertices"]:
				mesh_data[Mesh.ARRAY_VERTEX].append(vert + (Vector3(child.CHUNK_POSITION) * Vector3(CHUNK_SIZE)))
			for normal in child.output["normals"]:
				mesh_data[Mesh.ARRAY_NORMAL].append(normal)
	
	var array_mesh = ArrayMesh.new()
	array_mesh.clear_surfaces()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.DARK_KHAKI
	array_mesh.surface_set_material(0, mat)
	array_mesh.resource_local_to_scene = true
	
	self.mesh = array_mesh
	mesh_update_needed = false
	
	var elapsed: float = (Time.get_ticks_msec() - time)/1000.0
	total_time += elapsed
	if (VERBOSE) : print("terrain mesh created in " + str(elapsed))
