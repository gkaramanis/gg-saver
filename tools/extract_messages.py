#!/usr/bin/env python3
"""Pulls the warnings, messages, errors and deprecation notices out of ggplot2's R
sources and writes them as templates for the Warning rain scene.

Usage: extract_messages.py <ggplot2 source dir> <output dir>

Writes messages.txt and functions.txt. Messages whose inline {expressions}
have no sample value in VALUES are skipped and listed.
"""
import re
import sys
from pathlib import Path

CALLS = {"cli::cli_warn": "warn", "cli::cli_inform": "inform", "cli::cli_abort": "abort", "deprecate": "deprecate",
         "lifecycle::deprecate_warn": "deprecate", "lifecycle::deprecate_soft": "deprecate"}


def scan_call(src, start):
    """Returns the text between the parentheses opening at src[start]."""
    depth, i, n = 0, start, len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            j = i + 1
            while src[j] != c:
                j += 2 if src[j] == "\\" else 1
            i = j
        elif c == "#":
            while i < n and src[i] != "\n":
                i += 1
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
        i += 1
    raise ValueError("unbalanced call")


def split_args(body):
    """Splits a call body on its top-level commas."""
    args, depth, cur, i = [], 0, "", 0
    while i < len(body):
        c = body[i]
        if c in "\"'":
            j = i + 1
            while body[j] != c:
                j += 2 if body[j] == "\\" else 1
            cur += body[i:j + 1]
            i = j + 1
            continue
        if c == "#":
            while i < len(body) and body[i] != "\n":
                i += 1
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        if c == "," and depth == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        args.append(cur.strip())
    return args


STRING = re.compile(r'^(?:([A-Za-z.!*>v ]+|"[^"]*"|`[^`]*`)\s*=\s*)?("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')$', re.S)


def literal(arg):
    """Returns (bullet name, string) for a literal string argument, else None."""
    m = STRING.match(arg.strip())
    if not m:
        return None
    name = (m.group(1) or "").strip("\"` ")
    text = re.sub(r"\\\\\s*\n\s*", "", m.group(2)[1:-1])
    text = text.replace('\\"', '"').replace("\\'", "'").replace("\\n", " ").replace("\\\\", "\\")
    return name, re.sub(r"\s+", " ", text).strip()


def message_parts(arg):
    """The bullets of a cli message argument: a string or c(...) of strings."""
    arg = arg.strip()
    if arg.startswith("c(") and arg.endswith(")"):
        parts = [literal(a) for a in split_args(arg[2:-1])]
    else:
        parts = [literal(arg)]
    if not parts or parts[0] is None:
        return None
    return [p for p in parts if p is not None]


def calls(src):
    for name, kind in CALLS.items():
        for m in re.finditer(r"(?<![\w:.])" + re.escape(name) + r"\(", src):
            yield kind, split_args(scan_call(src, m.end() - 1))


def extract(root):
    out = []
    for path in sorted(Path(root, "R").glob("*.R")):
        src = path.read_text()
        for kind, args in calls(src):
            positional = [a for a in args if not re.match(r"^[\w.]+\s*=[^=]", a)]
            if kind == "deprecate":
                plain = [re.sub(r'^I\((.*)\)$', r"\1", a.strip(), flags=re.S) for a in positional[:3]]
                lits = [literal(a) for a in plain]
                ok = len(lits) >= 2 and all(lits) and re.fullmatch(r"[\d.]+", lits[0][1])
                if ok:
                    is_i = [a.strip().startswith("I(") for a in positional[:3]]
                    out.append(("deprecate", path.name, [l[1] for l in lits], is_i))
            elif positional:
                parts = message_parts(positional[0])
                if parts:
                    out.append((kind, path.name, parts, None))
    return out


# ---- rendering ---------------------------------------------------------------

