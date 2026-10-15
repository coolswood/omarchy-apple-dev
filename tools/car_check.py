"""Offline structural check of an Assets.car, on Linux with the standard library only.

Apple's `assetutil --validate-file` is the oracle. Two defects of AssetKit-built cars made it fail, and
`assetutil --info` accepted both, so a successful parse proves nothing:

* BITMAPKEYS. Apple recomputes each asset's 52-byte descriptor from the asset's renditions and reports
  `invalid bitmapindex` on any difference. Every variable field is the OR of `1 << token` over the
  renditions' key tokens of one KEYFORMAT attribute (the scale mask sits in header slot 6). Xcode's actool
  writes exactly this for all 147 rows of the IceCubes root catalog.
* Image blocks. The TVL 1007 stride must equal the byte width of the rows in the MLEC/KCBC chunks. A
  16-byte-aligned stride over unpadded rows gave `early EOF ... at row N` and `Image data corrupted`.

`check_car` returns a list of problems; an empty list means the car passed every check here. It does not
prove that Apple accepts the car: pass the same checks over Apple's actool output of the same catalog to
see what a passing car looks like.
"""
import struct
import zipfile

MAX_PER_KIND = 3


class CarError(Exception):
    pass


class _Bom:
    """Minimal reader for the BOMStore container (all fields big endian)."""

    def __init__(self, data):
        self.data = data
        if data[:8] != b"BOMStore":
            raise CarError("not a BOMStore file")
        _version, _count, index_off, index_len, vars_off, vars_len = struct.unpack(">6I", data[8:32])
        if index_off + 4 > len(data) or vars_off + 4 > len(data):
            raise CarError("BOM header points past the end of the file")
        n = struct.unpack(">I", data[index_off:index_off + 4])[0]
        if index_off + 4 + 8 * n > len(data):
            raise CarError(f"BOM index declares {n} entries but the file ends inside the index table")
        self.blocks = [struct.unpack(">2I", data[index_off + 4 + 8 * i:index_off + 12 + 8 * i]) for i in range(n)]
        # Unused slots: (0, 0) from actool, (offset, 0) from AssetKit, (0xFFFFFFFF, 0xFFFFFFFF) after assetutil -U.
        for i, (off, length) in enumerate(self.blocks):
            if length and off != 0xFFFFFFFF and off + length > len(data):
                raise CarError(f"BOM block {i} ends at {off + length}, past the file end {len(data)}")
        count = struct.unpack(">I", data[vars_off:vars_off + 4])[0]
        pos, self.vars = vars_off + 4, {}
        for _ in range(count):
            if pos + 5 > len(data):
                raise CarError("BOM variable table is truncated")
            index, length = struct.unpack(">IB", data[pos:pos + 5])
            self.vars[data[pos + 5:pos + 5 + length].decode("latin1")] = index
            pos += 5 + length
        if vars_len and pos - vars_off > vars_len:
            raise CarError("BOM variable table is longer than its declared size")

    def block(self, index):
        off, length = self.blocks[index]
        return self.data[off:off + length]

    def leaves(self, name):
        """(key slot, value block index) of every entry of the named tree, in order."""
        head = self.block(self.vars[name])
        if head[:4] != b"tree":
            raise CarError(f"{name} is not a tree")
        node, out, seen = struct.unpack(">I", head[8:12])[0], [], set()
        while True:
            if node in seen:
                raise CarError(f"{name} tree loops")
            seen.add(node)
            b = self.block(node)
            is_leaf, count, forward, _back = struct.unpack(">HHII", b[:12])
            if not is_leaf:
                node = struct.unpack(">I", b[12:16])[0]
                continue
            out += [(ki, vi) for vi, ki in (struct.unpack(">II", b[12 + 8 * i:20 + 8 * i]) for i in range(count))]
            if forward == 0:
                return out
            node = forward


def _lzfse_raw_size(stream):
    """Bytes a LZFSE stream decodes to, from its block headers, or None for a block kind not read here."""
    pos, total = 0, 0
    while pos + 4 <= len(stream):
        magic = stream[pos:pos + 4]
        if magic == b"bvx$":
            return total
        if magic == b"bvx-":
            n = struct.unpack_from("<I", stream, pos + 4)[0]
            total, pos = total + n, pos + 8 + n
        elif magic == b"bvxn":
            n_raw, n_payload = struct.unpack_from("<2I", stream, pos + 4)
            total, pos = total + n_raw, pos + 12 + n_payload
        elif magic == b"bvx2":
            n_raw = struct.unpack_from("<I", stream, pos + 4)[0]
            p0, p1, p2 = struct.unpack_from("<3Q", stream, pos + 8)
            header_size = p2 & 0xFFFFFFFF
            n_literal_bytes, n_lmd_bytes = (p0 >> 20) & 0xFFFFF, (p1 >> 40) & 0xFFFFF
            total, pos = total + n_raw, pos + header_size + n_literal_bytes + n_lmd_bytes
        else:
            return None
    return None


def _key_format(bom):
    block = bom.block(bom.vars["KEYFORMAT"])
    n = struct.unpack_from("<I", block, 8)[0]
    return struct.unpack_from(f"<{n}I", block, 12)


