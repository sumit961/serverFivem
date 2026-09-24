#!/usr/bin/env python3
"""
CM UI Contract Scanner
Audits all FiveM resources in the repository against the central CM UI design system contract.

Checks for:
1. Shared asset adoption (cm-theme.css, cm-components.css, cm-ui.js)
2. Forbidden central selector overrides outside cm-ui (.cm-btn, .cm-modal, etc.)
3. Forbidden CM token overrides (--cm-primary, --cm-cyan, --cm-bg, etc.)
4. Usage of native window.confirm() / confirm() in NUI JavaScript
5. Duplicate @font-face declarations (Poppins, DM Sans)
6. Dangerous viewport sizing (e.g., 3vw, 2vw font-size or 7vh heights)
7. Excessive !important rules in CSS
"""

import os
import re
import sys
from pathlib import Path

EXCLUDED_DIRS = {'.git', 'node_modules', '.agents', 'graphify-out', 'cm-agent-out', 'tools', 'dist'}

PROTECTED_SELECTORS = [
    r'\.cm-btn(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-modal(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-toast(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-card(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-input(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-select(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-tabs?(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-badge(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-slot(?:\s*\{|--?[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-actions?(?:\s*\{|--?[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
    r'\.cm-screen(?:\s*\{|-[a-zA-Z0-9_-]+\s*\{|\.[a-zA-Z0-9_-]+\s*\{)',
]

FORBIDDEN_TOKENS = [
    r'--cm-primary\s*:',
    r'--cm-cyan\s*:',
    r'--cm-yellow\s*:',
    r'--cm-green\s*:',
    r'--cm-red\s*:',
    r'--cm-bg\s*:',
    r'--cm-bg-deep\s*:',
    r'--cm-panel\s*:',
    r'--cm-border\s*:',
    r'--cm-radius\s*:',
    r'--cm-font\s*:',
]

DANGEROUS_SIZING = [
    (r'font-size\s*:\s*[23](?:\.\d+)?vw', 'raw vw font-size'),
    (r'height\s*:\s*7vh', 'fixed 7vh component height'),
]


def find_resources(root_dir):
    resources = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS and not d.startswith('.')]
        if 'fxmanifest.lua' in filenames or '__resource.lua' in filenames:
            name = os.path.basename(dirpath)
            resources.append((name, Path(dirpath)))
    return sorted(resources, key=lambda x: x[0])


def audit_resource(name, res_path):
    report = {
        'name': name,
        'has_nui': False,
        'has_theme': False,
        'has_components': False,
        'has_ui_js': False,
        'window_confirm': [],
        'protected_selectors': [],
        'token_overrides': [],
        'duplicate_fonts': [],
        'dangerous_sizing': [],
        'excessive_important': [],
        'pass': True,
    }

    html_files = []
    css_files = []
    js_files = []

    for p in res_path.rglob('*'):
        if any(part in EXCLUDED_DIRS or part.startswith('.') for part in p.parts):
            continue
        if p.is_file():
            ext = p.suffix.lower()
            if ext == '.html':
                html_files.append(p)
            elif ext == '.css':
                css_files.append(p)
            elif ext == '.js':
                js_files.append(p)

    if html_files or css_files or js_files:
        report['has_nui'] = True

    # 1. Check HTML files
    for hf in html_files:
        try:
            content = hf.read_text(encoding='utf-8', errors='ignore')
            if 'cm-theme.css' in content:
                report['has_theme'] = True
            if 'cm-components.css' in content:
                report['has_components'] = True
            if 'cm-ui.js' in content:
                report['has_ui_js'] = True
        except Exception:
            pass

    is_cm_ui = (name == 'cm-ui')

    # 2. Check CSS files (outside cm-ui)
    if not is_cm_ui:
        for cf in css_files:
            try:
                content = cf.read_text(encoding='utf-8', errors='ignore')
                rel_path = cf.relative_to(res_path)

                # Duplicate font-face for Poppins or DM Sans
                if re.search(r"@font-face\s*\{[^}]*font-family\s*:\s*['\"](?:DM Sans|Poppins)['\"]", content, re.IGNORECASE):
                    report['duplicate_fonts'].append(f"{rel_path}: redefines DM Sans / Poppins font-face")

                # Protected selectors
                for pattern in PROTECTED_SELECTORS:
                    for match in re.finditer(pattern, content):
                        sel = match.group(0).strip().rstrip('{').strip()
                        line_no = content[:match.start()].count('\n') + 1
                        report['protected_selectors'].append(f"{rel_path}:{line_no} overrides {sel}")

                # Forbidden token overrides
                for pattern in FORBIDDEN_TOKENS:
                    for match in re.finditer(pattern, content):
                        token = match.group(0).strip().rstrip(':').strip()
                        line_no = content[:match.start()].count('\n') + 1
                        report['token_overrides'].append(f"{rel_path}:{line_no} redefines {token}")

                # Dangerous sizing
                for pattern, desc in DANGEROUS_SIZING:
                    for match in re.finditer(pattern, content):
                        line_no = content[:match.start()].count('\n') + 1
                        report['dangerous_sizing'].append(f"{rel_path}:{line_no} dangerous {desc}: {match.group(0)}")

                # Excessive !important (> 20)
                important_count = len(re.findall(r'!important', content, re.IGNORECASE))
                if important_count > 20:
                    report['excessive_important'].append(f"{rel_path}: {important_count} !important rules")

            except Exception:
                pass

    # 3. Check JS files for native window.confirm (exclude CMUI.confirm and window.CMUI.confirm)
    for jf in js_files:
        try:
            content = jf.read_text(encoding='utf-8', errors='ignore')
            rel_path = jf.relative_to(res_path)

            for match in re.finditer(r'(?:window\.)?confirm\s*\(', content):
                # Ensure it's not CMUI.confirm or window.CMUI.confirm
                prefix_start = max(0, match.start() - 15)
                prefix = content[prefix_start:match.start()]
                if 'CMUI.' in prefix:
                    continue

                start_line = content.rfind('\n', 0, match.start()) + 1
                end_line = content.find('\n', match.end())
                if end_line == -1: end_line = len(content)
                line_str = content[start_line:end_line].strip()

                if line_str.startswith('//') or line_str.startswith('*') or '/*' in line_str:
                    continue
                line_no = content[:match.start()].count('\n') + 1
                report['window_confirm'].append(f"{rel_path}:{line_no}: {line_str[:70]}")
        except Exception:
            pass

    if report['has_nui'] and not is_cm_ui:
        violations = (len(report['window_confirm']) +
                      len(report['protected_selectors']) +
                      len(report['token_overrides']) +
                      len(report['duplicate_fonts']))
        if violations > 0 or not report['has_theme']:
            report['pass'] = False

    return report


