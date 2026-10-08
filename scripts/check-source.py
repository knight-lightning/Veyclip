"""Read-only Windows/macOS source checks. This does not compile or type-check Swift."""
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

from tree_sitter import Language, Parser
import tree_sitter_swift


def main():
    root = Path(__file__).resolve().parent.parent
    errors = []
    parser = Parser(Language(tree_sitter_swift.language()))
    files = sorted(root.glob("Sources/**/*.swift")) + sorted(root.glob("Tests/**/*.swift")) + [root / "Package.swift"]
    for path in files:
        tree = parser.parse(path.read_bytes())
        if tree.root_node.has_error:
            errors.append(f"Swift syntax: {path.relative_to(root)}")
    for name in ["Info.plist", "ShareXMac.entitlements"]:
        try:
            plistlib.loads((root / "Resources" / name).read_bytes())
        except Exception as error:
            errors.append(f"Property list {name}: {error}")

    project_path = root / "ShareXMac.xcodeproj" / "project.pbxproj"
    project = project_path.read_text(encoding="utf-8")
    definitions = re.findall(r"^\s*([A-F0-9]{24})\s*=", project, re.MULTILINE)
    references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
    if len(definitions) != len(set(definitions)):
        errors.append("Duplicate Xcode object IDs")
    for reference in references - set(definitions):
        errors.append(f"Unresolved Xcode object reference: {reference}")
    # Check balanced structural delimiters without interpreting quoted settings/comments.
    clean = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"', "", project, flags=re.DOTALL)
    stack = []
    for character in clean:
        if character in "{(":
            stack.append(character)
        elif character in "})":
            if not stack or stack.pop() != {"}": "{", ")": "("}[character]:
                errors.append("Unbalanced Xcode project delimiters")
                break
    if stack:
        errors.append("Unclosed Xcode project delimiter")
    scheme = root / "ShareXMac.xcodeproj/xcshareddata/xcschemes/ShareXMac.xcscheme"
    try:
        xml = ET.parse(scheme)
        for reference in xml.iter("BuildableReference"):
            if reference.attrib["BlueprintIdentifier"] not in set(definitions):
                errors.append("Scheme refers to an unknown Xcode target")
    except Exception as error:
        errors.append(f"Xcode scheme XML: {error}")
    for path in ["Sources/CaptureCore", "Sources/ShareXMac", "THIRD_PARTY_NOTICES.md"]:
        if not (root / path).exists():
            errors.append(f"Missing Xcode source/resource: {path}")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"PASS: parsed {len(files)} Swift files, two property lists, Xcode references, and scheme XML.")
    print("This is a syntax/structure check only. Run swift test and the app build on macOS next.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
