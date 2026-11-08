#!/usr/bin/env python3
"""Añade a data/questions/challenges.json los desafíos propios de cada mapa (Etapa 3).

Herramienta de trabajo (no es parte del juego). Los desafíos son originales: las preguntas y las
explicaciones están escritas con palabras propias y cada referencia es un pasaje real que se puede
comprobar en cualquier Biblia. No se copia texto de ninguna versión con derechos de autor.
También añade a data/verses/verse_references.json las referencias de los versículos a completar
(solo la referencia; el campo 'text' queda vacío) y reasigna los mapas antiguos.

Uso: gen_challenges.py <challenges.json> <verse_references.json> [--dry]
Es idempotente: vuelve a generar siempre los desafíos de mapa desde cero.
"""
import json
import re
import sys
import unicodedata

CHALLENGES = sys.argv[1]
VERSES = sys.argv[2]
DRY = "--dry" in sys.argv

# Libros con su número de capítulos (igual que scripts/questions/bible_reference.gd).
BOOKS = {
    "Génesis": 50, "Éxodo": 40, "Levítico": 27, "Números": 36, "Deuteronomio": 34, "Josué": 24,
    "Jueces": 21, "Rut": 4, "1 Samuel": 31, "2 Samuel": 24, "1 Reyes": 22, "2 Reyes": 25,
    "1 Crónicas": 29, "2 Crónicas": 36, "Esdras": 10, "Nehemías": 13, "Ester": 10, "Job": 42,
    "Salmos": 150, "Proverbios": 31, "Eclesiastés": 12, "Cantares": 8, "Isaías": 66, "Jeremías": 52,
    "Lamentaciones": 5, "Ezequiel": 48, "Daniel": 12, "Oseas": 14, "Joel": 3, "Amós": 9, "Abdías": 1,
    "Jonás": 4, "Miqueas": 7, "Nahúm": 3, "Habacuc": 3, "Sofonías": 3, "Hageo": 2, "Zacarías": 14,
    "Malaquías": 4, "Mateo": 28, "Marcos": 16, "Lucas": 24, "Juan": 21, "Hechos": 28, "Romanos": 16,
    "1 Corintios": 16, "2 Corintios": 13, "Gálatas": 6, "Efesios": 6, "Filipenses": 4,
    "Colosenses": 4, "1 Tesalonicenses": 5, "2 Tesalonicenses": 3, "1 Timoteo": 6, "2 Timoteo": 4,
    "Tito": 3, "Filemón": 1, "Hebreos": 13, "Santiago": 5, "1 Pedro": 5, "2 Pedro": 3, "1 Juan": 5,
    "2 Juan": 1, "3 Juan": 1, "Judas": 1, "Apocalipsis": 22,
}

PREFIX = {"eden": "ed", "arca_noe": "ar", "egipto_exodo": "eg", "desierto_sinai": "ds",
          "monte_sinai": "si", "jerusalen": "je", "belen": "be"}

items = []
verses = []


def _add(map_id, code, n, entry):
    entry = dict(entry)
    entry["id"] = "%s_%s%d" % (PREFIX[map_id], code, n)
    entry["map"] = map_id
    items.append(entry)


def mc(map_id, n, diff, prompt, options, correct, explanation, ref):
    _add(map_id, "mc", n, {"type": "multiple_choice", "difficulty": diff, "prompt": prompt,
                           "options": options, "correct": correct, "explanation": explanation,
                           "reference": ref})


def tf(map_id, n, diff, prompt, truth, explanation, ref):
    _add(map_id, "tf", n, {"type": "true_false", "difficulty": diff, "prompt": prompt,
                           "correct": truth, "explanation": explanation, "reference": ref})


def ch(map_id, n, diff, clues, options, correct, explanation, ref):
    _add(map_id, "ch", n, {"type": "character", "difficulty": diff, "clues": clues,
                           "options": options, "correct": correct, "explanation": explanation,
                           "reference": ref})


def cv(map_id, n, diff, prompt, options, correct, verse_id, explanation, ref, theme):
    _add(map_id, "cv", n, {"type": "complete_verse", "difficulty": diff, "prompt": prompt,
                           "options": options, "correct": correct, "verse_id": verse_id,
                           "explanation": explanation, "reference": ref})
    m = re.match(r"^(.+) (\d+):(\d+)", ref)
    verses.append({"id": verse_id, "reference": ref, "book": m.group(1), "chapter": int(m.group(2)),
                   "verse": int(m.group(3)), "map": map_id, "theme": theme, "text": ""})


def ev(map_id, n, diff, prompt, options, correct, explanation, ref):
    _add(map_id, "ev", n, {"type": "event", "difficulty": diff, "prompt": prompt,
                           "options": options, "correct": correct, "explanation": explanation,
                           "reference": ref})


# =========================================================================== Jardín del Edén
M = "eden"
mc(M, 1, 1, "¿Qué plantó Dios en Edén, hacia el oriente, para el hombre que había formado?",
   ["Un huerto", "Una ciudad", "Una viña", "Un bosque de cedros"], 0,
   "Dios plantó un huerto en Edén y puso allí al hombre que había formado.", "Génesis 2:8")
mc(M, 2, 2, "¿En cuántos brazos se dividía el río que salía de Edén para regar el huerto?",
   ["Dos", "Tres", "Cuatro", "Siete"], 2,
   "El río se repartía en cuatro brazos que regaban la tierra.", "Génesis 2:10")
mc(M, 3, 2, "¿Cuáles eran los dos árboles especiales que estaban en medio del huerto?",
   ["La vida y el conocimiento del bien y del mal", "La higuera y la vid", "El olivo y el cedro",
    "La palmera y el sicómoro"], 0,
   "En medio del huerto estaban el árbol de la vida y el árbol del conocimiento del bien y del mal.",
   "Génesis 2:9")
mc(M, 4, 1, "¿Qué trabajo le encargó Dios al hombre en el huerto?",
   ["Cultivarlo y cuidarlo", "Construir una torre", "Cuidar rebaños lejanos", "Hacer ladrillos"], 0,
   "Dios puso al hombre en el huerto para que lo trabajara y lo guardara.", "Génesis 2:15")
tf(M, 1, 1, "Dios formó al hombre del polvo de la tierra.", True,
   "Dios formó al hombre del polvo y sopló en su nariz aliento de vida.", "Génesis 2:7")
tf(M, 2, 1, "El hombre puso nombre a los animales.", True,
   "Dios trajo los animales al hombre para ver cómo los llamaría, y así quedaron sus nombres.",
   "Génesis 2:19-20")
tf(M, 3, 2, "Dios permitió comer del fruto de todos los árboles del huerto sin ninguna excepción.", False,
   "Dios prohibió comer del árbol del conocimiento del bien y del mal.", "Génesis 2:16-17")
tf(M, 4, 2, "Dios formó a Eva del barro, igual que al hombre.", False,
   "Dios formó a la mujer de una costilla del hombre mientras él dormía.", "Génesis 2:21-22")
ch(M, 1, 1, ["Dios me formó del polvo de la tierra.", "Puse nombre a los animales.",
             "Fui el primer hombre y viví en el huerto de Edén."],
   ["Adán", "Abel", "Set", "Noé"], 0,
   "Era Adán, el primer hombre, a quien Dios puso en el huerto.", "Génesis 2:7; Génesis 2:19-20")