def main():
    root = Path(__file__).resolve().parents[2]
    resources = find_resources(root)

    reports = []
    for name, path in resources:
        reports.append(audit_resource(name, path))

    ui_reports = [r for r in reports if r['has_nui']]

    theme_loaded = sum(1 for r in ui_reports if r['has_theme'])
    comp_loaded = sum(1 for r in ui_reports if r['has_components'])
    js_loaded = sum(1 for r in ui_reports if r['has_ui_js'])

    total_window_confirm = sum(len(r['window_confirm']) for r in reports)
    total_protected_selectors = sum(len(r['protected_selectors']) for r in reports)
    total_token_overrides = sum(len(r['token_overrides']) for r in reports)
    total_duplicate_fonts = sum(len(r['duplicate_fonts']) for r in reports)
    total_dangerous_sizing = sum(len(r['dangerous_sizing']) for r in reports)

    passing = [r['name'] for r in ui_reports if r['pass']]
    needs_migration = [r['name'] for r in ui_reports if not r['pass']]

    print("=" * 70)
    print("CM UI CONTRACT AUDIT REPORT")
    print("=" * 70)
    print(f"Resources scanned:        {len(reports)}")
    print(f"UI resources detected:    {len(ui_reports)}")
    print()
    print(f"Shared theme loaded:      {theme_loaded} / {len(ui_reports)}")
    print(f"Shared components loaded: {comp_loaded} / {len(ui_reports)}")
    print(f"Shared JS loaded:         {js_loaded} / {len(ui_reports)}")
    print()
    print("Violations:")
    print(f"  Native window.confirm:        {total_window_confirm} violations")
    print(f"  Protected selector overrides: {total_protected_selectors} violations")
    print(f"  CM token overrides:           {total_token_overrides} violations")
    print(f"  Duplicate font definitions:   {total_duplicate_fonts} violations")
    print(f"  Dangerous viewport sizing:    {total_dangerous_sizing} warnings")
    print()
    print(f"PASS ({len(passing)}):")
    for p in passing:
        print(f"  [+] {p}")
    print()
    print(f"NEEDS MIGRATION ({len(needs_migration)}):")
    for n in needs_migration:
        print(f"  [-] {n}")
    print("=" * 70)

    if '--detail' in sys.argv:
        print("\nDETAILED VIOLATIONS BY RESOURCE:")
        for r in ui_reports:
            if not r['pass']:
                print(f"\nResource: {r['name']}")
                if r['window_confirm']:
                    print("  window.confirm:")
                    for v in r['window_confirm']: print(f"    - {v}")
                if r['protected_selectors']:
                    print("  Protected Selectors:")
                    for v in r['protected_selectors']: print(f"    - {v}")
                if r['token_overrides']:
                    print("  Token Overrides:")
                    for v in r['token_overrides']: print(f"    - {v}")
                if r['duplicate_fonts']:
                    print("  Duplicate Fonts:")
                    for v in r['duplicate_fonts']: print(f"    - {v}")
                if r['dangerous_sizing']:
                    print("  Dangerous Sizing:")
                    for v in r['dangerous_sizing']: print(f"    - {v}")

    return 0


if __name__ == '__main__':
    sys.exit(main())
