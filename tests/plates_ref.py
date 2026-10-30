"""The plate shading Kolam's shape tools must match, pixel for pixel: a
shape's shadow-side edge, its lit side, a shade band and the body, and an
optional printed pattern of dots. Kept here so the test needs no game."""


class Pic:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.g = [[0] * w for _ in range(h)]

    def plate(self, inside, mat, holes=False, dots=None):
        """Shade one plate given by inside(x, y) and lay it on. dots: a
        printed pattern (colour, every n across, every m down) in its body."""
        m = {(x, y) for y in range(self.h) for x in range(self.w) if inside(x + .5, y + .5)}
        edge, shade, base, lit = mat
        for x, y in m:
            if (x + 1, y) not in m or (x, y + 1) not in m:
                c = edge                                        # the shadow side's edge
            elif (x - 1, y) not in m or (x, y - 1) not in m:
                c = lit                                         # the lit side: no line at all
            elif (x - 1, y) not in m or (x, y - 1) not in m or (x - 2, y) not in m and (x, y - 2) not in m:
                c = lit
            elif (x + 2, y) not in m or (x, y + 2) not in m:
                c = shade
            else:
                c = base
                deep = all((x + dx, y + dy) in m for dx in (-2, 2) for dy in (-2, 2))
                if holes and deep and y % 4 == 1 and (x + (y // 4) * 2) % 5 in (0, 1):
                    c = 0
                if dots and (x + (y // dots[2]) * (dots[1] // 2)) % dots[1] == 0 and y % dots[2] == 0:
                    c = dots[0]
            self.g[y][x] = c

    def put(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.g[y][x] = c


def capsule(ax, ay, bx, by, r0, r1=None):
    """Inside a limb from (ax, ay) to (bx, by), r0 thick at a, r1 at b."""
    r1 = r0 if r1 is None else r1
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy or 1

    def inside(x, y):
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / L))
        px, py = ax + t * dx, ay + t * dy
        return (x - px) ** 2 + (y - py) ** 2 <= (r0 + (r1 - r0) * t) ** 2
    return inside


def poly(pts):
    def inside(x, y):
        c = False
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                c = not c
        return c
    return inside