# Sample values for the inline expressions, by file then globally. A string
# list gives alternatives, and each one makes a variant of the message. A list
# of lists gives vectors, which cli collapses and counts for plurals. N is a
# row count the screensaver picks each time it shows the message.
N = "N"
VALUES = {
    "*": {
        "n": N, "sum(missing)": N, "sum(remove)": N, "sum(dups)": N, "sum(!kept)": N,
        "data$group[1]": N,
        "snake_class(self)": ["geom_point", "geom_line", "geom_bar", "geom_text"],
        "s": ["s"],
        "format(x)": ["data$x"], "good_usage": ["x"],
        "unique0(duplicated_names)": [["colour"]],
        "geom": ["abline"], "paste0('geom_', geom)": ["geom_abline"],
        "reject": [["position", "stat"]],
        "fun": ["after_stat"],
        "coord_name": ["coord_cartesian"], "var": ["xmin"], "alt": ["ymin"],
        "guide_names": [["colour", "fill"]], "cli::qty(guide_names)": [["colour", "fill"]],
        "snake_class(guide)": ["guide_axis_logticks"], "primary": ["theta"],
        "guide$available_aes": [["x", "y"]],
        "axis": ["x", "y"], "strip": ["left"],
        "snake_class(coord)": ["coord_polar", "coord_radial"], "snake_class(GeomRect)": ["geom_rect"],
        "extra_param": [["linewdith"], ["colour", "fill"]],
        "double_defined": [["colour"], ["x", "y"]],
        "extra_aes": [["labels"], ["label", "family"]],
        "empty_aes": [["fill"]],
        "failed": [["fill"]],
        "missing_params": ["linewidth, alpha"], "stat": ["custom"],
        "incorrect": [["t", "r"]], "lens[lens != 1]": [["2", "4"]],
        "object_name": ["`theme_bw`"],
        "name": ["position_dodge", "position_stack"],
        "length(filename)": ["2"], "filename[1]": ["plot.png"],
        "dim_f[1]": ["7"], "dim_f[2]": ["7"], "units": ["in"],
        "obj_type_friendly(x)": ["a <POSIXct> object"],
        "class(x)": ["difftime", "hms"],
        "scale$aesthetics[1]": ["colour"], "scalename": ["x", "y", "colour"],
        "flipped_names(params$flipped_aes)$x": ["x"],
        "dropped": [["label"], ["weight"]],
        "extra": [["axis.text.z"]], "cli::qty(extra)": [["colour2"]],
        "to@name": ["element_line"], "label": ["a number"],
        "deparse(formula)": ["y ~ x"],
        "elname": ["axis.ticks.theta"], "element": ["legend.position.inside"],
        "opts[i]": ["ggplot2.discrete.colour"], "pals[i]": ["palette.colour.discrete"],
        "msg": [["method = 'loess'", "formula = 'y ~ x'"], ["formula = 'y ~ x'"]],
    },
    "coord-map.R": {"snake_class(self)": ["coord_map"]},
    "coord-polar.R": {"snake_class(self)": ["coord_polar"]},
    "geom-function.R": {"snake_class(self)": ["geom_function"]},
    "geom-path.R": {"snake_class(self)": ["geom_path", "geom_line"]},
    "geom-raster.R": {"snake_class(self)": ["geom_raster"]},
    "geom-ribbon.R": {"snake_class(self)": ["geom_ribbon", "geom_area"]},
    "geom-sf.R": {"snake_class(self)": ["geom_sf"]},
    "guide-axis.R": {"snake_class(self)": ["guide_axis"]},
    "stat-.R": {"snake_class(self)": ["stat_bin", "stat_density", "stat_summary"]},
    "stat-density-2d.R": {"snake_class(self)": ["stat_density_2d"]},
    "bin.R": {"fun": ["stat_bin"]},
    "make-constructor.R": {"geom": ["custom"]},
    "stat-chain.R": {"extra": [["bins"]]},
    "utilities.R": {"name": ["geom_point", "geom_line", "geom_bar", "geom_text", "geom_col", "stat_bin"],
                    "missing": [["x"], ["x", "y"]]},
    "aes-delayed-eval.R": {"class(x)[1]": ["function"], "class(expr)[1]": ["environment"]},
    "aes.R": {"x": ["fill"]},
    "annotate.R": {"details": ["x (3) and label (2)"]},
    "autolayer.R": {"class(object)[1]": ["lm", "data.frame"]},
    "autoplot.R": {"class(object)[[1]]": ["lm", "data.frame"]},
    "backports.R": {"fun": ["list2DF"], "getRversion()": ["3.6.3"]},
    "facet-.R": {"problems": [["PANEL"]], "reserved_names": [["PANEL", "ROW", "COL"]],
                 "names(vars)": [["cyl"], ["class", "drv"]]},
    "facet-grid-.R": {"dups": [["cyl"]]},
    "facet-labeller.R": {"paste0('.', attr(labels, 'type'))": [".rows"], "names(dots)": [["vs"]]},
    "facet-wrap.R": {"n": ["12"], "nrow * ncol": ["6"]},
    "fortify-map.R": {"obj_type_friendly(map_obj)": ["a list"]},
    "geom-.R": {"names(which(!good))": [["colour"], ["x", "fill"]]},
    "geom-point.R": {"bad_string": [["triangle"], ["squiggle", "star"]]},
    "geom-rect.R": {"fun": ["geom_rect"], "missing": [["xmin", "xmax", "width"]], "missing[!absent]": [["xmin"]]},
    "geom-ribbon.R": {"flipped_names(params$flipped_aes)$ymin": ["ymin"],
                      "flipped_names(params$flipped_aes)$ymax": ["ymax"],
                      "non_constant": [["fill"], ["colour", "alpha"]]},
    "ggproto.R": {"class(x)[[1]]": ["GeomCustom"]},
    "guides-.R": {"guide": ["legnd"]},
    "layer.R": {"subclass": ["Geom"], "name": ["geom_pont"], "argname": ["geom"], "x": ["pont"]},
    "margins.R": {"x_arg": ["margin"], "x": ["a number"]},
    "plot-build.R": {"step": ["computing aesthetics", "computing stat"], "ordinal(i)": ["1st", "2nd"]},
    "save.R": {"path": ["~/plots/figs"], "filename": ["myplot"], "device": ["jpg2"]},
    "scale-colour.R": {"aesthetic": ["colour"], "scale$aesthetics": [["fill"]], "scale_types[1]": ["continuous"],
                       "scale_types[2]": ["discrete"], "scale": ["rainbow"]},
    "scale-discrete-.R": {"length(limits)": ["8"]},
    "scale-manual.R": {"n": ["5"], "length(values)": ["3"]},
    "stat-bin.R": {"x": ["x"], "snake_class(self)": ["stat_bin"]},
    "stat-connect.R": {"connection": ["a string"], "extra": [""]},
    "stat-density.R": {"obj_type_friendly(bw)": ["a negative number"]},
    "stat-qq-line.R": {"line.p": ["0.25"]},
    "stat-ydensity.R": {"bw": ["silverman"]},
    "theme-elements.R": {"extra": [["colour2"]], "arg": ["element_tree"], "bad_fields": [["inherit"]],
                         "bad_parent": [["axis.text.q"]], "class_name": ["element_line"]},
    "theme.R": {"t2name": ["geom_point()"], "item": ["axis.text"], "class@name": ["element_text"],
                "ggplot_global$element_tree[[element]]$class": ["element_text"],
                "names(nullprops)[nullprops]": [["colour"]], "class(new)[1]": ["character"],
                "class(old)[1]": ["element_text"]},
    "utilities-help.R": {"x$val$name": ["GeomCustom"]},
    "utilities-lifecycle.R": {"what": ["`geom_label()`"], "edition": ["3rd"]},
}