def _check_bitmap_keys(bom, problems):
    fmt = _key_format(bom)
    n = len(fmt)
    if 17 not in fmt or 12 not in fmt:
        problems.append("KEYFORMAT has no identifier or scale attribute")
        return
    ident_at, scale_at = fmt.index(17), fmt.index(12)
    masks = {}
    for key_block, _value in bom.leaves("RENDITIONS"):
        key = bom.block(key_block)
        tokens = struct.unpack(f"<{len(key) // 2}H", key)
        row = masks.setdefault(tokens[ident_at], [0] * n)
        for i, token in enumerate(tokens[:n]):
            if token < 32:
                row[i] |= 1 << token
    if "BITMAPKEYS" not in bom.vars:
        if masks:
            problems.append("no BITMAPKEYS tree although the car has renditions: assetutil reports invalid bitmapindex")
        return
    bad = 0
    for identifier, value in bom.leaves("BITMAPKEYS"):
        raw = bom.block(value)
        words = struct.unpack(f"<{len(raw) // 4}I", raw)
        row = masks.get(identifier)
        if row is None:
            bad += 1
            if bad <= MAX_PER_KIND:
                problems.append(f"BITMAPKEYS row for identifier {identifier} has no renditions")
            continue
        slots = max(0, n - 6)
        want = (1, 0, (n + 1) * 4, n, 0xFFFFFFFF, 1, row[scale_at], *row[3:3 + slots], 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF)
        if words != want:
            bad += 1
            if bad <= MAX_PER_KIND:
                diff = [(i, w, g) for i, (w, g) in enumerate(zip(words, want)) if w != g]
                problems.append(f"BITMAPKEYS row for identifier {identifier} differs from its renditions "
                                f"(word index, stored, expected): {diff[:4]}")
    if bad > MAX_PER_KIND:
        problems.append(f"BITMAPKEYS: {bad} rows in all differ from their renditions")


def _tvl_stride(csi):
    """(stride from TVL 1007 or None, offset just past the TVL block)."""
    length = struct.unpack_from("<I", csi, 168)[0]
    end, pos, stride = 184 + length, 184, None
    while pos + 8 <= end:
        kind, size = struct.unpack_from("<2I", csi, pos)
        if kind == 1007 and size == 4:
            stride = struct.unpack_from("<I", csi, pos + 8)[0]
        pos += 8 + size
    return stride, end


def _check_image_blocks(bom, problems):
    bad = checked = 0
    for key_block, value in bom.leaves("RENDITIONS"):
        csi = bom.block(value)
        if csi[:4] != b"ISTC" or len(csi) < 188:
            continue
        height = struct.unpack_from("<I", csi, 16)[0]
        name = csi[40:168].split(b"\0")[0].decode(errors="replace")
        stride, body = _tvl_stride(csi)
        if stride is None or csi[body:body + 4] != b"MLEC" or csi[body + 16:body + 20] != b"KCBC":
            continue
        count = struct.unpack_from("<I", csi, body + 12)[0]
        pos, rows_total, problem = body + 16, 0, None
        for chunk in range(count):
            if csi[pos:pos + 4] != b"KCBC":
                problem = f"chunk {chunk} has no KCBC magic"
                break
            rows, size = struct.unpack_from("<2I", csi, pos + 12)
            raw = _lzfse_raw_size(csi[pos + 20:pos + 20 + size])
            if raw is not None and raw != rows * stride:
                problem = f"chunk {chunk}: {rows} rows decode to {raw} bytes, the TVL stride {stride} wants {rows * stride}"
                break
            rows_total, pos = rows_total + rows, pos + 20 + size
        if problem is None and rows_total != height:
            problem = f"chunks cover {rows_total} rows, the header says {height}"
        checked += 1
        if problem:
            bad += 1
            if bad <= MAX_PER_KIND:
                problems.append(f"rendition '{name}' ({struct.unpack_from('<I', csi, 12)[0]}x{height}): {problem}")
    if bad > MAX_PER_KIND:
        problems.append(f"image blocks: {bad} of {checked} chunked renditions are inconsistent in all")


def check_car(data):
    """Problems found in the bytes of one Assets.car; an empty list means every check here passed."""
    problems = []
    try:
        bom = _Bom(data)
        for var in ("CARHEADER", "KEYFORMAT", "RENDITIONS", "FACETKEYS"):
            if var not in bom.vars:
                raise CarError(f"BOM variable {var} is missing")
        if not bom.leaves("RENDITIONS"):
            problems.append("car has no renditions (assetutil reports invalid bitmapindex)")
        _check_bitmap_keys(bom, problems)
        _check_image_blocks(bom, problems)
    except (CarError, struct.error, IndexError, KeyError) as error:
        problems.append(f"unreadable car: {type(error).__name__}: {error}")
    return problems


def check_ipa(ipa):
    """{archive member: problems} for every .car in an .ipa (app, nested bundles, extensions, frameworks)."""
    found = {}
    with zipfile.ZipFile(ipa) as z:
        for name in z.namelist():
            if name.endswith(".car"):
                found[name] = check_car(z.read(name))
    return found
