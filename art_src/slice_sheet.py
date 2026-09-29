"""바르코로 만든 마젠타 배경 스프라이트 시트를 잘라 개별 PNG로 저장한다.

python art_src/slice_sheet.py <시트.png> <출력 폴더> <열> <행> <이름1,이름2,...> [이름=표시폭 ...]

- 마젠타 배경을 지우고, 연결된 덩어리를 중심 위치로 칸에 배정한다 (칸 경계를 넘는 그림도 안 잘림).
- 표시폭을 주면 그 폭의 2배로 줄여 저장한다 (게임은 절반 크기로 그린다).
"""
import sys
from PIL import Image


def slice_sheet(src, outdir, cols, rows, names, widths):
    im = Image.open(src).convert("RGBA")
    W, H = im.size
    px = im.load()
    fg = bytearray(W * H)
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if (r + b) / 2 - g > 70 and r > 120 and b > 120:
                px[x, y] = (0, 0, 0, 0)
            else:
                fg[y * W + x] = 1
    label = [-1] * (W * H)
    comps = []
    for start in range(W * H):
        if not fg[start] or label[start] != -1:
            continue
        cid = len(comps)
        stack = [start]
        label[start] = cid
        pts = []
        while stack:
            i = stack.pop()
            pts.append(i)
            x, y = i % W, i // W
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H:
                        j = ny * W + nx
                        if fg[j] and label[j] == -1:
                            label[j] = cid
                            stack.append(j)
        comps.append(pts)
    cells = [[] for _ in names]
    for pts in comps:
        if len(pts) < 12:
            continue
        cx = sum(p % W for p in pts) / len(pts)
        cy = sum(p // W for p in pts) / len(pts)
        c = min(cols - 1, int(cx / (W / cols)))
        r = min(rows - 1, int(cy / (H / rows)))
        cells[r * cols + c].extend(pts)
    for k, n in enumerate(names):
        pts = cells[k]
        xs = [p % W for p in pts]
        ys = [p // W for p in pts]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        out = Image.new("RGBA", (x1 - x0 + 1, y1 - y0 + 1), (0, 0, 0, 0))
        op = out.load()
        for p in pts:
            r, g, b, a = px[p % W, p // W]
            if r > g + 40 and b > g + 40:  # 가장자리 마젠타 번짐
                r = g = b = min(r, g, b)
            op[p % W - x0, p // W - y0] = (r, g, b, a)
        if n in widths:
            w = widths[n] * 2
            out = out.resize((w, round(out.height * w / out.width)), Image.LANCZOS)
        out.save(f"{outdir}/{n}.png")
        print(n, out.size)


if __name__ == "__main__":
    src, outdir, cols, rows, names = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5].split(",")
    widths = {kv.split("=")[0]: int(kv.split("=")[1]) for kv in sys.argv[6:]}
    slice_sheet(src, outdir, cols, rows, names, widths)
