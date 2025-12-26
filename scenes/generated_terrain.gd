class_name GeneratedTerrain
extends MeshInstance3D

## The width terrain. Determines the amount of z-axis vertices
@export var z_length := 50.0
## The length generated terrain. Determines the amount of x-axis vertices
@export var x_length := 50.0

func create_mesh_chunk() -> void:
	# initialize an empty surface array and resize it to expected value
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Initialize data arrays needed for the surface array
	var verts = PackedVector3Array()
	var uvs = PackedVector2Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	var colors = PackedColorArray()
		
	var num_triangles := x_length * z_length * 2
	var triangle := 1
	# increase x every z_length
	var x := 0
	var z := 0
	while triangle <= num_triangles:
		if triangle % 2 == 0:
			var a := Vector3(x+1, 1, z+1)
			var b := Vector3(x, 1, z+1)
			var c := Vector3(x+1, 1, z+1)
			x += 1
			if (x > z_length):
				z += 1
				x = 0
		else:
			var a := Vector3(x, 1, z)
			var b := Vector3(x, 1, z+1)
			var c := Vector3(x+1, 1, z+1)
		triangle += 1
	
	#var x := 0.0
	#var z := 0.0
	##var y := 0.2
	#
	#var this_row := 0
	#var prev_row := 0
	#var point := 0
	#
	#for a in (width):
		## determine u value based on ratio relative to width
		#var u := float(a) / width
		#for b in length:
			## determine v value based on ratio relative to length
			#var v := float(b) / length
			## determine vertex position and add to vert array
			#var vert = Vector3(x + b, randf(), z + a)
			#verts.append(vert)
			## create normal. THIS IS NOT RIGHT. NEEDS TO BE ACTUALLY CALCULATED
			#normals.append(vert.normalized() * -1)
			##normals.append(Vector3(0,1,0))
			#uvs.append(Vector2(u,v))
			#colors.append(Color.SADDLE_BROWN)
			#point += 1
			#
			#if (a > 0 and b > 0):
				#indices.append(prev_row + int(b) - 1)
				#indices.append(prev_row + int(b))
				#indices.append(this_row + int(b) - 1)
#
				#indices.append(prev_row + int(b))
				#indices.append(this_row + int(b))
				#indices.append(this_row + int(b) - 1)
		#
		#prev_row = this_row
		#this_row = point
	#
	## Commit data to array mesh
	#arrays[Mesh.ARRAY_VERTEX] = verts
	#arrays[Mesh.ARRAY_TEX_UV] = uvs
	#arrays[Mesh.ARRAY_NORMAL] = normals
	#arrays[Mesh.ARRAY_INDEX] = indices
	#arrays[Mesh.ARRAY_COLOR] = colors
	#
	## Create mesh surface from mesh array.
	## No blendshapes, lods, or compression used.
	#mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	#var mat := StandardMaterial3D.new()
	#mat.vertex_color_use_as_albedo = true
	#mesh.surface_set_material(0, mat)

func create_mesh_collision() -> void:
	create_multiple_convex_collisions()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	create_mesh_chunk()
	create_mesh_collision()
	# set posisiton relative to defined size
	position.x = -x_length / 2
	position.z = -z_length / 2
	
	# display in wireframe
	#get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