ch(M, 2, 2, ["Fui formada de una costilla.", "Hablé con la serpiente en el huerto.",
             "Mi nombre recuerda a todos los que viven."],
   ["Eva", "Sara", "Rebeca", "Raquel"], 0,
   "Era Eva, la primera mujer; su nombre recuerda a todos los vivientes.",
   "Génesis 2:22; Génesis 3:1-5; Génesis 3:20")
ch(M, 3, 2, ["Era más astuta que todos los animales del campo.",
             "Le hice a la mujer una pregunta para sembrar la duda.",
             "Dios me castigó a andar arrastrándome."],
   ["La serpiente", "El cuervo", "El león", "El águila"], 0,
   "Era la serpiente, que engañó a la mujer en el huerto.", "Génesis 3:1; Génesis 3:14")
ch(M, 4, 3, ["Dios me puso al oriente del huerto de Edén.", "Cuido el camino que lleva al árbol de la vida.",
             "Estoy junto a una espada encendida que da vueltas."],
   ["Un querubín", "Un serafín", "Un centurión", "Un levita"], 0,
   "Eran los querubines con la espada de fuego que guardaban el camino al árbol de la vida.",
   "Génesis 3:24")
cv(M, 1, 1, "Dios puso al hombre en el huerto para que lo ____ y lo cuidara.",
   ["cultivara", "vendiera", "abandonara", "midiera"], 0, "gen_2_15",
   "El hombre recibió el trabajo de cultivar y guardar el huerto.", "Génesis 2:15", "trabajo")
cv(M, 2, 1, "Dios creó al ser humano a su ____.",
   ["imagen", "sombra", "capricho", "tamaño"], 0, "gen_1_27",
   "El ser humano fue creado a imagen de Dios, hombre y mujer.", "Génesis 1:27", "creación")
cv(M, 3, 2, "Dios dijo que no era bueno que el hombre estuviera ____.",
   ["solo", "cansado", "dormido", "enfermo"], 0, "gen_2_18",
   "Por eso Dios hizo una ayuda adecuada para el hombre.", "Génesis 2:18", "compañía")
cv(M, 4, 1, "Al terminar, Dios vio todo lo que había hecho y era muy ____.",
   ["bueno", "triste", "pequeño", "oscuro"], 0, "gen_1_31",
   "Al final de la creación, Dios vio que todo era muy bueno.", "Génesis 1:31", "creación")
ev(M, 1, 1, "Dios hace caer un sueño profundo sobre el hombre y forma a una compañera a partir de una costilla.",
   ["La creación de la mujer", "La torre de Babel", "El diluvio", "La zarza ardiente"], 0,
   "Dios formó a la mujer y se la presentó al hombre.", "Génesis 2:21-22")
ev(M, 2, 1, "Dios forma a una persona con polvo de la tierra y sopla en su nariz aliento de vida.",
   ["La creación del hombre", "El nacimiento de Isaac", "La unción de David", "El bautismo de Jesús"], 0,
   "Así empezó la vida del primer ser humano.", "Génesis 2:7")
ev(M, 3, 2, "La serpiente convence a la mujer de probar el fruto prohibido y los dos desobedecen a Dios.",
   ["La desobediencia en el huerto", "El pacto del arco iris", "La partida de Abraham", "El cruce del Jordán"], 0,
   "Comer del fruto prohibido rompió la confianza con Dios.", "Génesis 3:1-6")
ev(M, 4, 3, "Dios deja a unos guardianes y una espada de fuego para cuidar el camino al árbol de la vida.",
   ["La salida del huerto de Edén", "La entrega de la ley", "La construcción del arca", "La caída de Jericó"], 0,
   "Dios sacó a la pareja del huerto y puso guardianes en el camino al árbol de la vida.",
   "Génesis 3:23-24")

# =========================================================================== Arca de Noé
M = "arca_noe"
mc(M, 1, 3, "¿Cuántos codos de largo debía tener el arca según las instrucciones de Dios?",
   ["300 codos", "100 codos", "500 codos", "1000 codos"], 0,
   "Dios indicó trescientos codos de largo, cincuenta de ancho y treinta de alto.", "Génesis 6:15")
mc(M, 2, 2, "¿De qué madera mandó Dios construir el arca?",
   ["Gofer", "Cedro", "Acacia", "Olivo"], 0,
   "Dios pidió madera de gofer y cubrirla de brea por dentro y por fuera.", "Génesis 6:14")
mc(M, 3, 2, "¿Cuántos pisos o niveles tenía el arca?",
   ["Tres", "Uno", "Cinco", "Siete"], 0,
   "El arca tenía tres niveles: bajo, segundo y tercero.", "Génesis 6:16")
mc(M, 4, 2, "¿Qué ave soltó Noé primero para saber si las aguas habían bajado?",
   ["Un cuervo", "Una paloma", "Un águila", "Una golondrina"], 0,
   "Primero envió un cuervo y después una paloma.", "Génesis 8:6-8")
tf(M, 1, 1, "Noé tenía tres hijos: Sem, Cam y Jafet.", True,
   "Los tres hijos de Noé entraron al arca con sus esposas.", "Génesis 6:10; Génesis 7:13")
tf(M, 2, 1, "La paloma volvió a Noé con una hoja de olivo en el pico.", True,
   "La hoja de olivo mostró que las aguas habían bajado.", "Génesis 8:11")
tf(M, 3, 2, "El arca se detuvo sobre el monte Sinaí.", False,
   "El arca se posó sobre los montes de Ararat.", "Génesis 8:4")
tf(M, 4, 2, "Noé salió del arca por su cuenta apenas dejó de llover, sin esperar nada de Dios.", False,
   "Noé esperó, y Dios mismo le dijo cuándo salir del arca.", "Génesis 8:15-16")
ch(M, 1, 1, ["Dios me halló justo entre la gente de mi tiempo.",
             "Construí un arca enorme siguiendo las medidas que Dios me dio.",
             "Mi familia y yo nos salvamos del diluvio."],
   ["Noé", "Lot", "Jacob", "Matusalén"], 0,
   "Era Noé, que obedeció a Dios y construyó el arca.", "Génesis 6:8-9; Génesis 6:22; Génesis 7:1")
ch(M, 2, 2, ["Me enviaron tres veces.", "La primera vez no hallé dónde posarme y volví.",
             "La segunda vez traje una hoja de olivo."],
   ["La paloma", "El cuervo", "El águila", "La golondrina"], 0,
   "Era la paloma; a la tercera vez ya no regresó porque la tierra estaba seca.", "Génesis 8:8-12")
ch(M, 3, 3, ["Soy uno de los tres hijos de Noé.", "Entré al arca con mi padre, mi esposa y mis hermanos.",
             "Generaciones después, de mi familia nacería Abram."],
   ["Sem", "Cam", "Jafet", "Cus"], 0,
   "Era Sem; de su descendencia nació Abram, el futuro Abraham.", "Génesis 7:13; Génesis 11:10-26")
