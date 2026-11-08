"""Convert decompiled Minecraft 1.x ModelBase classes into Rust EntityModelSpec builders for the b173 mod loader.

Reads the constructor of each model class: ModelRenderer creation, addBox, setRotationPoint, setTextureSize,
setTextureOffset, mirror, rotation and pivot assignments, addChild. Understands SRG names (1.7.10 jars) and MCP names.
Animation code is not converted, port setRotationAngles and render by hand into the entity's pose callback.

    python3 -I convert_models.py --out models.rs Model.java [Other.java ...] [--arg Model.scale=0.0]

Each class becomes `pub mod <snake name>` with one u16 const per part and `pub fn model() -> EntityModelSpec`.
The output expects `fn part(...)` and `fn cuboid(...)` from the mod's own models module (see templates below).
"""

import argparse
import math
import re
import sys
from pathlib import Path

# SRG name to meaning for the calls and fields models use
CALLS = {
    "func_78790_a": "addBox",
    "func_78789_a": "addBox",
    "addBox": "addBox",
    "func_78793_a": "setRotationPoint",
    "setRotationPoint": "setRotationPoint",
    "func_78787_b": "setTextureSize",
    "setTextureSize": "setTextureSize",
    "func_78784_a": "setTextureOffset",
    "setTextureOffset": "setTextureOffset",
    "func_78792_a": "addChild",
    "func_78786_a": "addNamedBox",
    "addChild": "addChild",
}
FIELDS = {
    "field_78809_i": "mirror",
    "mirror": "mirror",
    "field_78795_f": "rotateX",
    "rotateAngleX": "rotateX",
    "field_78796_g": "rotateY",
    "rotateAngleY": "rotateY",
    "field_78808_h": "rotateZ",
    "rotateAngleZ": "rotateZ",
    "field_78800_c": "pivotX",
    "rotationPointX": "pivotX",
    "field_78797_d": "pivotY",
    "rotationPointY": "pivotY",
    "field_78798_e": "pivotZ",
    "rotationPointZ": "pivotZ",
}
TEXTURE_FIELDS = {"field_78090_t": 0, "textureWidth": 0, "field_78089_u": 1, "textureHeight": 1}

# parts ModelBiped and ModelQuadruped create before a subclass constructor runs, 1.7.10 values
BIPED = [
    ("field_78116_c", "head", (0, 0), [((-4, -8, -4), (8, 8, 8))], (0, 0, 0)),
    ("field_78114_d", "headwear", (32, 0), [((-4, -8, -4), (8, 8, 8))], (0, 0, 0)),
    ("field_78115_e", "body", (16, 16), [((-4, 0, -2), (8, 12, 4))], (0, 0, 0)),
    ("field_78112_f", "right_arm", (40, 16), [((-3, -2, -2), (4, 12, 4))], (-5, 2, 0)),
    ("field_78113_g", "left_arm", (40, 16), [((-1, -2, -2), (4, 12, 4))], (5, 2, 0)),
    ("field_78123_h", "right_leg", (0, 16), [((-2, 0, -2), (4, 12, 4))], (-1.9, 12, 0)),
    ("field_78124_i", "left_leg", (0, 16), [((-2, 0, -2), (4, 12, 4))], (1.9, 12, 0)),
]
BIPED_MIRRORED = {"field_78113_g", "field_78124_i"}

# ModelQuadruped(height, scale): field, name, uv, box origin and size as functions of height, pivot
def quadruped(height):
    return [
        ("field_78150_a", "head", (0, 0), (-4, -4, -8), (8, 8, 8), (0, 18 - height, -6)),
        ("field_78148_b", "body", (28, 8), (-5, -10, -7), (10, 16, 8), (0, 17 - height, 2)),
        ("field_78149_c", "leg1", (0, 16), (-2, 0, -2), (4, height, 4), (-3, 24 - height, 7)),
        ("field_78146_d", "leg2", (0, 16), (-2, 0, -2), (4, height, 4), (3, 24 - height, 7)),
        ("field_78147_e", "leg3", (0, 16), (-2, 0, -2), (4, height, 4), (-3, 24 - height, -5)),
        ("field_78144_f", "leg4", (0, 16), (-2, 0, -2), (4, height, 4), (3, 24 - height, -5)),
    ]

NUMBER = re.compile(r"(?<![\w.])(\d+\.\d*|\.\d+|\d+)[FfDdL]\b")
CAST = re.compile(r"\((?:float|double|int|byte|short|long)\)\s*")


class Part:
    def __init__(self, name, uv, size):
        self.name = name
        self.uv = list(uv)
        self.size = list(size)
        self.box_uv = None
        self.mirror = False
        self.pivot = [0.0, 0.0, 0.0]
        self.rotation = [0.0, 0.0, 0.0]
        self.boxes = []
        self.parent = None


