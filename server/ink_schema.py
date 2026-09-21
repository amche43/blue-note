"""Bounded, versioned canvas validation; no interpretation or execution of content."""
import base64
import io
import json
import math


def validate_canvas(raw):
    if not isinstance(raw, str) or len(raw) > 8 * 1024 * 1024:
        raise ValueError('画布超过 8MB')
    if not raw:
        return False
    value = json.loads(raw)

    def number(v, lo, hi):
        if type(v) not in (int, float) or not math.isfinite(v) or not lo <= v <= hi:
            raise ValueError('画布坐标无效')

    if not isinstance(value, dict) or value.get('version') != 1 or type(value.get('ruled')) is not bool:
        raise ValueError('画布版本无效')
    number(value.get('height'), 400, 20000)
    elements = value.get('elements')
    if not isinstance(elements, list) or len(elements) > 3000:
        raise ValueError('画布动作过多')
    ids = set()
    for e in elements:
        if not isinstance(e, dict) or e.get('kind') not in ('pen', 'highlight', 'text', 'image', 'rect', 'ellipse', 'line', 'table'):
            raise ValueError('画布对象无效')
        for k, size in dict(id=80, text=18000, note=4000, image=4*1024*1024).items():
            if not isinstance(e.get(k), str) or len(e[k]) > size:
                raise ValueError('画布字段无效')
        if e['id'] in ids:
            raise ValueError('画布动作编号重复')
        ids.add(e['id'])
        number(e.get('width'), 1, 80)
        number(e.get('color'), 0, 0xffffffff)
        number(e.get('rows'), 1, 20)
        number(e.get('columns'), 1, 20)
        box, points = e.get('box'), e.get('points')
        if not isinstance(box, list) or len(box) != 4 or not isinstance(points, list) or len(points) > 12000:
            raise ValueError('画布范围无效')
        for i, v in enumerate(box):
            number(v, -20000 if i < 2 else 0, 20000)
        if e['kind'] in ('pen', 'highlight') and not points:
            raise ValueError('笔迹不能为空')
        for point in points:
            if not isinstance(point, list) or len(point) != 2:
                raise ValueError('笔迹坐标无效')
            for v in point:
                number(v, -20000, 20000)
        if e['kind'] == 'image':
            from PIL import Image
            with Image.open(io.BytesIO(base64.b64decode(e['image'], validate=True))) as image:
                if image.format not in ('PNG', 'JPEG') or image.width * image.height > 20000000:
                    raise ValueError('画布照片无效')
                image.verify()
    return bool(elements)