ch(M, 4, 3, ["Soy el abuelo de Noé.", "Mi padre fue Enoc, quien caminó con Dios.",
             "Viví más años que cualquier otra persona de la que habla la Biblia."],
   ["Matusalén", "Set", "Lamec", "Enós"], 0,
   "Era Matusalén, que vivió 969 años y fue abuelo de Noé.", "Génesis 5:21-27")
cv(M, 1, 1, "Dios puso su ____ en las nubes como señal de su pacto con la tierra.",
   ["arco", "espada", "trono", "manto"], 0, "gen_9_13",
   "El arco iris quedó como señal de la promesa de Dios.", "Génesis 9:13", "pacto")
cv(M, 2, 2, "Dios prometió que mientras exista la tierra no faltarán la siembra y la ____.",
   ["cosecha", "tormenta", "sequía", "guerra"], 0, "gen_8_22",
   "Dios aseguró el ritmo de las estaciones, del día y de la noche.", "Génesis 8:22", "promesa")
cv(M, 3, 2, "Noé hizo todo tal como Dios se lo ____.",
   ["mandó", "negó", "ocultó", "prohibió"], 0, "gen_6_22",
   "Noé obedeció a Dios en todo lo que le pidió.", "Génesis 6:22", "obediencia")
cv(M, 4, 3, "Cuando todos estuvieron adentro, el Señor ____ la puerta del arca.",
   ["cerró", "abrió", "derribó", "quemó"], 0, "gen_7_16",
   "Dios mismo cerró la puerta del arca detrás de ellos.", "Génesis 7:16", "cuidado de Dios")
ev(M, 1, 1, "Después de muchos días de agua, un ave regresa a Noé con una ramita fresca de un árbol en el pico.",
   ["La paloma con la hoja de olivo", "El maná del cielo", "La zarza ardiente", "El sueño de Jacob"], 0,
   "Era la señal de que la tierra volvía a tener vida.", "Génesis 8:11")
ev(M, 2, 1, "Después del diluvio, Dios pone en el cielo una señal de colores para recordar su promesa de no volver a destruir la tierra con agua.",
   ["El arco iris y el pacto con Noé", "La columna de fuego", "La estrella de Belén", "La nube de gloria"], 0,
   "Dios hizo un pacto con Noé y con todos los seres vivos.", "Génesis 9:12-17")
ev(M, 3, 2, "Dios cierra la puerta y se abren las fuentes del gran abismo y las ventanas del cielo.",
   ["El comienzo del diluvio", "La caída de Jericó", "La llegada del maná", "La destrucción de Babel"], 0,
   "Cuando todos estaban a salvo en el arca, empezó el diluvio.", "Génesis 7:11-16")
ev(M, 4, 3, "Cuando bajan las aguas, la gran embarcación descansa sobre la cima de unas montañas.",
   ["El arca se posa en el monte Ararat", "Moisés recibe las tablas", "Jonás sale del pez", "Daniel sale del foso"], 0,
   "El arca quedó sobre los montes de Ararat.", "Génesis 8:4")

# =========================================================================== Egipto y el Éxodo
M = "egipto_exodo"
mc(M, 1, 1, "¿Cuántas plagas envió Dios sobre Egipto?",
   ["Diez", "Siete", "Doce", "Cuarenta"], 0,
   "Dios envió diez plagas hasta que el faraón dejó salir a Israel.", "Éxodo 7-12")
mc(M, 2, 1, "¿Qué pusieron los israelitas en los marcos de sus puertas la noche de la Pascua?",
   ["Sangre de cordero", "Aceite de oliva", "Agua del Nilo", "Ceniza"], 0,
   "La sangre del cordero era la señal para que el ángel pasara de largo.", "Éxodo 12:7")
mc(M, 3, 2, "¿Cuál fue la última plaga que sufrió Egipto?",
   ["La muerte de los primogénitos", "La oscuridad", "El granizo", "Las langostas"], 0,
   "Después de esa plaga el faraón dejó salir al pueblo.", "Éxodo 12:29-31")
mc(M, 4, 3, "¿Con qué cubrió la madre de Moisés la canasta para que flotara?",
   ["Asfalto y brea", "Cera de abejas", "Lana de oveja", "Arcilla del Nilo"], 0,
   "Calafateó la canasta con asfalto y brea y la dejó entre los juncos.", "Éxodo 2:3")
tf(M, 1, 1, "Los israelitas fabricaban ladrillos para el faraón.", True,
   "Los egipcios hicieron amarga la vida de Israel con trabajos duros, como hacer barro y ladrillo.",
   "Éxodo 1:13-14")
tf(M, 2, 1, "El agua del mar se abrió solo para Moisés, y el pueblo tuvo que esperar.", False,
   "Todo el pueblo pasó por en medio del mar en seco.", "Éxodo 14:21-22")
tf(M, 3, 2, "La primera plaga convirtió el agua del Nilo en sangre.", True,
   "Los peces murieron y el río se llenó de mal olor.", "Éxodo 7:19-21")
tf(M, 4, 1, "Los egipcios alcanzaron a Israel y los vencieron junto al mar.", False,
   "Los carros egipcios fueron cubiertos por las aguas cuando entraron al mar.", "Éxodo 14:27-28")
ch(M, 1, 1, ["Me criaron en el palacio de Egipto.", "Dios me envió a pedir que dejaran salir a su pueblo.",
             "Extendí mi vara y el mar se abrió."],
   ["Moisés", "Josué", "Elías", "Samuel"], 0,
   "Era Moisés, el líder que Dios usó para sacar a Israel de Egipto.",
   "Éxodo 2:10; Éxodo 3:10; Éxodo 14:21")
ch(M, 2, 2, ["Vigilé desde lejos la canasta de mi hermano pequeño en el río.",
             "Tomé una pandereta y dirigí un canto de alabanza.",
             "Mis hermanos eran Moisés y Aarón."],
   ["Miriam", "Séfora", "Débora", "Raquel"], 0,
   "Era Miriam, la hermana de Moisés, que cantó a Dios después de cruzar el mar.",
   "Éxodo 2:4; Éxodo 15:20-21")
ch(M, 3, 1, ["Era el rey de Egipto cuando Israel salió.", "No quise dejar ir al pueblo hasta ver las diez plagas.",
             "Mi ejército fue cubierto por el mar."],
   ["El faraón", "Nabucodonosor", "Herodes", "Ciro"], 0,
   "Era el faraón, que se resistió hasta que Egipto sufrió las plagas.", "Éxodo 5:2; Éxodo 14:28")
ch(M, 4, 2, ["Bajé al río y hallé una canasta entre los juncos.", "Adopté al niño como mi hijo.",
             "Le puse por nombre Moisés."],
   ["La hija del faraón", "Miriam", "Séfora", "Jocabed"], 0,
   "Era la hija del faraón, que rescató y adoptó a Moisés.", "Éxodo 2:5-10")
cv(M, 1, 1, "Moisés animó al pueblo diciendo que el Señor pelearía por ellos y que ellos solo debían quedarse ____.",
   ["tranquilos", "corriendo", "escondidos", "dormidos"], 0, "exo_14_14",
   "Israel no tuvo que pelear: Dios defendió a su pueblo.", "Éxodo 14:14", "confianza")
cv(M, 2, 2, "Al verse libre, Israel cantó que el Señor era su fuerza, su canción y su ____.",
   ["salvación", "riqueza", "ejército", "bandera"], 0, "exo_15_2",
   "El pueblo celebró con un canto la liberación que Dios le dio.", "Éxodo 15:2", "alabanza")
