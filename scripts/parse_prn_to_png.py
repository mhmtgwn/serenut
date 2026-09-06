import os
import re
import sys
from PIL import Image

prn_path = sys.argv[1] if len(sys.argv) > 1 else 'outputs/test_order_5_items.prn'
output_prefix = sys.argv[2] if len(sys.argv) > 2 else 'test_label_page'
artifact_dir = r'C:\Users\notop\.gemini\antigravity-ide\brain\27153ec6-c17d-4be6-8950-62cdf1035352'

with open(prn_path, 'rb') as f:
    data = f.read()

# Pattern for BITMAP X,Y,widthBytes,heightDots,mode,data
# Note: TSPL mode 0: 0 = black (burned), 1 = white
pattern = re.compile(rb'BITMAP\s+(\d+),(\d+),(\d+),(\d+),(\d+),')

pos = 0
page_num = 1
saved_images = []

while True:
    match = pattern.search(data, pos)
    if not match:
        break
    
    x = int(match.group(1))
    y = int(match.group(2))
    width_bytes = int(match.group(3))
    height_dots = int(match.group(4))
    mode = int(match.group(5))
    
    data_start = match.end()
    expected_len = width_bytes * height_dots
    bitmap_bytes = data[data_start:data_start + expected_len]
    
    width_px = width_bytes * 8
    img = Image.new('RGB', (width_px, height_dots), color=(255, 255, 255))
    pixels = img.load()
    
    for row in range(height_dots):
        for col_byte in range(width_bytes):
            byte_val = bitmap_bytes[row * width_bytes + col_byte]
            for bit in range(8):
                px_x = col_byte * 8 + bit
                # In TSPL mode 0: 0 is black, 1 is white
                is_black = ((byte_val >> (7 - bit)) & 1) == 0
                pixels[px_x, row] = (0, 0, 0) if is_black else (255, 255, 255)
    
    # Save to artifacts directory
    # Also parse and draw QR codes for this page if present
    page_chunk = data[pos:data_start + expected_len + 300]
    qr_match = re.search(rb'QRCODE\s+(\d+),(\d+),[A-Z],(\d+),[A-Z],\d+,"([^"]+)"', page_chunk)
    if qr_match:
        try:
            import qrcode
            qr_x = int(qr_match.group(1))
            qr_y = int(qr_match.group(2))
            cell_w = int(qr_match.group(3))
            qr_content = qr_match.group(4).decode('utf-8', errors='ignore')
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_M,
                box_size=cell_w,
                border=2,
            )
            qr.add_data(qr_content)
            qr.make(fit=True)
            qr_img = qr.make_image(fill_color="black", back_color="white").convert('RGB')
            img.paste(qr_img, (qr_x, qr_y))
            print(f'Pasted QR code at ({qr_x}, {qr_y}) with content: {qr_content}')
        except Exception as e:
            print(f'QR rendering error: {e}')

    out_path = os.path.join(artifact_dir, f'{output_prefix}_{page_num}.png')
    img.save(out_path)
    print(f'Page {page_num} saved: {out_path} ({width_px}x{height_dots})')
    saved_images.append(out_path)
    
    page_num += 1
    pos = data_start + expected_len

print(f'Total {len(saved_images)} pages extracted.')
