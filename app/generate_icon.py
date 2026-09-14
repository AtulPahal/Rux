#!/usr/bin/env python3
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont

def create_base_icon(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # macOS squircle margin & padding
    pad = int(size * 0.08)
    radius = int(size * 0.22)
    box = [pad, pad, size - pad, size - pad]
    
    # Background gradient simulation (dark tech navy/slate)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    
    for y in range(pad, size - pad):
        factor = (y - pad) / (size - 2 * pad)
        r = int(12 + factor * 16)
        g = int(16 + factor * 14)
        b = int(28 + factor * 35)
        bg_draw.line([(pad, y), (size - pad, y)], fill=(r, g, b, 255))
        
    # Mask for squircle
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(box, radius=radius, fill=255)
    
    img.paste(bg, (0, 0), mask)
    
    # Glowing border
    border_draw = ImageDraw.Draw(img)
    border_draw.rounded_rectangle(box, radius=radius, outline=(0, 240, 255, 200), width=int(size * 0.015))
    
    # Inner accent ring
    inner_pad = pad + int(size * 0.03)
    inner_radius = int(radius * 0.85)
    border_draw.rounded_rectangle(
        [inner_pad, inner_pad, size - inner_pad, size - inner_pad],
        radius=inner_radius,
        outline=(168, 85, 247, 80),
        width=int(size * 0.008)
    )
    
    # Center emblem: Stylized Mach-O needle / arrow / R
    cx, cy = size // 2, size // 2
    
    # Glowing backdrop for emblem
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_radius = int(size * 0.25)
    glow_draw.ellipse(
        [cx - glow_radius, cy - glow_radius, cx + glow_radius, cy + glow_radius],
        fill=(0, 240, 255, 35)
    )
    img = Image.alpha_composite(img, glow)
    draw = ImageDraw.Draw(img)
    
    # Stylized "R" / Injector symbol:
    # Left vertical stem
    stem_w = int(size * 0.075)
    stem_h = int(size * 0.44)
    stem_x = int(cx - size * 0.16)
    stem_y = int(cy - stem_h // 2)
    
    # Draw vertical stem with gradient or bright cyan
    draw.rounded_rectangle(
        [stem_x, stem_y, stem_x + stem_w, stem_y + stem_h],
        radius=int(stem_w * 0.3),
        fill=(0, 240, 255, 255)
    )
    
    # Upper loop of R
    loop_top = stem_y
    loop_h = int(stem_h * 0.55)
    loop_w = int(size * 0.28)
    draw.rounded_rectangle(
        [stem_x + stem_w // 2, loop_top, stem_x + loop_w, loop_top + loop_h],
        radius=int(loop_h * 0.45),
        outline=(255, 255, 255, 255),
        width=stem_w
    )
    
    # Diagonal leg of R (lightning/needle style)
    leg_start_x = stem_x + stem_w
    leg_start_y = loop_top + loop_h - int(stem_w * 0.4)
    leg_end_x = stem_x + loop_w + int(size * 0.02)
    leg_end_y = stem_y + stem_h
    
    draw.line(
        [(leg_start_x, leg_start_y), (leg_end_x, leg_end_y)],
        fill=(168, 85, 247, 255),
        width=stem_w
    )
    # Round endpoints
    r_cap = stem_w // 2
    draw.ellipse([leg_end_x - r_cap, leg_end_y - r_cap, leg_end_x + r_cap, leg_end_y + r_cap], fill=(168, 85, 247, 255))
    
    # Injector spark dot
    spark_cx = int(cx + size * 0.18)
    spark_cy = int(cy - size * 0.16)
    spark_r = int(size * 0.035)
    draw.ellipse([spark_cx - spark_r, spark_cy - spark_r, spark_cx + spark_r, spark_cy + spark_r], fill=(0, 255, 200, 255))
    
    return img

def main():
    iconset_dir = "app/Resources/AppIcon.iconset"
    os.makedirs(iconset_dir, exist_ok=True)
    
    base_img = create_base_icon(1024)
    
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    
    for filename, s in sizes:
        resized = base_img.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename))
        
    # Convert iconset to .icns
    icns_path = "app/Resources/AppIcon.icns"
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"[OK] Generated {icns_path}")

if __name__ == "__main__":
    main()