cv(M, 3, 2, "Dios prometió llevar a su pueblo a una tierra buena donde fluyen leche y ____.",
   ["miel", "aceite", "vino", "agua"], 0, "exo_3_8",
   "Dios le habló a Moisés desde la zarza y prometió una tierra buena para Israel.", "Éxodo 3:8", "promesa")
cv(M, 4, 1, "De día el Señor guiaba a Israel en una columna de nube, y de noche en una columna de ____.",
   ["fuego", "agua", "piedra", "hielo"], 0, "exo_13_21",
   "Dios acompañó al pueblo de día y de noche para que pudiera caminar.", "Éxodo 13:21", "guía")
ev(M, 1, 1, "Una noche las familias comen cordero y pan sin levadura, listas para salir de viaje.",
   ["La primera Pascua", "El año del jubileo", "La dedicación del templo", "La fiesta de Purim"], 0,
   "Esa noche Dios protegió a Israel y comenzó su salida de Egipto.", "Éxodo 12:1-13")
ev(M, 2, 1, "Moisés extiende su vara y las aguas se levantan como muros a los dos lados del camino.",
   ["La apertura del Mar Rojo", "La caída de Jericó", "El cruce del Jordán", "El diluvio"], 0,
   "Israel cruzó el mar en seco, y los egipcios no pudieron alcanzarlo.", "Éxodo 14:21-22")
ev(M, 3, 3, "Una oscuridad espesa cubre Egipto durante tres días, pero donde viven los israelitas hay luz.",
   ["La plaga de las tinieblas", "La plaga de las ranas", "La plaga del granizo", "La plaga de las moscas"], 0,
   "Fue la novena plaga: las tinieblas sobre Egipto.", "Éxodo 10:21-23")
ev(M, 4, 2, "A la orilla del mar, el pueblo canta y baila al verse libre del ejército que lo perseguía.",
   ["El cántico de Moisés y Miriam", "La dedicación del templo", "El sermón del monte", "La Última Cena"], 0,
   "Israel alabó a Dios por haberlos salvado en el mar.", "Éxodo 15:1; Éxodo 15:20-21")

# =========================================================================== Desierto del Sinaí
M = "desierto_sinai"
mc(M, 1, 1, "¿Cómo se llamó el alimento que Dios envió del cielo cada mañana?",
   ["Maná", "Pan de cebada", "Miel silvestre", "Aceite"], 0,
   "El pueblo lo llamó maná; era blanco y de sabor dulce.", "Éxodo 16:31")
mc(M, 2, 1, "¿De dónde brotó agua cuando Moisés golpeó en Horeb por orden de Dios?",
   ["De una roca", "De una palmera", "De una cueva", "De un pozo viejo"], 0,
   "Dios dijo que saldría agua de la roca para que bebiera el pueblo.", "Éxodo 17:6")
mc(M, 3, 1, "¿Qué aves llenaron el campamento al atardecer para dar carne a Israel?",
   ["Codornices", "Palomas", "Águilas", "Gaviotas"], 0,
   "Por la tarde subieron codornices y cubrieron el campamento.", "Éxodo 16:13")
mc(M, 4, 2, "¿Quiénes sostuvieron los brazos de Moisés durante la batalla contra Amalec?",
   ["Aarón y Hur", "Josué y Caleb", "Nadab y Abiú", "Jetro y Séfora"], 0,
   "Aarón y Hur le sostuvieron los brazos hasta la puesta del sol.", "Éxodo 17:12")
tf(M, 1, 2, "En el sexto día el pueblo recogía el doble de maná, porque el séptimo día no caía.", True,
   "Dios proveyó doble ración para que descansaran el día de reposo.", "Éxodo 16:22-26")
tf(M, 2, 2, "Las aguas de Mara eran dulces cuando Israel llegó.", False,
   "Eran amargas y el pueblo no podía beberlas, hasta que Dios mostró cómo endulzarlas.", "Éxodo 15:23-25")
tf(M, 3, 3, "La vara de Aarón floreció y dio almendras como señal de a quién había escogido Dios.", True,
   "Dios hizo reverdecer la vara de Aarón para calmar las quejas del pueblo.", "Números 17:5-8")
tf(M, 4, 1, "En el desierto, el pueblo nunca se quejó de Moisés.", False,
   "Varias veces se quejaron por el hambre y la sed, pero Dios siguió cuidándolos.", "Éxodo 16:2-3")
ch(M, 1, 2, ["Antes me llamaba Oseas; Moisés me cambió el nombre.",
             "Fui el ayudante de Moisés y subí con él parte del camino al monte de Dios.",
             "Dirigí a Israel cuando por fin cruzó el Jordán."],
   ["Josué", "Caleb", "Eleazar", "Aarón"], 0,
   "Era Josué, ayudante de Moisés y su sucesor al frente de Israel.",
   "Números 13:16; Éxodo 24:13; Josué 3:17")
ch(M, 2, 2, ["Soy suegro de Moisés y sacerdote de Madián.", "Fui a verlo al desierto y le llevé a su esposa y a sus hijos.",
             "Le aconsejé repartir la tarea de juzgar al pueblo."],
   ["Jetro", "Balac", "Caleb", "Elí"], 0,
   "Era Jetro, cuyo consejo ayudó a Moisés a organizar a Israel.", "Éxodo 18:1-24")
ch(M, 3, 2, ["Éramos doce, uno de cada tribu de Israel.", "Moisés nos envió a ver cómo era la tierra de Canaán.",
             "Volvimos después de cuarenta días con un racimo de uvas enorme."],
   ["Los doce espías", "Los doce apóstoles", "Los doce hijos de Jacob", "Los doce jueces de Israel"], 0,
   "Eran los doce espías que exploraron la tierra prometida.", "Números 13:1-3; Números 13:23-25")
ch(M, 4, 3, ["Pertenecía a la tribu de Judá.", "Dije que sí podíamos conquistar la tierra, aunque otros tenían miedo.",
             "Dios dijo que yo sí entraría en ella, porque lo seguí con fidelidad."],
   ["Caleb", "Josué", "Aarón", "Eleazar"], 0,
   "Era Caleb, que confió en Dios cuando otros tuvieron miedo.", "Números 13:6; Números 13:30; Números 14:24")
cv(M, 1, 1, "Dios prometió que haría llover ____ del cielo para alimentar al pueblo.",
   ["pan", "oro", "fuego", "semillas"], 0, "exo_16_4",
   "Dios prometió dar alimento cada día en el desierto.", "Éxodo 16:4", "provisión")
cv(M, 2, 2, "En Elim, Israel halló doce fuentes de agua y setenta ____.",
   ["palmeras", "pozos", "tiendas", "ovejas"], 0, "exo_15_27",
   "Elim fue un descanso con agua y sombra después de las aguas amargas de Mara.", "Éxodo 15:27", "descanso")
cv(M, 3, 2, "Dios enseñó a los sacerdotes a bendecir al pueblo pidiendo que el Señor lo ____ y lo cuidara.",
   ["bendijera", "castigara", "olvidara", "dispersara"], 0, "num_6_24",
   "Era la bendición que los sacerdotes pronunciaban sobre Israel.", "Números 6:24", "bendición")
