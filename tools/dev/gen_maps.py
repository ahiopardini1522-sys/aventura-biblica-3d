#!/usr/bin/env python3
"""Genera data/maps/maps.json (Etapa 3) con tableros validados.

No forma parte del juego: es una herramienta de trabajo para armar los 7 tableros con las
mismas reglas que BoardLayout.validate() y comprobar que las partidas sean razonables.
"""
import json
import random
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gen/maps.json"


def row_of(t):
    return (t - 1) // 10


def make_board(seed, lad_span, snk_span, lad_bands, snk_bands):
    rng = random.Random(seed)
    used = {1, 100}
    ladders, snakes = [], []
    for lo, hi in lad_bands:
        for _ in range(500):
            s = rng.randint(lo, hi)
            e = s + rng.randint(*lad_span)
            if e > 97 or s in used or e in used or row_of(e) <= row_of(s):
                continue
            used.update((s, e))
            ladders.append([s, e])
            break
        else:
            raise SystemExit("no se pudo colocar una escalera")
    for lo, hi in snk_bands:
        for _ in range(500):
            h = rng.randint(lo, hi)
            t = h - rng.randint(*snk_span)
            if t < 2 or h in used or t in used or row_of(t) >= row_of(h):
                continue
            used.update((h, t))
            snakes.append([h, t])
            break
        else:
            raise SystemExit("no se pudo colocar una serpiente")
    return rng, used, ladders, snakes


def pick_challenges(rng, used, count=20):
    chosen = []
    # Dos por fila aproximadamente, repartidas.
    rows = list(range(10))
    per_row = [2] * 10
    for r in rng.sample(rows, count - 20) if count > 20 else []:
        per_row[r] += 1
    for r in rows:
        tiles = [t for t in range(10 * r + 1, 10 * r + 11) if t not in used and t not in chosen]
        rng.shuffle(tiles)
        # Evita dos desafíos pegados.
        picked = []
        for t in tiles:
            if len(picked) >= per_row[r]:
                break
            if any(abs(t - p) < 2 for p in picked):
                continue
            picked.append(t)
        chosen.extend(picked)
    chosen.sort()
    return chosen


def pick_specials(rng, used, challenges, reward_rows, obstacle_rows):
    taken = set(used) | set(challenges)
    rewards, obstacles = [], []
    for rows_, out in ((reward_rows, rewards), (obstacle_rows, obstacles)):
        for r in rows_:
            tiles = [t for t in range(10 * r + 1, 10 * r + 11) if t not in taken and 1 < t < 100]
            if not tiles:
                raise SystemExit("sin hueco para casilla especial en la fila %d" % r)
            t = rng.choice(tiles)
            taken.add(t)
            out.append(t)
    return rewards, obstacles


