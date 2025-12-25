extends MeshInstance3D

## The width terrain. Determines the amount of z-axis vertices
@export var width := 50.0
## The length generated terrain. Determines the amount of x-axis vertices
@export var length := 50.0

func create_mesh_chunk() -> void:
	print("creating mesh")
	# initialize an empty surface array and resize it to expected value
	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Initialize data arrays needed for the surface array
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	var colors = PackedColorArray()
	
	var x := 0.0
	var z := 0.0
	var y := 0.2
	
	var this_row := 0
	var prev_row := 0
	var point := 0
	
	for a in (width):
		var u := float(a) / width
		for b in length:
			var v := float(b) / length
			var vert = Vector3(x + b, y, z + a)
			verts.append(vert)
			normals.append(Vector3(0,1,0))
			uvs.append(Vector2(u,v))
			colors.append(Color(randi() % 225, randi() % 225, randi() % 225))
			point += 1
			
			if (a > 0 and b > 0):
				indices.append(prev_row + int(b) - 1)
				indices.append(prev_row + int(b))
				indices.append(this_row + int(b) - 1)

				indices.append(prev_row + int(b))
				indices.append(this_row + int(b))
				indices.append(this_row + int(b) - 1)
		
		prev_row = this_row
		this_row = point
	
	# Commit data to array mesh
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors
	
	# Create mesh surface from mesh array.
	# No blendshapes, lods, or compression used.
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	print("mesh created")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	create_mesh_chunk()
	position.x = -length / 2
	position.z = -width / 2
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
