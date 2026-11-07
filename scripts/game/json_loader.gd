class_name JsonLoader
extends RefCounted
## Lectura segura de los archivos JSON de la carpeta data/.


## Devuelve el objeto JSON como Dictionary, o {} si el archivo falta o no es válido.
static func load_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("JsonLoader: no existe el archivo %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("JsonLoader: %s no contiene un objeto JSON válido" % path)
	return {}