def snake(name):
    name = re.sub(r"Model$", "", name)
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


class Converter:
    def __init__(self, cls, args):
        self.cls = cls
        self.env = {"Math": math, "PI": math.pi, "true": True, "false": False}
        self.env.update(args)
        self.texture = [64, 32]
        self.parts = {}
        self.order = []
        self.aliases = {}
        self.named = {}
        self.boxNames = {}

    def value(self, text):
        text = CAST.sub("", text.strip())
        text = NUMBER.sub(r"\1", text)
        text = text.replace("Math.PI", "math.pi").replace("(float) Math.PI", "math.pi").replace("this.", "")
        text = re.sub(r"\bMathHelper\.func_76126_a\b|\bMathHelper\.sin\b", "math.sin", text)
        text = re.sub(r"\bMathHelper\.func_76134_b\b|\bMathHelper\.cos\b", "math.cos", text)
        try:
            return eval(text, {"__builtins__": {}, "math": math}, self.env)
        except Exception as error:
            raise ValueError(f"{self.cls}: cannot evaluate '{text}': {error}")

    def part(self, ref):
        ref = ref.replace("this.", "").strip()
        ref = self.aliases.get(ref, ref)
        if ref not in self.parts:
            raise ValueError(f"{self.cls}: unknown part {ref}")
        return self.parts[ref]

    def new(self, field, uv, name=None):
        # a field assigned again replaces its part in place, keeping the friendly name a base class gave it
        existing = self.parts.get(field)
        part = Part(name or (existing.name if existing else field), uv, self.texture)
        self.parts[field] = part
        if not existing:
            self.order.append(field)

    def base(self, kind, args):
        if kind == "quadruped":
            height = int(self.value(args[0]))
            inflate = float(self.value(args[1])) if len(args) > 1 else 0.0
            for field, name, uv, origin, size, pivot in quadruped(height):
                self.new(field, uv, name)
                self.parts[field].boxes.append((list(map(float, origin)), list(size), inflate, None))
                self.parts[field].pivot = list(map(float, pivot))
            return
        if kind == "biped":
            inflate = self.value(args[0]) if args else 0.0
            for field, name, uv, boxes, pivot in BIPED:
                self.new(field, uv, name)
                part = self.parts[field]
                part.mirror = field in BIPED_MIRRORED
                inflate_here = inflate + 0.5 if name == "headwear" else inflate
                for origin, size in boxes:
                    part.boxes.append((list(map(float, origin)), list(size), inflate_here, None))
                part.pivot = list(map(float, pivot))

    def indexed(self, line):
        # thorn[i] becomes thorn_3 with the loop variable's current value
        return re.sub(r"(\w+)\[([^\]]+)\]", lambda m: f"{m.group(1)}_{int(self.value(m.group(2)))}", line)

    def run(self, statements):
        index = 0
        while index < len(statements):
            line = statements[index]
            loop = re.match(r"for \(int (\w+) = ([^;]+); \1 < ([^;]+); \1\+\+\) \{$", line)
            if loop:
                depth, body, index = 1, [], index + 1
                while depth:
                    nested = statements[index]
                    depth -= nested.startswith("}")
                    depth += nested.endswith("{")
                    if depth:
                        body.append(nested)
                    index += 1
                for value in range(int(self.value(loop.group(2))), int(self.value(loop.group(3)))):
                    self.env[loop.group(1)] = value
                    self.run(body)
                continue
            branch = re.match(r"if \((.+)\) \{$", line)
            if branch:
                taken, skipping, depth, index = bool(self.value(condition(branch.group(1)))), False, 1, index + 1
                chosen = []
                while depth:
                    nested = statements[index]
                    if depth == 1 and nested == "} else {":
                        skipping = True
                        index += 1
                        continue
                    depth -= nested.startswith("}")
                    depth += nested.endswith("{")
                    if depth and (taken != skipping):
                        chosen.append(nested)
                    index += 1
                self.run(chosen)
                continue
            self.statement(line)
            index += 1

    def statement(self, line):
        line = line.strip().rstrip(";")
        if re.search(r"new ModelRenderer\[", line) or line in ("}", "{"):
            return
        line = self.indexed(line)
        helper = re.match(r"(?:this\.)?(?:setRotation|setRotateAngle|setRotationAngle)\((?:this\.)?(\w+),\s*(.+)\)$", line)
        if helper:
            self.part(helper.group(1)).rotation = [float(self.value(a)) for a in split(helper.group(2))]
            return
        if not line or line.startswith("//") or line.startswith("super("):
            return
        local = re.match(r"(?:final\s+)?(?:byte|int|float|double|short)\s+(\w+)\s*=\s*(.+)$", line)
        if local:
            self.env[local.group(1)] = self.value(local.group(2))
            return
        texture = re.match(r"(?:this\.)?(\w+)\s*=\s*(.+)$", line)
        if texture and texture.group(1) in TEXTURE_FIELDS:
            self.texture[TEXTURE_FIELDS[texture.group(1)]] = int(self.value(texture.group(2)))
            return
        named = re.match(r'(?:this\.)?(\w+)\s*=\s*new ModelRenderer\(this,\s*"(\w+)"\)$', line)
        if named:
            self.new(named.group(1), (0, 0))
            self.boxNames[named.group(1)] = named.group(2)
            return
        offset = re.match(r'(?:this\.)?func_78085_a\("([\w.]+)",\s*([^,]+),\s*([^)]+)\)$', line)
        if offset:
            self.named[offset.group(1)] = [int(self.value(offset.group(2))), int(self.value(offset.group(3)))]
            return
        create = re.match(r"(?:this\.)?(\w+)\s*=\s*new ModelRenderer\(this(?:,\s*([^,]+),\s*([^)]+))?\)$", line)
        if create:
            uv = (int(self.value(create.group(2))), int(self.value(create.group(3)))) if create.group(2) else (0, 0)
            self.new(create.group(1), uv)
            return
        alias = re.match(r"(?:this\.)?(\w+)\s*=\s*(?:this\.)?(\w+)$", line)
        if alias and alias.group(2) in self.parts:
            self.aliases[alias.group(1)] = alias.group(2)
            return
        call = re.match(r"(?:this\.)?([\w.]+?)\.(\w+)\((.*)\)$", line)
        if call and CALLS.get(call.group(2)):
            part = self.part(call.group(1))
            args = split(call.group(3))
            kind = CALLS[call.group(2)]
            if kind == "addBox":
                origin = [float(self.value(a)) for a in args[0:3]]
                size = [int(self.value(a)) for a in args[3:6]]
                inflate = float(self.value(args[6])) if len(args) > 6 else 0.0
                part.boxes.append((origin, size, inflate, part.box_uv))
            elif kind == "addNamedBox":
                field = next(key for key, value in self.parts.items() if value is part)
                uv = self.named.get(f"{self.boxNames.get(field, field)}.{args[0].strip().strip(chr(34))}")
                origin = [float(self.value(a)) for a in args[1:4]]
                size = [int(self.value(a)) for a in args[4:7]]
                part.boxes.append((origin, size, 0.0, uv))
            elif kind == "setRotationPoint":
                part.pivot = [float(self.value(a)) for a in args]
            elif kind == "setTextureSize":
                part.size = [int(self.value(a)) for a in args]
            elif kind == "setTextureOffset":
                part.box_uv = [int(self.value(a)) for a in args]
            elif kind == "addChild":
                self.part(args[0]).parent = part.name
            return
        step = re.match(r"(.+)(\+\+|--)$", line)
        if step:
            line = f"{step.group(1)} {'+' if step.group(2) == '++' else '-'}= 1"
        assign = re.match(r"(?:this\.)?([\w.]+?)\.(\w+)\s*([+\-*]?=)\s*(.+)$", line)
        if assign and assign.group(2) in FIELDS:
            part = self.part(assign.group(1))
            target = FIELDS[assign.group(2)]
            value = self.value(assign.group(4))
            op = assign.group(3)
            if target == "mirror":
                part.mirror = bool(value)
                return
            vector, index = (part.rotation, "XYZ".index(target[-1])) if target.startswith("rotate") else (part.pivot, "XYZ".index(target[-1]))
            current = vector[index]
            vector[index] = value if op == "=" else current + value if op == "+=" else current - value if op == "-=" else current * value
            return
        if not re.match(r"(?:this\.)?field_78117_n\s*=", line):
            print(f"warning {self.cls}: skipped `{line}`", file=sys.stderr)