# Warnings built with paste0(), written out here with ggplot2's wording, and
# how often each shows up relative to the rest.
EXTRA = [
    ("utilities.R", "Removed {sum(missing)} row{?s} containing missing values or values outside the scale range ({.fn {name}}).", 8),
    ("utilities.R", "Removed {sum(missing)} row{?s} containing non-finite values or values outside the scale range ({.fn {name}}).", 4),
    ("geom-path.R", "Removed {sum(!kept)} row{?s} containing missing values or values outside the scale range ({.fn {snake_class(self)}}).", 2),
]

# Verbose debugging output rather than messages a user meets.
SKIP = {"nothing (top level)", "{pnames}"}

BULLETS = {"i": "ℹ ", "x": "✖ ", "!": "! ", "v": "✔ ", "*": "• ", ">": "→ ", " ": "  ", "": ""}
TICK = {"fn", "fun", "arg", "code", "var", "envvar", "help", "topic"}


class Unknown(Exception):
    pass


def collapse(items, word="and"):
    if len(items) <= 1:
        return "".join(items)
    if len(items) == 2:
        return f"{items[0]} {word} {items[1]}"
    return ", ".join(items[:-1]) + f", {word} {items[-1]}"


def style(kind, text):
    if kind in ("fn", "fun"):
        return f"`{text}()`"
    if kind in TICK:
        return f"`{text}`"
    if kind == "cls":
        return f"<{text}>"
    if kind == "str":
        return f'"{text}"'
    if kind == "val":
        return text if re.fullmatch(r"-?[\d.]+|TRUE|FALSE|NULL", text) else f'"{text}"'
    return text


