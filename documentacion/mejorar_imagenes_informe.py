from pathlib import Path
from tempfile import NamedTemporaryFile
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "documentacion" / "assets_informe"
DOCX = ROOT / "documentacion" / "Informe_TP1_Bases_de_Datos_Activas_Smart_City.docx"

PALETTE = {
    "ink": "172A33",
    "petrol": "123A43",
    "teal": "24766B",
    "gold": "C9A646",
    "wine": "7A3145",
    "paper": "F8FAF8",
    "soft": "EEF4F2",
    "gray": "5B6770",
    "white": "FFFFFF",
}


def font(size, bold=False):
    candidates = [
        "C:/Windows/Fonts/aptos-display-bold.ttf" if bold else "C:/Windows/Fonts/aptos.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/calibrib.ttf" if bold else "C:/Windows/Fonts/calibri.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def hex_to_rgb(value, alpha=255):
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def crop_resize_cover(img, size):
    target_w, target_h = size
    src_w, src_h = img.size
    scale = max(target_w / src_w, target_h / src_h)
    resized = img.resize((round(src_w * scale), round(src_h * scale)), Image.Resampling.LANCZOS)
    left = (resized.width - target_w) // 2
    top = (resized.height - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def make_cover():
    base = Image.open(ASSETS / "portada_smart_city_ai_base.png").convert("RGB")
    img = crop_resize_cover(base, (1800, 620)).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    draw.rounded_rectangle([76, 80, 690, 458], radius=28, fill=(18, 58, 67, 218))
    draw.rectangle([76, 414, 690, 458], fill=(201, 166, 70, 230))
    draw.line([118, 404, 560, 404], fill=hex_to_rgb(PALETTE["gold"]), width=6)

    draw.text((116, 132), "SMART", font=font(82, True), fill=hex_to_rgb(PALETTE["white"]))
    draw.text((116, 216), "CITY", font=font(82, True), fill=hex_to_rgb(PALETTE["white"]))
    draw.text((120, 326), "Bases de Datos Activas", font=font(32), fill=(224, 241, 237, 255))
    draw.text((120, 374), "Sistema de emergencias urbanas", font=font(22), fill=(248, 250, 248, 235))

    final = Image.alpha_composite(img, overlay).convert("RGB")
    out = ASSETS / "portada_smart_city.png"
    final.save(out, quality=95)
    return out


def make_flow():
    base = Image.open(ASSETS / "flujo_operativo_ai_base.png").convert("RGB")
    src_w, src_h = base.size
    target_w, target_h = 1800, 760
    visual_h = 610

    scale = max(target_w / src_w, visual_h / src_h)
    resized = base.resize((round(src_w * scale), round(src_h * scale)), Image.Resampling.LANCZOS)
    left = max(0, (resized.width - target_w) // 2)
    top = max(0, round((resized.height - visual_h) * 0.32))
    crop = resized.crop((left, top, left + target_w, top + visual_h))

    canvas = Image.new("RGB", (target_w, target_h), "#" + PALETTE["paper"])
    canvas.paste(crop, (0, 0))
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    draw.rectangle([0, 568, target_w, target_h], fill=(248, 250, 248, 244))
    draw.line([92, 568, 1710, 568], fill=(201, 166, 70, 230), width=5)
    draw.text((70, 34), "Flujo operativo del sistema activo", font=font(38, True), fill=hex_to_rgb(PALETTE["petrol"]))
    draw.line([70, 88, 670, 88], fill=hex_to_rgb(PALETTE["gold"]), width=7)

    nodes = [
        (145, "Sensor", "lectura IoT", "R21"),
        (382, "Evento", "registro", "R21"),
        (606, "Incidente", "prioridad", "R12/R13"),
        (842, "Base activa", "decision", "ECA"),
        (1082, "Asignación", "mejor recurso", "R14/R15"),
        (1308, "Intervención", "arribo/cierre", "P4/R7"),
        (1542, "Auditoría", "trazabilidad", "R18/R19"),
        (1710, "SLA", "tiempo", "R16/R17"),
    ]

    label_font = font(21, True)
    small_font = font(16)
    code_font = font(15, True)

    for idx, (x, title, subtitle, code) in enumerate(nodes):
        y = 604 if idx % 2 == 0 else 682
        w = 170
        if title in ("Base activa", "Intervención", "Auditoría"):
            w = 188
        x0 = max(20, min(target_w - w - 20, x - w // 2))

        fill = (36, 118, 107, 232)
        if title in ("Incidente", "Base activa", "Asignacion"):
            fill = (18, 58, 67, 236)
        if title == "Intervención":
            fill = (122, 49, 69, 236)
        if title in ("Auditoría", "SLA"):
            fill = (238, 244, 242, 244)

        text_color = (255, 255, 255, 255)
        muted = (224, 241, 237, 255)
        if title in ("Auditoría", "SLA"):
            text_color = hex_to_rgb(PALETTE["ink"])
            muted = hex_to_rgb(PALETTE["gray"])

        border = hex_to_rgb(PALETTE["gold"]) if title in ("Base activa", "SLA") else (185, 201, 197, 255)
        draw.rounded_rectangle([x0, y, x0 + w, y + 66], radius=14, fill=fill, outline=border, width=2)
        draw.text((x0 + 13, y + 9), title, font=label_font, fill=text_color)
        draw.text((x0 + 13, y + 36), subtitle, font=small_font, fill=muted)
        draw.text((x0 + 13, y + 52), code, font=code_font, fill=hex_to_rgb(PALETTE["gold"]))

    final = Image.alpha_composite(canvas.convert("RGBA"), overlay).convert("RGB")
    out = ASSETS / "flujo_operativo.png"
    final.save(out, quality=95)
    return out


def replace_docx_images(cover_path, flow_path):
    replacements = {
        "word/media/image1.png": cover_path,
        "word/media/image2.png": flow_path,
    }
    with NamedTemporaryFile(delete=False, suffix=".docx") as tmp:
        tmp_path = Path(tmp.name)

    with ZipFile(DOCX, "r") as source, ZipFile(tmp_path, "w", ZIP_DEFLATED) as target:
        for item in source.infolist():
            if item.filename in replacements:
                target.writestr(item, replacements[item.filename].read_bytes())
            else:
                target.writestr(item, source.read(item.filename))

    tmp_path.replace(DOCX)


def main():
    cover = make_cover()
    flow = make_flow()
    replace_docx_images(cover, flow)
    print(cover)
    print(flow)
    print(DOCX)


if __name__ == "__main__":
    main()