def condition(text):
    return text.replace("&&", " and ").replace("||", " or ").replace("!=", " != ").replace("!", " not ").replace(" not =", "!=")


def split(args):
    depth, current, out = 0, "", []
    for char in args:
        if char == "," and depth == 0:
            out.append(current)
            current = ""
            continue
        depth += char == "("
        depth -= char == ")"
        current += char
    if current.strip():
        out.append(current)
    return out


def constructor(source, cls):
    # the constructor doing the work, a this(...) delegate is skipped for the overload it calls
    matches = list(re.finditer(r"public " + cls + r"\(([^)]*)\)\s*\{", source))
    if not matches:
        raise ValueError(f"no constructor in {cls}")
    match = max(matches, key=lambda found: source.count(";", found.end(), source.find("\n   }", found.end())))
    start = match.end()
    depth, index = 1, start
    while depth:
        depth += source[index] == "{"
        depth -= source[index] == "}"
        index += 1
    body = source[start:index - 1]
    params = [p.split()[-1] for p in match.group(1).split(",") if p.strip()]
    statements, current = [], ""
    for line in body.splitlines():
        current += " " + line.strip()
        if current.strip().endswith(";") or current.strip().endswith("{") or current.strip().endswith("}"):
            statements.append(current.strip())
            current = ""
    return params, statements