cv(M, 4, 2, "Dios se presentó a Israel como el Señor que los ____.",
   ["sana", "encierra", "castiga", "olvida"], 0, "exo_15_26",
   "Dios prometió cuidar la salud del pueblo si lo escuchaba.", "Éxodo 15:26", "cuidado de Dios")
ev(M, 1, 1, "Cada mañana el suelo amanece cubierto de algo fino y blanco que el pueblo recoge para comer.",
   ["La caída del maná", "La primera Pascua", "La caída de Jericó", "El diluvio"], 0,
   "El maná alimentó a Israel durante cuarenta años.", "Éxodo 16:13-15; Éxodo 16:35")
ev(M, 2, 2, "Mientras Moisés mantiene los brazos en alto, Israel gana la batalla.",
   ["La batalla contra Amalec", "La caída de Jericó", "David y Goliat", "La batalla de Gedeón"], 0,
   "Cuando Moisés bajaba los brazos, Amalec avanzaba; por eso lo ayudaron a sostenerlos.", "Éxodo 17:8-13")
ev(M, 3, 3, "Unas serpientes venenosas muerden al pueblo y Dios manda levantar una figura para que quien la mire viva.",
   ["La serpiente de bronce", "La vara de Aarón que floreció", "El becerro de oro", "El agua de Mara"], 0,
   "Quien miraba la serpiente de bronce se sanaba.", "Números 21:4-9")
ev(M, 4, 1, "Moisés golpea una roca con su vara y brota agua para que beba todo el pueblo.",
   ["El agua de la roca", "El cruce del Jordán", "El sueño de Jacob", "La zarza ardiente"], 0,
   "Dios dio agua a su pueblo en el desierto.", "Éxodo 17:5-6")

# =========================================================================== Monte Sinaí
M = "monte_sinai"
mc(M, 1, 1, "¿Cuántos mandamientos escribió Dios en las tablas de piedra?",
   ["Diez", "Siete", "Doce", "Cinco"], 0,
   "Dios escribió las diez palabras del pacto en tablas de piedra.", "Éxodo 34:28")
mc(M, 2, 1, "¿Cuántos días y noches estuvo Moisés en el monte con Dios?",
   ["Cuarenta", "Siete", "Tres", "Cien"], 0,
   "Moisés entró en la nube y estuvo en el monte cuarenta días y cuarenta noches.", "Éxodo 24:18")
mc(M, 3, 1, "¿Qué mandó Dios construir para habitar en medio de su pueblo?",
   ["Un santuario o tabernáculo", "Una muralla", "Una torre hasta el cielo", "Un palacio de marfil"], 0,
   "Dios pidió un santuario portátil, el tabernáculo, para estar presente entre los israelitas.",
   "Éxodo 25:8-9")
mc(M, 4, 2, "¿Cuántos ancianos de Israel subieron con Moisés a ver a Dios en el monte?",
   ["Setenta", "Doce", "Cien", "Tres"], 0,
   "Subieron setenta ancianos de Israel junto con Moisés y sus acompañantes.", "Éxodo 24:9-10")
tf(M, 1, 1, "El pueblo vio relámpagos y oyó truenos y un fuerte sonido de trompeta en el monte.", True,
   "Una nube espesa cubría el monte y todo el pueblo temblaba.", "Éxodo 19:16")
tf(M, 2, 1, "Dios entregó los mandamientos escritos en tablas de madera.", False,
   "Los escribió en tablas de piedra.", "Éxodo 31:18")
tf(M, 3, 2, "Moisés podía subir a la cumbre, pero el pueblo tenía un límite alrededor del monte.", True,
   "Dios puso límites para que nadie tocara el monte mientras él estaba presente.",
   "Éxodo 19:12; Éxodo 19:20")
tf(M, 4, 1, "Aarón fue quien recibió las tablas de piedra en la cumbre.", False,
   "Fue Moisés quien subió y recibió las tablas.", "Éxodo 24:12; Éxodo 31:18")
ch(M, 1, 1, ["Subí al monte y estuve cuarenta días con Dios.", "Bajé con dos tablas de piedra en las manos.",
             "Mi rostro resplandecía después de hablar con él."],
   ["Moisés", "Josué", "Elías", "Samuel"], 0,
   "Era Moisés, que recibió la ley en el monte Sinaí.", "Éxodo 24:18; Éxodo 34:29")
ch(M, 2, 2, ["Mi hermano tardó en bajar del monte y el pueblo me pidió dioses.",
             "Con el oro de los aretes moldeé una figura.", "Más tarde fui sacerdote de Israel."],
   ["Aarón", "Hur", "Eleazar", "Itamar"], 0,
   "Era Aarón, que cedió a la presión y fundió el becerro de oro.", "Éxodo 32:1-4")
ch(M, 3, 3, ["Dios me llenó de su Espíritu con sabiduría y habilidad.",
             "Trabajé el oro, la plata, el bronce y la madera.", "Ayudé a construir el tabernáculo."],
   ["Bezaleel", "Eleazar", "Itamar", "Hiram"], 0,
   "Era Bezaleel, el artesano que Dios llamó para la obra del tabernáculo.", "Éxodo 31:1-5")
ch(M, 4, 3, ["Somos dos hermanos, hijos de Aarón.", "Subimos con Moisés y los ancianos y vimos al Dios de Israel.",
             "Más tarde ofrecimos un fuego que Dios no había mandado."],
   ["Nadab y Abiú", "Hofni y Finees", "Caín y Abel", "Jacob y Esaú"], 0,
   "Eran Nadab y Abiú, hijos de Aarón.", "Éxodo 24:9-10; Levítico 10:1-2")
cv(M, 1, 1, "Uno de los diez mandamientos pide apartar un día de la semana para el ____.",
   ["reposo", "mercado", "viaje", "trabajo"], 0, "exo_20_8",
   "Dios apartó un día de descanso para su pueblo.", "Éxodo 20:8", "descanso")
cv(M, 2, 1, "Uno de los mandamientos pide que honremos a nuestro ____ y a nuestra madre.",
   ["padre", "vecino", "maestro", "rey"], 0, "exo_20_12",
   "Dios pidió respeto y cuidado para la familia.", "Éxodo 20:12", "familia")
cv(M, 3, 2, "Dios dijo que, si Israel guardaba su pacto, sería su tesoro ____ entre todos los pueblos.",
   ["especial", "olvidado", "escondido", "pequeño"], 0, "exo_19_5",
   "Dios eligió a Israel como un pueblo especial para él.", "Éxodo 19:5", "pacto")
cv(M, 4, 1, "Uno de los diez mandamientos pide no ____ lo que es de otra persona.",
   ["robar", "cantar", "viajar", "dormir"], 0, "exo_20_15",
   "Dios protegió la propiedad y la honradez entre su pueblo.", "Éxodo 20:15", "honradez")
ev(M, 1, 1, "Truenos, relámpagos, una nube espesa y un sonido de trompeta cubren el monte mientras el pueblo tiembla.",
   ["Dios desciende sobre el monte Sinaí", "La caída de Jericó", "El diluvio", "La visita de los sabios"], 0,
   "Dios se mostró en el monte para hacer su pacto con Israel.", "Éxodo 19:16-19")