def simulate(ladders, snakes, games=3000, seed=5):
    jumps = {a: b for a, b in ladders}
    jumps.update({a: b for a, b in snakes})
    rng = random.Random(seed)
    lengths = []
    for _ in range(games):
        pos, n = 1, 0
        while pos < 100 and n < 3000:
            n += 1
            pos = min(100, pos + rng.randint(1, 6))
            pos = jumps.get(pos, pos)
        lengths.append(n)
    lengths.sort()
    return sum(lengths) / len(lengths), lengths[len(lengths) // 2], lengths[-1]


def check(board, name):
    tiles = set()
    for a, b in board["ladders"]:
        assert b > a and a != 1 and a != 100, (name, "escalera", a, b)
        assert a not in tiles and b not in tiles, (name, "repetida", a, b)
        tiles.update((a, b))
    for a, b in board["snakes"]:
        assert b < a and a != 1 and a != 100, (name, "serpiente", a, b)
        assert a not in tiles and b not in tiles, (name, "repetida", a, b)
        tiles.update((a, b))
    reserved = tiles | {1, 100}
    ch = set()
    for t in board["challenge_tiles"]:
        assert 1 <= t <= 100 and t not in reserved and t not in ch, (name, "desafío", t)
        ch.add(t)
    sp = set()
    for key in ("rewards", "obstacles"):
        for e in board[key]:
            t = e["tile"]
            assert 1 <= t <= 100 and t not in reserved and t not in ch and t not in sp, (name, "especial", t)
            sp.add(t)
            assert e["name"]
            if e["kind"] in ("advance", "back"):
                assert 1 <= e["steps"] <= 4
            if e["kind"] == "stars":
                assert 1 <= e["stars"] <= 3
            if key == "rewards":
                assert e["kind"] in ("advance", "extra_roll", "stars"), (name, e)
            else:
                assert e["kind"] in ("back", "skip"), (name, e)
    assert len(board["ladders"]) == 6 and len(board["snakes"]) == 7, name
    assert 18 <= len(board["challenge_tiles"]) <= 22, (name, len(board["challenge_tiles"]))
    assert len(board["rewards"]) == 4 and len(board["obstacles"]) == 4, name


def special(tile, kind, name, ref, steps=0, stars=0):
    entry = {"tile": tile, "kind": kind, "name": name, "ref": ref}
    if kind in ("advance", "back"):
        entry["steps"] = steps
    if kind == "stars":
        entry["stars"] = stars
    return entry


# --------------------------------------------------------------------------- Mapas

MAPS = []


def add_map(order, mid, name, reference, description, style, board_style, world, requires, reward,
            sound, lighting, theme, board_fixed=None, specials=None, seed=0,
            lad_span=(9, 30), snk_span=(10, 40)):
    if board_fixed is None:
        rng, used, ladders, snakes = make_board(
            seed, lad_span, snk_span,
            [(2, 12), (14, 26), (27, 40), (41, 56), (57, 72), (73, 84)],
            [(16, 28), (29, 42), (43, 55), (56, 68), (69, 80), (81, 92), (93, 99)])
        challenges = pick_challenges(rng, used)
        reward_tiles, obstacle_tiles = pick_specials(rng, used | set(), challenges,
                                                     [1, 3, 5, 7], [2, 4, 6, 8])
        rewards = [special(t, *specials["rewards"][i]) for i, t in enumerate(reward_tiles)]
        obstacles = [special(t, *specials["obstacles"][i]) for i, t in enumerate(obstacle_tiles)]
        board = {"columns": 10, "rows": 10, "style": board_style, "ladders": ladders, "snakes": snakes,
                 "challenge_tiles": challenges, "rewards": rewards, "obstacles": obstacles}
    else:
        board = dict(board_fixed)
        board["style"] = board_style
        board["rewards"] = [special(t, *specials["rewards"][i]) for i, t in enumerate(board_fixed["_reward_tiles"])]
        board["obstacles"] = [special(t, *specials["obstacles"][i]) for i, t in enumerate(board_fixed["_obstacle_tiles"])]
        del board["_reward_tiles"]
        del board["_obstacle_tiles"]
    check(board, mid)
    MAPS.append({
        "id": mid, "order": order, "name": name, "reference": reference, "description": description,
        "status": "available", "style": style,
        "world": world, "unlock": {"requires": requires}, "reward": reward,
        "ambience": {"sound": sound}, "lighting": lighting, "theme": theme, "board": board,
    })


# 1. Jardín del Edén ------------------------------------------------------------
add_map(
    1, "eden", "Jardín del Edén", "Génesis 2:8-17",
    "El huerto que Dios plantó: árboles, ríos y el primer hogar del ser humano.",
    "eden", "garden",
    {"x": -52.0, "z": -12.0, "icon": "tree"}, "",
    {"stars": 10, "badge": "badge_eden", "badge_name": "Guardián del Huerto",
     "badge_text": "Recorriste el Jardín del Edén de principio a fin."},
    "garden",
    {"sun_energy": 0.27, "ambient_energy": 0.30, "fog_density": 0.0035, "sun_dir": [-0.5, 0.65, 0.45]},
    {"tile_a": "#d3eba9", "tile_b": "#a2d17c", "frame": "#5b3d22", "ground": "#5fa04a",
     "sky_top": "#4aa3e8", "sky_horizon": "#f6f1c8", "ambient": "#fff8e0", "fog": "#d9edc2",
     "sun": "#fff2cf", "props": []},
    specials={
        "rewards": [
            ("advance", "Árbol de la vida", "Génesis 2:9", 3),
            ("extra_roll", "Fruto del huerto", "Génesis 2:16", 0),
            ("stars", "Río de cuatro brazos", "Génesis 2:10", 0, 2),
            ("advance", "Rocío del amanecer", "Génesis 2:5-6", 2),
        ],
        "obstacles": [
            ("back", "Espinos y cardos", "Génesis 3:18", 2),
            ("back", "Sombra de la serpiente", "Génesis 3:1", 3),
            ("skip", "Espada encendida", "Génesis 3:24", 0),
            ("back", "Niebla del huerto", "Génesis 2:6", 1),
        ],
    },
    seed=101)

# 2. Arca de Noé ------------------------------------------------------------------
add_map(
    2, "arca_noe", "Arca de Noé", "Génesis 6-8",
    "Noé, su familia y los animales se salvan del diluvio dentro del arca.",
    "arca", "deck",
    {"x": -27.0, "z": -18.0, "icon": "ark"}, "eden",
    {"stars": 15, "badge": "badge_arca", "badge_name": "Capitán del Arca",
     "badge_text": "Llevaste el arca a salvo hasta la meta."},
    "sea",
    {"sun_energy": 0.24, "ambient_energy": 0.31, "fog_density": 0.0055, "sun_dir": [-0.4, 0.55, 0.5]},
    {"tile_a": "#e8c995", "tile_b": "#c99b62", "frame": "#6e4524", "ground": "#4f7fa0",
     "sky_top": "#5f86ad", "sky_horizon": "#dce5e2", "ambient": "#eaf0f3", "fog": "#c9d6da",
     "sun": "#fff0d8", "props": []},
    specials={
        "rewards": [
            ("advance", "Paloma con el olivo", "Génesis 8:11", 3),
            ("extra_roll", "Pareja de animales", "Génesis 7:8-9", 0),
            ("stars", "Arcoíris del pacto", "Génesis 9:13", 0, 2),
            ("advance", "Provisiones del arca", "Génesis 6:21", 2),
        ],
        "obstacles": [
            ("back", "Ola del diluvio", "Génesis 7:17-20", 3),
            ("back", "Cuervo errante", "Génesis 8:7", 1),
            ("skip", "Tormenta de cuarenta días", "Génesis 7:12", 0),
            ("back", "Cubierta resbalosa", "Génesis 7:18", 2),
        ],
    },
    seed=202)

# 3. Egipto y el Éxodo -----------------------------------------------------------
add_map(
    3, "egipto_exodo", "Egipto y el Éxodo", "Éxodo 12-14",
    "Israel sale de Egipto y Dios abre el Mar Rojo para su pueblo.",
    "egipto", "causeway",
    {"x": -30.0, "z": 8.0, "icon": "pyramid"}, "arca_noe",
    {"stars": 20, "badge": "badge_egipto", "badge_name": "Libertador del Éxodo",
     "badge_text": "Cruzaste el Mar Rojo siguiendo al pueblo de Dios."},
    "wind",
    {"sun_energy": 0.28, "ambient_energy": 0.28, "fog_density": 0.0025, "sun_dir": [-0.6, 0.6, 0.45]},
    {"tile_a": "#f3dd9e", "tile_b": "#dcb56a", "frame": "#8a5b2b", "ground": "#dcb875",
     "sky_top": "#3d86d4", "sky_horizon": "#fbe6b4", "ambient": "#fff0d6", "fog": "#f3dcae",
     "sun": "#fff1d2", "props": []},
    specials={
        "rewards": [
            ("advance", "Pan sin levadura", "Éxodo 12:39", 2),
            ("extra_roll", "Columna de fuego", "Éxodo 13:21", 0),
            ("advance", "Camino en seco", "Éxodo 14:21-22", 3),
            ("stars", "Regalos de los egipcios", "Éxodo 12:35-36", 0, 2),
        ],
        "obstacles": [
            ("back", "Plaga de ranas", "Éxodo 8:1-6", 2),
            ("back", "Plaga de langostas", "Éxodo 10:12-15", 3),
            ("skip", "Oscuridad espesa", "Éxodo 10:21-23", 0),
            ("back", "Ladrillos sin paja", "Éxodo 5:6-8", 1),
        ],
    },
    seed=303)

# 4. Desierto del Sinaí (se conserva el tablero de la Etapa 2) ------------------------
desert_board = {
    "columns": 10, "rows": 10,
    "ladders": [[3, 22], [8, 30], [28, 56], [39, 60], [51, 72], [71, 92]],
    "snakes": [[98, 78], [94, 67], [85, 64], [62, 44], [54, 34], [46, 15], [36, 6]],
    "challenge_tiles": [5, 12, 14, 19, 24, 26, 33, 38, 41, 48, 50, 55, 58, 65, 69, 75, 80, 87, 90, 96],
    "_reward_tiles": [17, 43, 66, 83],
    "_obstacle_tiles": [29, 52, 74, 89],
}
add_map(
    4, "desierto_sinai", "Desierto del Sinaí", "Éxodo 16-17",
    "En el desierto, Dios cuida a Israel con maná, codornices y agua de la roca.",
    "desierto", "sand",
    {"x": -6.0, "z": 14.0, "icon": "tent"}, "egipto_exodo",
    {"stars": 25, "badge": "badge_desierto", "badge_name": "Peregrino del Desierto",
     "badge_text": "Atravesaste el desierto confiando en Dios."},
    "desert",
    {"sun_energy": 0.26, "ambient_energy": 0.28, "fog_density": 0.003, "sun_dir": [-0.55, 0.62, 0.5]},
    {"tile_a": "#ead29a", "tile_b": "#d6a766", "frame": "#6b4426", "ground": "#cfa467",
     "sky_top": "#3f78c4", "sky_horizon": "#f6d9a2", "ambient": "#fff0d6", "fog": "#f1d6a4",
     "sun": "#fff1d2", "props": ["palm", "rock", "dune"]},
    board_fixed=desert_board,
    specials={
        "rewards": [
            ("advance", "Maná del cielo", "Éxodo 16:14-15", 2),
            ("advance", "Agua de la roca", "Éxodo 17:6", 3),
            ("extra_roll", "Codornices al anochecer", "Éxodo 16:13", 0),
            ("stars", "Nube que guía de día", "Éxodo 13:21", 0, 2),
        ],
        "obstacles": [
            ("back", "Tormenta de arena", "Éxodo 15:22", 2),
            ("back", "Sed del desierto", "Éxodo 17:1-3", 3),
            ("skip", "Quejas del pueblo", "Éxodo 16:2-3", 0),
            ("back", "Ataque de Amalec", "Éxodo 17:8", 2),
        ],
    })

# 5. Monte Sinaí ------------------------------------------------------------------
add_map(
    5, "monte_sinai", "Monte Sinaí", "Éxodo 19-20",
    "Dios desciende sobre el monte y entrega los diez mandamientos a Moisés.",
    "sinai", "rock",
    {"x": 16.0, "z": 6.0, "icon": "mountain"}, "desierto_sinai",
    {"stars": 30, "badge": "badge_sinai", "badge_name": "Testigo del Sinaí",
     "badge_text": "Subiste al monte donde Dios entregó su ley."},
    "mountain",
    {"sun_energy": 0.30, "ambient_energy": 0.26, "fog_density": 0.004, "sun_dir": [-0.35, 0.7, 0.4]},
    {"tile_a": "#cdc4b8", "tile_b": "#a99b8d", "frame": "#4a3d34", "ground": "#8c7a68",
     "sky_top": "#5b82bb", "sky_horizon": "#f4e7d2", "ambient": "#f1e7dd", "fog": "#e6dacd",
     "sun": "#ffe9c4", "props": []},
    specials={
        "rewards": [
            ("advance", "Nube de gloria", "Éxodo 24:15-16", 2),
            ("stars", "Tablas de la ley", "Éxodo 31:18", 0, 3),
            ("extra_roll", "Sonido de trompeta", "Éxodo 19:16", 0),
            ("advance", "Zarza que ardía", "Éxodo 3:2-4", 3),
        ],
        "obstacles": [
            ("back", "Temblor del monte", "Éxodo 19:18", 3),
            ("skip", "Truenos y relámpagos", "Éxodo 19:16", 0),
            ("back", "Límite del monte", "Éxodo 19:12", 2),
            ("back", "Becerro de oro", "Éxodo 32:1-4", 3),
        ],
    },
    seed=505, lad_span=(9, 28), snk_span=(10, 38))

# 6. Jerusalén --------------------------------------------------------------------
add_map(
    6, "jerusalen", "Jerusalén", "2 Samuel 5; 1 Reyes 6",
    "La ciudad de David, sus murallas y el templo que construyó Salomón.",
    "jerusalen", "city",
    {"x": 36.0, "z": -10.0, "icon": "temple"}, "monte_sinai",
    {"stars": 35, "badge": "badge_jerusalen", "badge_name": "Guardián de la Ciudad Santa",
     "badge_text": "Llegaste hasta el templo de Jerusalén."},
    "city",
    {"sun_energy": 0.27, "ambient_energy": 0.29, "fog_density": 0.003, "sun_dir": [-0.5, 0.62, 0.5]},
    {"tile_a": "#f1e7d1", "tile_b": "#d6c6a4", "frame": "#6b5638", "ground": "#c6af84",
     "sky_top": "#4a8bd0", "sky_horizon": "#f9e9c8", "ambient": "#fff3dc", "fog": "#f1e1bf",
     "sun": "#fff3d6", "props": []},
    specials={
        "rewards": [
            ("advance", "Cedros para el templo", "1 Reyes 5:6-10", 2),
            ("stars", "Oro de Salomón", "1 Reyes 10:14", 0, 3),
            ("advance", "Canto de los peregrinos", "Salmo 122:1", 3),
            ("extra_roll", "El arca en el templo", "1 Reyes 8:6", 0),
        ],
        "obstacles": [
            ("back", "Muralla en ruinas", "Nehemías 2:13-15", 3),
            ("back", "Ejército que cerca la ciudad", "2 Reyes 18:17", 2),
            ("skip", "Mercaderes en el templo", "Juan 2:14-16", 0),
            ("back", "Puertas quemadas", "Nehemías 2:13", 1),
        ],
    },
    seed=606, lad_span=(9, 30), snk_span=(10, 40))

# 7. Belén -------------------------------------------------------------------------
add_map(
    7, "belen", "Belén", "Lucas 2:1-20; Mateo 2:1-12",
    "En la ciudad de David nace Jesús; los pastores y los magos van a adorarlo.",
    "belen", "village",
    {"x": 56.0, "z": 2.0, "icon": "stable"}, "jerusalen",
    {"stars": 50, "badge": "badge_belen", "badge_name": "Seguidor de la Estrella",
     "badge_text": "Seguiste la estrella hasta el pesebre de Belén."},
    "night",
    {"sun_energy": 0.17, "ambient_energy": 0.27, "fog_density": 0.0055, "sun_dir": [0.4, 0.6, 0.5]},
    {"tile_a": "#e0d2ae", "tile_b": "#b9a27a", "frame": "#3d2d1f", "ground": "#38486a",
     "sky_top": "#0a1433", "sky_horizon": "#2f4382", "ambient": "#93a2d6", "fog": "#27355f",
     "sun": "#b9c8ff", "props": []},
    specials={
        "rewards": [
            ("advance", "Estrella de oriente", "Mateo 2:2", 3),
            ("extra_roll", "Canto de los ángeles", "Lucas 2:13-14", 0),
            ("stars", "Regalos de los magos", "Mateo 2:11", 0, 3),
            ("advance", "Pastores en vela", "Lucas 2:8-9", 2),
        ],
        "obstacles": [
            ("back", "Posada llena", "Lucas 2:7", 2),
            ("back", "Largo camino desde Nazaret", "Lucas 2:4-5", 1),
            ("skip", "Censo del emperador", "Lucas 2:1-3", 0),
            ("back", "Senda pedregosa", "Lucas 2:4", 3),
        ],
    },
    seed=707, lad_span=(9, 30), snk_span=(10, 40))


def compact(obj, indent=0):
    """JSON legible: los arreglos cortos de números y pares van en una sola línea."""
    pad = "  " * indent
    if isinstance(obj, dict):
        if not obj:
            return "{}"
        # Diccionarios simples (todos los valores escalares) en una línea si son cortos.
        if all(not isinstance(v, (dict, list)) for v in obj.values()):
            line = "{" + ", ".join("%s: %s" % (json.dumps(k, ensure_ascii=False), json.dumps(v, ensure_ascii=False))
                                   for k, v in obj.items()) + "}"
            if len(line) <= 110:
                return line
        items = []
        for k, v in obj.items():
            items.append("%s  %s: %s" % (pad, json.dumps(k, ensure_ascii=False), compact(v, indent + 1)))
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(obj, list):
        if not obj:
            return "[]"
        flat = all(not isinstance(v, (dict, list)) or (isinstance(v, list) and all(not isinstance(x, (dict, list)) for x in v))
                   for v in obj)
        if flat:
            line = "[" + ", ".join(json.dumps(v, ensure_ascii=False) for v in obj) + "]"
            if len(line) <= 120:
                return line
        items = ["%s  %s" % (pad, compact(v, indent + 1)) for v in obj]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(obj, ensure_ascii=False)


doc = {
    "schema_version": 2,
    "note": ("Catálogo de mapas bíblicos de la Etapa 3. Los 7 mundos son jugables; el orden del campo "
             "'unlock.requires' define el desbloqueo progresivo (el primero está abierto desde el inicio). "
             "'board' trae las escaleras, serpientes, casillas de desafío bíblico y casillas especiales "
             "(recompensas y obstáculos) de cada tablero. Las referencias bíblicas son pasajes reales; "
             "no se incluye texto de ninguna versión con derechos de autor."),
    "maps": MAPS,
}
with open(OUT, "w", encoding="utf-8") as f:
    f.write(compact(doc) + "\n")

for m in MAPS:
    b = m["board"]
    avg, med, mx = simulate(b["ladders"], b["snakes"])
    print("%-16s tiradas medias %.1f mediana %d máx %d | escaleras %s | serpientes %s" % (
        m["id"], avg, med, mx, b["ladders"], b["snakes"]))
    print("    desafíos %s" % b["challenge_tiles"])
    print("    recompensas %s obstáculos %s" % ([e["tile"] for e in b["rewards"]], [e["tile"] for e in b["obstacles"]]))
print("escrito", OUT)
