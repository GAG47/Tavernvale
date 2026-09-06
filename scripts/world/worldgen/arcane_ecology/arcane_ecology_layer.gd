class_name ArcaneEcologyLayer
extends RefCounted

enum EcologyState {
	NORMAL = 0,
	INFLUENCED = 1,
	DOMINANT = 2,
}

enum ManifestationType {
	NONE = 0,
	CRYSTALLINE = 1,
	ECOLOGICAL = 2,
	MIXED = 3,
}

## Cell-aligned categorical results describing realized arcane ecology and the
## primary nature of its manifestation.
var arcane_ecology_state := PackedInt32Array()
var arcane_manifestation_type := PackedInt32Array()


func cell_count() -> int:
	return arcane_ecology_state.size()


static func ecology_state_name(state: int) -> String:
	match state:
		EcologyState.NORMAL:
			return "NORMAL"
		EcologyState.INFLUENCED:
			return "INFLUENCED"
		EcologyState.DOMINANT:
			return "DOMINANT"
		_:
			return "UNKNOWN"


static func manifestation_type_name(manifestation_type: int) -> String:
	match manifestation_type:
		ManifestationType.NONE:
			return "NONE"
		ManifestationType.CRYSTALLINE:
			return "CRYSTALLINE"
		ManifestationType.ECOLOGICAL:
			return "ECOLOGICAL"
		ManifestationType.MIXED:
			return "MIXED"
		_:
			return "UNKNOWN"