ev(M, 2, 2, "Moisés baja con las tablas y, al ver al pueblo bailando ante una estatua, las arroja y se rompen.",
   ["El becerro de oro", "La zarza ardiente", "El cruce del Jordán", "La torre de Babel"], 0,
   "El pueblo se había apartado de Dios mientras esperaba.", "Éxodo 32:15-19")
ev(M, 3, 1, "Dios habla desde el monte y da a su pueblo diez normas para guiar su vida.",
   ["La entrega de los diez mandamientos", "El sermón del monte", "El bautismo de Jesús", "La Última Cena"], 0,
   "Los diez mandamientos son la base de la ley que Dios dio a Israel.", "Éxodo 20:1-17")
ev(M, 4, 3, "Un hombre baja de la montaña con la cara tan brillante que el pueblo se asusta, y se cubre con un velo.",
   ["El rostro resplandeciente de Moisés", "La visión de Isaías", "La transfiguración de Jesús", "El sueño de Jacob"], 0,
   "Moisés se ponía el velo ante el pueblo y se lo quitaba al hablar con Dios.", "Éxodo 34:29-35")

# =========================================================================== Jerusalén
M = "jerusalen"
mc(M, 1, 1, "¿Qué rey conquistó Jerusalén y la hizo su capital?",
   ["David", "Saúl", "Salomón", "Ezequías"], 0,
   "David tomó la fortaleza de Sión y la llamó la ciudad de David.", "2 Samuel 5:6-9")
mc(M, 2, 1, "¿Quién construyó el primer templo en Jerusalén?",
   ["Salomón", "David", "Josué", "Nehemías"], 0,
   "Salomón construyó la casa del Señor en Jerusalén.", "1 Reyes 6:1")
mc(M, 3, 2, "¿Qué madera llegó desde el Líbano para construir el templo?",
   ["Cedro", "Ébano", "Roble", "Sicómoro"], 0,
   "Hiram, rey de Tiro, envió cedros y cipreses a Salomón.", "1 Reyes 5:6-10")
mc(M, 4, 2, "¿Qué se colocó dentro del lugar santísimo del templo de Salomón?",
   ["El arca del pacto", "El candelero de plata", "Un trono de marfil", "La mesa de los panes"], 0,
   "Los sacerdotes pusieron el arca del pacto en el lugar santísimo.", "1 Reyes 8:6")
tf(M, 1, 2, "Cuando Dios le preguntó qué quería, Salomón pidió riquezas y una vida larga.", False,
   "Salomón pidió sabiduría para gobernar al pueblo, y eso agradó a Dios.", "1 Reyes 3:5-11")
tf(M, 2, 2, "Salomón tardó siete años en construir el templo.", True,
   "La obra del templo terminó después de siete años.", "1 Reyes 6:38")
tf(M, 3, 3, "Las piedras del templo llegaron ya labradas de la cantera, así que no se oyeron herramientas de hierro en la obra.", True,
   "Las piedras se prepararon antes, y en el sitio no se oyó martillo ni hacha.", "1 Reyes 6:7")
tf(M, 4, 2, "El rey David fue quien construyó el templo de Jerusalén.", False,
   "David reunió materiales, pero fue su hijo Salomón quien construyó el templo.", "1 Reyes 5:3-5")
ch(M, 1, 1, ["Reinaba en Hebrón antes de conquistar Jerusalén.",
             "Traje el arca del pacto a la ciudad con alegría y baile.", "Mi hijo construyó el templo."],
   ["David", "Saúl", "Salomón", "Absalón"], 0,
   "Era David, el rey que hizo de Jerusalén su capital.", "2 Samuel 5:5; 2 Samuel 6:12-15")
ch(M, 2, 1, ["Pedí a Dios sabiduría para gobernar a su pueblo.",
             "Un rey de Tiro me envió madera para una gran obra.", "Construí el templo en Jerusalén."],
   ["Salomón", "David", "Roboam", "Josías"], 0,
   "Era Salomón, famoso por su sabiduría y por construir el templo.", "1 Reyes 3:9-12; 1 Reyes 6:1")
ch(M, 3, 3, ["Fui rey de Tiro y amigo de David.", "Envié cedros y cipreses a Salomón.",
             "Mis obreros cortaron la madera en el Líbano."],
   ["Hiram", "Nabucodonosor", "Ciro", "Senaquerib"], 0,
   "Era Hiram, que colaboró con Salomón en la obra del templo.", "1 Reyes 5:1-10")
ch(M, 4, 3, ["Recibí una carta amenazadora del rey de Asiria.", "La extendí delante del Señor en el templo y oré.",
             "Dios envió un ángel y la ciudad se salvó."],
   ["Ezequías", "Josías", "Acab", "Joram"], 0,
   "Era Ezequías, rey de Judá, que confió en Dios cuando Jerusalén fue rodeada.",
   "2 Reyes 19:14-19; 2 Reyes 19:35")
cv(M, 1, 1, "El salmista pide que oremos por la ____ de Jerusalén.",
   ["paz", "riqueza", "fama", "muralla"], 0, "sal_122_6",
   "El salmo anima a pedir paz y bien para la ciudad.", "Salmos 122:6", "oración")
cv(M, 2, 2, "Como los montes rodean a Jerusalén, así el Señor ____ a los que confían en él.",
   ["protege", "olvida", "castiga", "abandona"], 0, "sal_125_2",
   "El salmo compara el cuidado de Dios con las montañas que rodean la ciudad.", "Salmos 125:2", "protección")
cv(M, 3, 3, "Salomón reconoció que ni el cielo de los cielos puede ____ a Dios, mucho menos un templo.",
   ["contener", "asustar", "cansar", "vencer"], 0, "1re_8_27",
   "Dios es más grande que cualquier edificio, aunque escucha a su pueblo en el templo.",
   "1 Reyes 8:27", "grandeza de Dios")
cv(M, 4, 1, "David tomó la fortaleza de Sión, que desde entonces se llamó la ____ de David.",
   ["ciudad", "torre", "puerta", "casa"], 0, "2sa_5_7",
   "Jerusalén fue conocida como la ciudad de David.", "2 Samuel 5:7", "ciudad de David")
ev(M, 1, 1, "David y su pueblo entran a la ciudad con gritos de alegría, trompetas y bailes, llevando el arca.",
   ["El traslado del arca a Jerusalén", "La construcción del arca de Noé", "El cruce del Mar Rojo", "La caída de Jericó"], 0,
   "David llevó el arca a Jerusalén con gran fiesta.", "2 Samuel 6:12-15")
ev(M, 2, 2, "Una nube llena la casa de Dios recién terminada y el rey ora de pie ante todo el pueblo, con las manos extendidas al cielo.",
   ["La dedicación del templo", "La entrega de la ley", "El bautismo de Jesús", "La visita de los sabios"], 0,
   "La gloria del Señor llenó el templo cuando fue dedicado.", "1 Reyes 8:10-11; 1 Reyes 8:22")
ev(M, 3, 3, "Un grupo reconstruye las puertas y las murallas arruinadas de la ciudad en cincuenta y dos días.",
   ["La reconstrucción de la muralla", "La construcción del templo", "El regreso del arca", "La caída de Babilonia"], 0,
   "Nehemías dirigió al pueblo y terminaron el muro a pesar de las amenazas.", "Nehemías 6:15")
