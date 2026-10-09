"""Compile the existing Android vector into matching PWA launcher assets."""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = "{http://schemas.android.com/apk/res/android}"
source = ET.parse(ROOT / "android/app/src/main/res/drawable/lifemate_logo.xml").getroot()
svg_ns = "http://www.w3.org/2000/svg"
ET.register_namespace("", svg_ns)


def export_svg(maskable=False):
    svg = ET.Element(f"{{{svg_ns}}}svg", {
        "width": "512", "height": "512",
        "viewBox": f"0 0 {source.attrib[ANDROID + 'viewportWidth']} {source.attrib[ANDROID + 'viewportHeight']}",
    })
    if maskable:
        ET.SubElement(svg, f"{{{svg_ns}}}rect", {
            "width": source.attrib[ANDROID + "viewportWidth"],
            "height": source.attrib[ANDROID + "viewportHeight"],
            "fill": "#4D86E8",
        })
    for element in source.findall("path"):
        ET.SubElement(svg, f"{{{svg_ns}}}path", {
            "fill": element.attrib[ANDROID + "fillColor"],
            "d": element.attrib[ANDROID + "pathData"],
        })
    output = ROOT / "web/icons" / ("lifeguide-maskable.svg" if maskable else "lifeguide.svg")
    ET.ElementTree(svg).write(output, encoding="utf-8", xml_declaration=True)
    return output


export_svg(), export_svg(True)
print("Matching PWA SVG sources compiled from the existing Android vector.")
