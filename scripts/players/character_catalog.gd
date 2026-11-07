class_name CharacterCatalog
extends RefCounted
## Personajes bíblicos disponibles como fichas (provisionales: peones de colores).
## Más adelante cada uno podrá tener su modelo 3D propio en assets/models.

const CHARACTERS: Array = [
	{
		"id": "moises",
		"name": "Moisés",
		"title": "El guía del desierto",
		"description": "Guió al pueblo de Israel fuera de Egipto y a través del desierto.",
		"reference": "Éxodo 3-14",
		"color": Color(0.20, 0.45, 0.85),
	},
	{
		"id": "david",
		"name": "David",
		"title": "Pastor, músico y rey",
		"description": "Siendo joven venció a Goliat con una honda y llegó a ser rey de Israel.",
		"reference": "1 Samuel 16-17",
		"color": Color(0.85, 0.25, 0.25),
	},
	{
		"id": "ester",
		"name": "Ester",
		"title": "La reina valiente",
		"description": "Arriesgó su vida para interceder por su pueblo ante el rey.",
		"reference": "Ester 4-7",
		"color": Color(0.65, 0.30, 0.80),
	},
	{
		"id": "rut",
		"name": "Rut",
		"title": "Lealtad y fidelidad",
		"description": "Permaneció junto a su suegra Noemí y la acompañó hasta Belén.",
		"reference": "Rut 1",
		"color": Color(0.25, 0.70, 0.40),
	},
	{
		"id": "daniel",
		"name": "Daniel",
		"title": "Fiel en Babilonia",
		"description": "Se mantuvo fiel a Dios y fue librado del foso de los leones.",
		"reference": "Daniel 6",
		"color": Color(0.95, 0.60, 0.15),
	},
	{
		"id": "josue",
		"name": "Josué",
		"title": "El que cruzó el Jordán",
		"description": "Sucedió a Moisés y guió a Israel a la tierra prometida.",
		"reference": "Josué 1-3",
		"color": Color(0.15, 0.70, 0.75),
	},
]


static func all_characters() -> Array:
	return CHARACTERS


static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for entry in CHARACTERS:
		ids.append(str(entry["id"]))
	return ids


## Devuelve el personaje con ese id, o {} si no existe.
static func find_character(id: String) -> Dictionary:
	for entry in CHARACTERS:
		if str(entry["id"]) == id:
			return entry
	return {}


static func default_character_id() -> String:
	return str(CHARACTERS[0]["id"])