ev(M, 4, 2, "Un niño de doce años se queda en Jerusalén conversando con los maestros de la ley, mientras sus padres lo buscan angustiados.",
   ["El niño Jesús en el templo", "El bautismo de Jesús", "La huida a Egipto", "La visita de los pastores"], 0,
   "Sus padres lo hallaron en el templo escuchando y preguntando a los maestros.", "Lucas 2:41-47")

# =========================================================================== Belén
M = "belen"
mc(M, 1, 2, "¿Qué profeta anunció que de Belén saldría un gobernante para Israel?",
   ["Miqueas", "Jonás", "Amós", "Abdías"], 0,
   "Miqueas dijo que de la pequeña Belén saldría quien gobernaría a Israel.", "Miqueas 5:2")
mc(M, 2, 1, "¿Dónde recostó María a su hijo recién nacido?",
   ["En un pesebre", "En un trono", "En un carro", "En un barco"], 0,
   "Lo envolvió en pañales y lo recostó en un pesebre porque no había lugar en la posada.", "Lucas 2:7")
mc(M, 3, 2, "¿A quién ungió el profeta Samuel como futuro rey en Belén, en casa de Isaí?",
   ["David", "Eliab", "Saúl", "Jonatán"], 0,
   "Samuel ungió a David, el menor de los hijos de Isaí, que cuidaba las ovejas.",
   "1 Samuel 16:1; 1 Samuel 16:11-13")
mc(M, 4, 2, "¿Qué regalos llevaron los sabios de oriente a Jesús?",
   ["Oro, incienso y mirra", "Pan, vino y miel", "Plata, cobre y hierro", "Lana, lino y seda"], 0,
   "Abrieron sus tesoros y le ofrecieron oro, incienso y mirra.", "Mateo 2:11")
tf(M, 1, 1, "José y María viajaron a Belén por un censo ordenado por el emperador.", True,
   "Cada persona debía inscribirse en la ciudad de su familia, y José era de la familia de David.",
   "Lucas 2:1-5")
tf(M, 2, 1, "María y José tenían reservado un cuarto cómodo en la posada de Belén.", False,
   "No había lugar para ellos en la posada, y el niño fue puesto en un pesebre.", "Lucas 2:7")
tf(M, 3, 2, "Herodes dijo que quería adorar al niño, pero en realidad quería hacerle daño.", True,
   "Por eso Dios avisó a José y a los sabios en sueños.", "Mateo 2:8; Mateo 2:13")
tf(M, 4, 3, "Rut, la bisabuela del rey David, había nacido en Belén.", False,
   "Rut era moabita; llegó a Belén con su suegra Noemí y allí se casó con Booz.", "Rut 1:4; Rut 1:19; Rut 4:13-17")
ch(M, 1, 1, ["Un ángel me anunció que tendría un hijo.", "Viajé a Belén con mi esposo.",
             "Envolví a mi bebé en pañales y lo recosté en un pesebre."],
   ["María", "Elisabet", "Ana", "Marta"], 0,
   "Era María, la madre de Jesús.", "Lucas 1:26-31; Lucas 2:4-7")
ch(M, 2, 2, ["Soy descendiente de David y trabajaba como carpintero.",
             "Un ángel me habló en sueños y me pidió recibir a mi esposa.",
             "Llevé a mi familia a Egipto para escapar de un rey cruel."],
   ["José, esposo de María", "José, hijo de Jacob", "José de Arimatea", "José Barsabás"], 0,
   "Era José, el esposo de María, que cuidó a Jesús.", "Mateo 1:20; Mateo 13:55; Mateo 2:13-14")
ch(M, 3, 1, ["Me aparecí a unos pastores de noche y la gloria del Señor los rodeó.",
             "Les dije que no tuvieran miedo.", "Anuncié que había nacido el Salvador."],
   ["Un ángel del Señor", "Un sacerdote", "Un profeta", "Un mensajero romano"], 0,
   "Era un ángel del Señor, que dio la buena noticia a los pastores.", "Lucas 2:9-11")
ch(M, 4, 3, ["Soy moabita y regresé a Belén con mi suegra.", "Fui a recoger espigas al campo de un pariente.",
             "Me casé con Booz y fui bisabuela del rey David."],
   ["Rut", "Noemí", "Orfa", "Ester"], 0,
   "Era Rut, cuya fidelidad a Noemí la llevó a Belén y a la familia del rey David.",
   "Rut 1:16-19; Rut 2:2-3; Rut 4:13-17")
cv(M, 1, 1, "El ángel dijo a los pastores que esa noche, en la ciudad de David, había nacido un ____ para el pueblo.",
   ["Salvador", "guerrero", "juez", "mercader"], 0, "luc_2_11",
   "Jesús nació para salvar a su pueblo.", "Lucas 2:11", "salvación")
cv(M, 2, 2, "Los ángeles alabaron a Dios y anunciaron ____ en la tierra para las personas que él ama.",
   ["paz", "guerra", "tristeza", "hambre"], 0, "luc_2_14",
   "El nacimiento de Jesús trajo un mensaje de paz.", "Lucas 2:14", "paz")
cv(M, 3, 3, "Al buscar al nuevo rey en Belén, Samuel aprendió que Dios no mira la apariencia, sino el ____.",
   ["corazón", "vestido", "tamaño", "nombre"], 0, "1sa_16_7",
   "Dios mira el corazón y no la apariencia externa.", "1 Samuel 16:7", "el corazón")
cv(M, 4, 1, "Los sabios preguntaron por el rey recién nacido porque habían visto su ____ en oriente.",
   ["estrella", "corona", "bandera", "carro"], 0, "mat_2_2",
   "La estrella los guió hasta donde estaba Jesús.", "Mateo 2:2", "adoración")
ev(M, 1, 1, "Un ángel anuncia buenas noticias a unos hombres que cuidan ovejas de noche, y el cielo se llena de cantos.",
   ["El anuncio a los pastores", "La zarza ardiente", "El cruce del Jordán", "La caída de Jericó"], 0,
   "Los pastores fueron los primeros en saber del nacimiento de Jesús.", "Lucas 2:8-14")
ev(M, 2, 1, "Una pareja no encuentra lugar en la posada y el niño nace en un lugar donde hay animales.",
   ["El nacimiento de Jesús en Belén", "El bautismo de Jesús", "La última cena", "El sermón del monte"], 0,
   "Jesús nació en Belén y fue puesto en un pesebre.", "Lucas 2:6-7")
ev(M, 3, 2, "Unos sabios llegan de lejos, se arrodillan y entregan regalos al niño.",
   ["La visita de los sabios de oriente", "La visita de la reina de Sabá", "El bautismo de Jesús", "La coronación de David"], 0,
   "Los sabios adoraron a Jesús y le dieron sus regalos.", "Mateo 2:9-11")
ev(M, 4, 3, "Un ángel avisa en sueños a un padre, y la familia huye de noche para proteger a su niño de un rey cruel.",
   ["La huida a Egipto", "La salida de Egipto", "El regreso del exilio", "El cruce del Jordán"], 0,
   "Un ángel avisó a José en sueños, y la familia salió de inmediato.", "Mateo 2:13-14")