def rust_float(value):
    text = repr(float(value))
    return text if "e" not in text else f"{float(value):.8f}"


def emit(converter, out):
    module = snake(converter.cls)
    out.append(f"// generated by tools/modport/convert_models.py from {converter.cls}.java")
    out.append(f"pub mod {module}")
    out.append("{")
    out.append("    use crate::models::{cuboid, part};")
    out.append("    use b173_api::EntityModelSpec;")
    out.append("")
    for index, field in enumerate(converter.order):
        name = converter.parts[field].name
        out.append(f"    pub const {re.sub(r'(?<!^)(?=[A-Z])', '_', name).upper()}: u16 = {index};")
    count = len(converter.order)
    pivots = ", ".join("[" + ", ".join(map(rust_float, converter.parts[field].pivot)) + "]" for field in converter.order)
    rotations = ", ".join("[" + ", ".join(map(rust_float, converter.parts[field].rotation)) + "]" for field in converter.order)
    out.append(f"    // rest pivots and rotations by part, what a setRotationAngles body starts from")
    out.append(f"    pub const PIVOTS: [[f32; 3]; {count}] = [{pivots}];")
    out.append(f"    pub const ROTATIONS: [[f32; 3]; {count}] = [{rotations}];")
    out.append("")
    out.append("    pub fn model() -> EntityModelSpec")
    out.append("    {")
    out.append("        EntityModelSpec {")
    out.append(f"            texture_size: [{converter.texture[0]}, {converter.texture[1]}],")
    out.append("            parts: vec![")
    for field in converter.order:
        p = converter.parts[field]
        boxes = ", ".join(
            f"cuboid([{', '.join(map(rust_float, o))}], [{', '.join(map(str, s))}], {rust_float(i)}, "
            + (f"Some([{uv[0]}, {uv[1]}])" if uv else "None")
            + ")"
            for o, s, i, uv in p.boxes
        )
        parent = f'Some("{converter.parts[p.parent].name if p.parent in converter.parts else p.parent}")' if p.parent else "None"
        size = f"Some([{p.size[0]}, {p.size[1]}])" if p.size != converter.texture else "None"
        out.append(
            f'                part("{p.name}", {parent}, [{p.uv[0]}, {p.uv[1]}], {str(p.mirror).lower()}, '
            f"[{', '.join(map(rust_float, p.pivot))}], [{', '.join(map(rust_float, p.rotation))}], vec![{boxes}], {size}),"
        )
    out.append("            ],")
    out.append("            ..EntityModelSpec::default()")
    out.append("        }")
    out.append("    }")
    out.append("}")
    out.append("")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--out", required=True)
    parser.add_argument("--arg", action="append", default=[], help="Class.param=value for constructor parameters")
    options = parser.parse_args()
    args = {}
    for item in options.arg:
        key, value = item.split("=", 1)
        cls, param = key.split(".")
        args.setdefault(cls, {})[param] = float(value)
    out = []
    for file in options.files:
        source = Path(file).read_text(encoding="utf-8")
        cls = Path(file).stem
        params, statements = constructor(source, cls)
        converter = Converter(cls, {param: args.get(cls, {}).get(param, 0.0) for param in params})
        extends = re.search(r"class " + cls + r" extends (\w+)", source)
        if extends and extends.group(1) == "ModelBiped":
            converter.base("biped", [])
        superCall = next((statement for statement in statements if statement.startswith("super(")), None)
        if extends and extends.group(1) == "ModelQuadruped" and superCall:
            converter.base("quadruped", split(superCall[len("super("):superCall.rindex(")")]))
        for initializer in re.findall(r"^   (?:public |private |protected )?ModelRenderer (\w+ = new ModelRenderer\([^;]*\));", source, re.M):
            converter.statement(initializer)
        converter.run([statement for statement in statements if not statement.startswith("super(")])
        emit(converter, out)
    Path(options.out).write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {len(options.files)} models to {options.out}")


if __name__ == "__main__":
    main()