class Renderer:
    """Renders one cli string for one choice of sample values."""

    def __init__(self, file, choice):
        self.file, self.choice, self.qty, self.used = file, choice, None, set()
        self.ahead = []  # quantities in order of appearance

    def line(self, text):
        """Renders a bullet. A plural before any quantity uses the next one, as in cli."""
        dry = Renderer(self.file, self.choice)
        dry.render(text)
        self.ahead, self.qty = dry.ahead, None
        return re.sub(r"  +", " ", self.render(text))

    def note(self, q):
        self.ahead.append(q)
        return q

    def value(self, expr):
        table = {**VALUES["*"], **VALUES.get(self.file, {})}
        if expr not in table:
            raise Unknown(expr)
        self.used.add(expr)
        v = table[expr]
        return v if v == N else v[self.choice.get(expr, 0)]

    def braces(self, text, i):
        depth, j = 0, i
        while j < len(text):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    return text[i + 1:j], j + 1
            j += 1
        raise Unknown("unbalanced: " + text)

    def render(self, text):
        out, i = "", 0
        while i < len(text):
            c = text[i]
            if text.startswith("{{", i) or text.startswith("}}", i):
                out += c
                i += 2
                continue
            if c != "{":
                out += c
                i += 1
                continue
            inner, i = self.braces(text, i)
            out += self.expand(inner)
        return out

    def plural(self, forms):
        forms = forms.split("/")
        one, many = ("", forms[0]) if len(forms) == 1 else (forms[-2], forms[-1])
        qty = self.qty if self.qty is not None else next(iter(self.ahead), None)
        if qty == N:
            return f"{{N?{one}|{many}}}"
        return one if qty == 1 else many

    def expand(self, inner):
        if inner.startswith("?"):
            return self.plural(inner[1:])
        if inner.startswith("."):
            kind, _, content = inner[1:].partition(" ")
            return self.styled(kind, content)
        if inner.startswith("cli::qty("):
            v = self.value(inner)
            self.qty = self.note(N if v == N else len(v))
            return ""
        v = self.value(inner)
        if v == N:
            self.qty = self.note(N)
            return "{N}"
        if isinstance(v, list):
            self.qty = self.note(len(v))
            return collapse(v)
        self.qty = self.note(1)
        return v

    def styled(self, kind, content):
        if kind in ("and", "or"):
            m = re.fullmatch(r"\{\.(\w+) \{([^{}]+)\}\}|\{([^{}]+)\}", content)
            if not m:
                raise Unknown(content)
            sub, expr = (m.group(1), m.group(2)) if m.group(1) else (None, m.group(3))
            v = self.value(expr)
            items = v if isinstance(v, list) else [v]
            self.qty = self.note(len(items))
            return collapse([style(sub, x) if sub else x for x in items], kind)
        m = re.fullmatch(r"\{([^{}]+)\}", content)
        if m and not m.group(1).startswith((".", "?")):
            v = self.value(m.group(1))
            if v == N:
                self.qty = self.note(N)
                return "{N}"
            if isinstance(v, list):
                self.qty = self.note(len(v))
                return collapse([style(kind, x) for x in v])
            self.qty = self.note(1)
            return style(kind, v)
        return style(kind, self.render(content))


