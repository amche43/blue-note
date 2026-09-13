"""Private CPU OCR. Input images are processed in memory, never published."""
import base64
import io
import pathlib
import sys
import threading

_engine = None
_lock = threading.Lock()


def recognize(encoded):
    if not isinstance(encoded, str) or len(encoded) > 12 * 1024 * 1024:
        raise ValueError('照片过大，请先裁剪到单道题')
    try:
        raw = base64.b64decode(encoded, validate=True)
    except Exception:
        raise ValueError('照片编码不正确')
    if len(raw) > 8 * 1024 * 1024:
        raise ValueError('照片超过8MB')
    runtime = pathlib.Path(__file__).resolve().parents[3] / 'work/ocr-runtime'
    if runtime.is_dir() and str(runtime) not in sys.path:
        sys.path.insert(0, str(runtime))
    repaired = runtime.parent / 'ocr-repair'
    if repaired.is_dir() and str(repaired) not in sys.path:
        sys.path.insert(0, str(repaired))
    try:
        from PIL import Image, ImageOps
        import numpy as np
        from rapidocr_onnxruntime import RapidOCR
    except ImportError:
        raise RuntimeError('本机尚未安装识题模型，请先运行 install-ocr.cmd')
    try:
        with Image.open(io.BytesIO(raw)) as image:
            if image.width * image.height > 20000000:
                raise ValueError('图片像素过大，请裁剪后重试')
            prepared = ImageOps.exif_transpose(image).convert('RGB')
            prepared.thumbnail((2400,2400))
            pixels = np.array(prepared)
    except (OSError, Image.DecompressionBombError):
        raise ValueError('无法读取图片，请选择JPEG或PNG照片')
    if not _lock.acquire(blocking=False):
        raise RuntimeError('已有一张题目正在识别，请稍后重试')
    try:
        global _engine
        if _engine is None:
            _engine = RapidOCR(intra_op_num_threads=2, inter_op_num_threads=1)
        result, _ = _engine(pixels)
        rows = [{'text':str(row[1]), 'confidence':int(float(row[2])*100),'polygon':[[float(v) for v in point] for point in row[0]]} for row in result or []]
        return {'text':'\n'.join(row['text'] for row in rows), 'lines':rows,
                'engine':'RapidOCR / PP-OCRv4 / CPU','image_width':int(pixels.shape[1]),'image_height':int(pixels.shape[0]),
                'notice':'识别结果需核对。公式上下标、矩阵、图形和手写内容可能有误；此步骤只读取文字，不生成解答。'}
    finally:
        _lock.release()