# ------------------------------------------------------------------------ Validación


def fold(text):
    text = unicodedata.normalize("NFD", text.lower())
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    return " " + re.sub(r"[^a-z0-9]+", " ", text).strip() + " "


def words(text):
    return {w for w in fold(text).split() if len(w) >= 5}


def ref_ok(ref):
    for part in ref.split(";"):
        m = re.match(r"^\s*((?:\d )?[^\d]+?) (\d+)(?::(\d+)(?:-(\d+))?|-(\d+))?\s*$", part)
        if not m:
            return False, part
        book, chapter = m.group(1), int(m.group(2))
        if book not in BOOKS or chapter < 1 or chapter > BOOKS[book]:
            return False, part
        if m.group(3) and int(m.group(3)) < 1:
            return False, part
        if m.group(4) and int(m.group(4)) < int(m.group(3)):
            return False, part
        if m.group(5) and int(m.group(5)) < chapter:
            return False, part
    return True, ""


with open(CHALLENGES, encoding="utf-8") as f:
    doc = json.load(f)
base = [c for c in doc["challenges"] if "map" not in c]
base_ids = {c["id"] for c in base}
base_keys = {(c.get("prompt") or "|".join(c.get("clues", []))) for c in base}

errors = []
warnings = []
seen_ids, seen_prompts = set(base_ids), set(base_keys)
per_map = {}
for it in items:
    if it["id"] in seen_ids:
        errors.append("id repetido " + it["id"])
    seen_ids.add(it["id"])
    key = it.get("prompt") or "|".join(it["clues"])
    if key in seen_prompts:
        errors.append("enunciado repetido " + it["id"])
    seen_prompts.add(key)
    ok, bad = ref_ok(it["reference"])
    if not ok:
        errors.append("%s: referencia no válida %r" % (it["id"], bad))
    if len(it.get("prompt", "")) > 220 or len(it["explanation"]) > 220:
        errors.append("%s: texto largo" % it["id"])
    if it["type"] != "true_false":
        opts = it["options"]
        if len(opts) != 4 or len({o.strip().lower() for o in opts}) != 4:
            errors.append("%s: opciones inválidas" % it["id"])
        if not 0 <= it["correct"] < 4:
            errors.append("%s: correcta fuera de rango" % it["id"])
        if any(len(o) > 60 for o in opts):
            errors.append("%s: opción larga" % it["id"])
        # La respuesta correcta no debe repetir las palabras de la pregunta.
        answer_words = words(opts[it["correct"]])
        asked = words(it.get("prompt", "") + " " + " ".join(it.get("clues", [])))
        shared = answer_words & asked
        if answer_words and len(shared) * 2 >= len(answer_words) and it["type"] in ("event", "multiple_choice"):
            warnings.append("%s: la respuesta repite palabras de la pregunta %s" % (it["id"], sorted(shared)))
    if it["type"] == "character":
        if len(it["clues"]) < 2:
            errors.append("%s: pocas pistas" % it["id"])
        if fold(it["options"][it["correct"]]) in fold(" ".join(it["clues"])):
            errors.append("%s: las pistas revelan la respuesta" % it["id"])
    if it["type"] == "complete_verse":
        if it["prompt"].count("____") != 1:
            errors.append("%s: el hueco" % it["id"])
        if len(it["prompt"]) < 30:
            errors.append("%s: enunciado corto" % it["id"])
    counts = per_map.setdefault(it["map"], {})
    counts[it["type"]] = counts.get(it["type"], 0) + 1
for m, counts in per_map.items():
    if sorted(counts.values()) != [4, 4, 4, 4, 4] or len(counts) != 5:
        errors.append("%s: reparto %s" % (m, counts))
    tfs = [i for i in items if i["map"] == m and i["type"] == "true_false"]
    if sum(1 for i in tfs if i["correct"]) not in (1, 2, 3):
        errors.append("%s: verdadero o falso desequilibrado" % m)
    answers = [i["correct"] for i in items if i["map"] == m and i["type"] != "true_false"]
    if len(set(answers)) < 1:
        errors.append("%s: sin respuestas" % m)
vids = [v["id"] for v in verses]
if len(vids) != len(set(vids)):
    errors.append("versículos repetidos")

for w in warnings:
    print("AVISO:", w)
if errors:
    print("\n".join(errors))
    raise SystemExit(1)

# ------------------------------------------------------------------------ Fusión

doc["challenges"] = base + items
doc["format_version"] = 3
doc["note"] = ("Desafíos bíblicos originales. Los que llevan 'map' son propios de ese mapa; los demás son "
               "generales. Cada referencia es un pasaje real que se puede comprobar en cualquier Biblia. "
               "Los enunciados de 'complete_verse' son ideas escritas con palabras propias: NO son citas "
               "textuales de ninguna versión. El texto de una versión con derechos (RVR1960) solo se "
               "mostrará cuando exista autorización (ver data/verses/translations.json).")


def dump(obj):
    out = ["{"]
    keys = list(obj.keys())
    for i, k in enumerate(keys):
        v = obj[k]
        comma = "," if i < len(keys) - 1 else ""
        if k == "challenges":
            out.append('  "challenges": [')
            for j, c in enumerate(v):
                out.append("    " + json.dumps(c, ensure_ascii=False) + ("," if j < len(v) - 1 else ""))
            out.append("  ]" + comma)
        else:
            out.append("  %s: %s%s" % (json.dumps(k, ensure_ascii=False), json.dumps(v, ensure_ascii=False), comma))
    out.append("}")
    return "\n".join(out) + "\n"


with open(VERSES, encoding="utf-8") as f:
    vdoc = json.load(f)
remap = {"betel": "general", "rio_jordan": "general", "mar_galilea": "general", "egipto": "egipto_exodo"}
used_by_base = {c.get("verse_id") for c in base if c["type"] == "complete_verse"}
keep = []
for v in vdoc["verses"]:
    if v["id"] in vids:
        if v["id"] in used_by_base:
            errors.append("el versículo %s ya lo usa un desafío general" % v["id"])
        continue  # lo vuelve a aportar este script
    if v["id"] in ("exo_19_20", "exo_20_3"):
        v["map"] = "monte_sinai"
    v["map"] = remap.get(v["map"], v["map"])
    keep.append(v)
if errors:
    print("\n".join(errors))
    raise SystemExit(1)
vdoc["verses"] = keep + verses

if DRY:
    print("(prueba en seco) desafíos de mapa:", len(items), "| total:", len(doc["challenges"]),
          "| versículos:", len(vdoc["verses"]))
    raise SystemExit(0)

with open(CHALLENGES, "w", encoding="utf-8") as f:
    f.write(dump(doc))
with open(VERSES, "w", encoding="utf-8") as f:
    f.write('{\n  "schema_version": 1,\n  "note": %s,\n  "verses": [\n' % json.dumps(vdoc["note"], ensure_ascii=False))
    f.write(",\n".join("    " + json.dumps(v, ensure_ascii=False) for v in vdoc["verses"]))
    f.write("\n  ]\n}\n")

print("desafíos de mapa:", len(items), "| total:", len(doc["challenges"]), "| versículos:", len(vdoc["verses"]))