def variants(file, parts):
    """Every rendering of a message across its alternative sample values."""
    first = Renderer(file, {})
    lines = [(n, first.line(t)) for n, t in parts]
    table = {**VALUES["*"], **VALUES.get(file, {})}
    choices = [e for e in sorted(first.used) if table[e] != N and len(table[e]) > 1]
    if not choices:
        return [lines]
    out = []
    for k in range(max(len(table[e]) for e in choices)):
        r = Renderer(file, {e: min(k, len(table[e]) - 1) for e in choices})
        out.append([(n, r.line(t)) for n, t in parts])
    return out


def deprecation(when, texts, is_i):
    """lifecycle's wording for a deprecate(when, what, with) call."""
    what, with_ = texts[0], texts[1] if len(texts) > 1 else None
    tick = lambda s: s if s.startswith("`") else f"`{s}`"
    m = re.fullmatch(r"([\w.:]+)\(([\w.]+)\)", what)
    if is_i[0]:
        line = f"{what} was deprecated in ggplot2 {when}."
    elif m:
        line = f"The `{m.group(2)}` argument of `{m.group(1)}()` is deprecated as of ggplot2 {when}."
    elif re.fullmatch(r"[\w.:]+\(\)", what):
        line = f"{tick(what)} was deprecated in ggplot2 {when}."
    else:
        return None
    if with_ is None:
        return [("", line)]
    w = re.fullmatch(r"([\w.:]+)\(([\w.]+)\)", with_)
    if len(is_i) > 1 and is_i[1]:
        hint = f"Please use {with_} instead."
    elif w and m and w.group(1) == m.group(1):
        hint = f"Please use the `{w.group(2)}` argument instead."
    elif re.fullmatch(r"[\w.:]+\(.*\)", with_):
        hint = f"Please use {tick(with_)} instead."
    else:
        return None
    return [("", line), ("i", hint)]


def functions(root):
    """ggplot2's exported functions, from its NAMESPACE."""
    names = re.findall(r"^export\(\"?([^\")]+)\"?\)", Path(root, "NAMESPACE").read_text(), re.M)
    return sorted(n for n in set(names) if re.fullmatch(r"[a-z][\w.]*", n))


def main(root, out_dir):
    found = extract(root)
    found += [("warn", f, [("", t)], w) for f, t, w in EXTRA]
    groups, unknown, seen = [], {}, set()
    for kind, file, parts, extra in found:
        if parts and parts[0][1] in SKIP:
            continue
        if kind == "deprecate":
            texts, is_i = parts, extra
            when = texts[0]
            if tuple(int(x) for x in when.split(".")[:2]) < (3, 0):
                continue  # defunct: an error, not a warning
            lines = deprecation(when, texts[1:], is_i[1:])
            if lines:
                groups.append((1, [lines], ""))
            continue
        weight = extra if kind == "warn" and isinstance(extra, int) else 1
        try:
            groups.append((weight, variants(file, parts), "Error: " if kind == "abort" else ""))
        except Unknown as e:
            unknown[str(e)] = file
    out, n = [], 0
    for weight, vs, prefix in groups:
        texts = []
        for v in vs:
            t = prefix + "  ".join(BULLETS.get(name, "") + text for name, text in v)
            if t not in seen:
                seen.add(t)
                texts.append(t)
        if texts:
            out.append("\t".join([str(weight)] + texts))
            n += 1
    out_dir = Path(out_dir)
    (out_dir / "functions.txt").write_text(
        "# ggplot2's exported functions for the Warning rain scene.\n"
        "# Written by tools/extract_messages.py, in the same format as messages.txt.\n"
        + "".join(f"1\t{f}()\n" for f in functions(root)))
    (out_dir / "messages.txt").write_text(
        "# ggplot2 warnings, messages and errors for the Warning rain scene.\n"
        "# Written by tools/extract_messages.py. Each line: weight, then tab-separated\n"
        "# variants. {N} is a row count, {N?one|many} agrees with it.\n"
        + "\n".join(out) + "\n")
    for e, f in unknown.items():
        print(f"skipped, no value for {{{e}}} in {f}", file=sys.stderr)
    print(f"{n} messages", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
