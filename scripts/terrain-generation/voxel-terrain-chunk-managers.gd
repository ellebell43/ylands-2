#@tool
extends MeshInstance3D
class_name VoxelTerrainChunkManager

## Reference to player object. Used to determine loaded chunks
@export var PLAYER : CharacterBody3D
## Total size of the area. Should be a multiple of CHUNK_SIZE
@export var SIZE : Vector3i = Vector3i(1280, 128, 1280) # 1280 * 128 * 1280 takes about 2s to generate noise texture
## The volume a single chunk is.
@export var CHUNK_SIZE : Vector3i = Vector3i(128, 128, 128)
@export var RENDER_DISTANCE : int = 5
## defines what value represent whether a vertex is inside or outside of the mesh. Interpolated from noise luminance with an inclusive range from 0.0 to 1.0
@export var ISO : float = 0.6
@export var FLAT_SHADED : bool = false
@export var VERBOSE : bool = true

var data : Texture3D
var rendered_chunks : = {}

var total_time : float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready():
	data = create_data(SIZE)
	
	if (VERBOSE):
		print("===============================================")
		print("chunk manager ready in: " + str(total_time) + "s")
		print("===============================================")


func _process(_delta: float) -> void:
	# calculate player chunk position
	var player_chunk_position : Vector3i = Vector3i(int(PLAYER.global_position.x / CHUNK_SIZE.x),int(PLAYER.global_position.y / CHUNK_SIZE.y),int(PLAYER.global_position.z / CHUNK_SIZE.z))
	# Iterate through chunks within range, and load chunks that haven't been loaded yet
	for x in range(player_chunk_position.x - RENDER_DISTANCE, player_chunk_position.x + RENDER_DISTANCE):
		for y in range(player_chunk_position.y - RENDER_DISTANCE, player_chunk_position.y + RENDER_DISTANCE):
			for z in range(player_chunk_position.z - RENDER_DISTANCE, player_chunk_position.z + RENDER_DISTANCE):
				var chunk_key = str(x) + "," + str(y) + "," + str(z)
				var chunk_position : Vector3i = Vector3i(x, y, z)
				if not rendered_chunks.has(chunk_key):
					load_chunk(chunk_position)
	
	# Iterate through rendered chunks and confirm all are in range, otherwise, unload
	for key in rendered_chunks:
		var coords : Array[int] = key.split(",")
		var chunk_position : Vector3i = Vector3i(coords[0], coords[1], coords[2])
		var is_out_of_range = abs(chunk_position - player_chunk_position) < RENDER_DISTANCE
		if is_out_of_range:
			unload_chunk(chunk_position)

## Generates a noise volume at the specfied SIZE, then returns that noise as a Texture3D object
func create_data(size: Vector3i) -> Texture3D:
	var time: int = Time.get_ticks_msec()
	# create and configure noise
	var noise : FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	
	# create image array from 3d noise volume
	# invert=false, normalize=true
	var img_array : Array[Image] = noise.get_image_3d(size.x, size.y, size.z, false, true)
	
	# create texture3d from 3d image
	# use_mipmaps=false
	var tex3d = ImageTexture3D.new()
	tex3d.create(img_array[0].get_format(), size.x, size.y, size.z, false, img_array)
	
	var elapsed: float = (Time.get_ticks_msec() - time)/1000.0
	total_time += elapsed
	print("noise texture generated in: " + str(elapsed) + "s")
	
	return tex3d

func load_chunk(chunk_position: Vector3i):
	var new_chunk :VoxelTerrainChunk = VoxelTerrainChunk.new(chunk_position, CHUNK_SIZE, ISO, FLAT_SHADED, data, VERBOSE)
	add_child(new_chunk)
	rendered_chunks[str(chunk_position)] = new_chunk
	
func unload_chunk(chunk_position: Vector3i):
	if (VERBOSE) : print("chunk unloaded at: " + str(chunk_position))
