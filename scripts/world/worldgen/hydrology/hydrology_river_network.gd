class_name HydrologyRiverNetwork
extends RefCounted

## One connected drainage tree containing a main stem and all joined tributaries.

var id: int = -1
var source_cell: int = -1
var mouth_cell: int = -1
var discharge: float = 0.0
var order: int = 0
