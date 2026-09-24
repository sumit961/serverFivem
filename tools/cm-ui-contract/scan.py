#!/usr/bin/env python3
"""
CM UI Contract Scanner (v2.0.1)
Audits all FiveM resources in the repository against the central CM UI design system contract.

Enforces:
1. Shared asset adoption (cm-theme.css, cm-components.css, cm-layout.css, cm-icons.css, cm-ui.js)
2. Canonical load order (theme -> components -> layout -> icons -> local CSS -> ui.js)
3. Forbidden central selector overrides outside cm-ui (e.g. .cm-btn, button.cm-btn, body .cm-card, etc.)
4. Forbidden CM token overrides (--cm-cyan, --cm-bg, --cm-primary, etc.)
5. Prohibition of native window.confirm() / confirm() in NUI JavaScript
6. Prohibition of duplicate @font-face declarations (Poppins, DM Sans)
7. Audit of custom font-family applied to standard CM controls
8. Dangerous viewport sizing warnings (e.g. 3vw font-size, 7vh heights)
9. Excessive !important rules in CSS

Classifies resources into:
- FULLY MIGRATED (all 5 canonical assets, canonical order, 0 violations)
- PARTIAL CM UI (theme or subset loaded, but incomplete adoption, load order issue, or violations)
- LEGACY UI (has NUI but does not load cm-theme.css)
"""

import os
import re
import sys
from pathlib import Path

EXCLUDED_DIRS = {'.git', 'node_modules', '.agents', 'graphify-out', 'cm-agent-out', 'tools', 'dist'}

PROTECTED_SELECTOR_PATTERN = re.compile(
    r'(?:^|[\s,>+~])(?:[a-zA-Z0-9_-]+)?\.cm-(?:btn|modal|toast|card|input|select|tabs?|badge|slot|actions?|screen)(?:[-_a-zA-Z0-9]+)?'
)

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

ALLOWED_FONTS_PATTERN = re.compile(
    r'var\(--cm-font|["\']?(?:DM Sans|Poppins)["\']?|inherit|sans-serif|system-ui|-apple-system|BlinkMacSystemFont|Segoe UI|Roboto',
    re.IGNORECASE
)


def find_resources(root_dir):
    resources = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS and not d.startswith('.')]
        if 'fxmanifest.lua' in filenames or '__resource.lua' in filenames:
            name = os.path.basename(dirpath)
            resources.append((name, Path(dirpath)))
    return sorted(resources, key=lambda x: x[0])


def strip_css_comments(text):
    return re.sub(r'/\*[\s\S]*?\*/', '', text)


def audit_resource(name, res_path):
    report = {
        'name': name,
        'has_nui': False,
        'has_theme': False,
        'has_components': False,
        'has_layout': False,
        'has_icons': False,
        'has_ui_js': False,
        'load_order_violations': [],
        'window_confirm': [],
        'protected_selectors': [],
        'token_overrides': [],
        'duplicate_fonts': [],
        'custom_control_fonts': [],
        'dangerous_sizing': [],
        'excessive_important': [],
        'category': 'NO_NUI',
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

    is_cm_ui = (name == 'cm-ui')

    # 1. Check HTML files for asset presence and canonical load order
    for hf in html_files:
        try:
            content = hf.read_text(encoding='utf-8', errors='ignore')
            rel_path = hf.relative_to(res_path)

            has_th = 'cm-theme.css' in content
            has_co = 'cm-components.css' in content
            has_la = 'cm-layout.css' in content
            has_ic = 'cm-icons.css' in content
            has_js = 'cm-ui.js' in content

            if has_th: report['has_theme'] = True
            if has_co: report['has_components'] = True
            if has_la: report['has_layout'] = True
            if has_ic: report['has_icons'] = True
            if has_js: report['has_ui_js'] = True

            # If resource adopts cm-theme.css, check canonical load order
            if has_th and not is_cm_ui:
                # Find all <link rel="stylesheet"> or css hrefs
                link_matches = list(re.finditer(r'<link[^>]+href=[\x22\x27]([^\x22\x27]+)[\x22\x27]', content, re.IGNORECASE))

                pos_theme = -1
                pos_comp = -1
                pos_layout = -1
                pos_icons = -1

                for idx, match in enumerate(link_matches):
                    href = match.group(1).lower()
                    if 'cm-theme.css' in href:
                        pos_theme = idx
                    elif 'cm-components.css' in href:
                        pos_comp = idx
                    elif 'cm-layout.css' in href:
                        pos_layout = idx
                    elif 'cm-icons.css' in href:
                        pos_icons = idx
                    elif not href.startswith('nui://cm-ui/') and not href.startswith('cm-ui/') and 'fonts.googleapis' not in href:
                        # Local stylesheet: must appear after cm-theme.css
                        if pos_theme != -1 and idx < pos_theme:
                            line_no = content[:match.start()].count('\n') + 1
                            report['load_order_violations'].append(
                                f"{rel_path}:{line_no}: INVALID_CM_UI_LOAD_ORDER: local stylesheet '{match.group(1)}' loaded before cm-theme.css"
                            )

                if pos_comp != -1 and pos_comp < pos_theme:
                    report['load_order_violations'].append(
                        f"{rel_path}: INVALID_CM_UI_LOAD_ORDER: cm-components.css loaded before cm-theme.css"
                    )
                if pos_layout != -1 and pos_comp != -1 and pos_layout < pos_comp:
                    report['load_order_violations'].append(
                        f"{rel_path}: INVALID_CM_UI_LOAD_ORDER: cm-layout.css loaded before cm-components.css"
                    )
                if pos_icons != -1 and pos_layout != -1 and pos_icons < pos_layout:
                    report['load_order_violations'].append(
                        f"{rel_path}: INVALID_CM_UI_LOAD_ORDER: cm-icons.css loaded before cm-layout.css"
                    )

        except Exception:
            pass

    # 2. Check CSS files (outside cm-ui)
    if not is_cm_ui:
        for cf in css_files:
            try:
                raw_content = cf.read_text(encoding='utf-8', errors='ignore')
                rel_path = cf.relative_to(res_path)

                # Duplicate font-face for Poppins or DM Sans
                if re.search(r"@font-face\s*\{[^}]*font-family\s*:\s*['\"](?:DM Sans|Poppins)['\"]", raw_content, re.IGNORECASE):
                    report['duplicate_fonts'].append(f"{rel_path}: redefines DM Sans / Poppins font-face")

                # Forbidden token overrides
                for pattern in FORBIDDEN_TOKENS:
                    for match in re.finditer(pattern, raw_content):
                        token = match.group(0).strip().rstrip(':').strip()
                        line_no = raw_content[:match.start()].count('\n') + 1
                        report['token_overrides'].append(f"{rel_path}:{line_no} redefines {token}")

                # Dangerous sizing
                for pattern, desc in DANGEROUS_SIZING:
                    for match in re.finditer(pattern, raw_content):
                        line_no = raw_content[:match.start()].count('\n') + 1
                        report['dangerous_sizing'].append(f"{rel_path}:{line_no} dangerous {desc}: {match.group(0)}")

                # Excessive !important (> 20)
                important_count = len(re.findall(r'!important', raw_content, re.IGNORECASE))
                if important_count > 20:
                    report['excessive_important'].append(f"{rel_path}: {important_count} !important rules")

                # Parse rules to detect protected selector overrides and custom control fonts
                clean_css = strip_css_comments(raw_content)
                rule_matches = list(re.finditer(r'([^{]+)\{([^}]+)\}', clean_css))

                for rm in rule_matches:
                    selector_chunk = rm.group(1).strip()
                    body_chunk = rm.group(2).strip()

                    # Ignore @keyframes, @media rule headers themselves
                    if selector_chunk.startswith('@'):
                        continue

                    # Check for protected selector overrides (including prefixed like body .cm-btn, button.cm-btn)
                    sel_match = PROTECTED_SELECTOR_PATTERN.search(selector_chunk)
                    if sel_match:
                        matched_sel = sel_match.group(0).strip()
                        line_no = raw_content[:rm.start()].count('\n') + 1
                        report['protected_selectors'].append(f"{rel_path}:{line_no} overrides {matched_sel}")

                        # Check if this standard control override defines unauthorized font-family
                        ff_match = re.search(r'font-family\s*:\s*([^;]+);', body_chunk, re.IGNORECASE)
                        if ff_match:
                            font_val = ff_match.group(1).strip()
                            if not ALLOWED_FONTS_PATTERN.search(font_val):
                                report['custom_control_fonts'].append(
                                    f"{rel_path}:{line_no} overrides {matched_sel} with custom font: {font_val}"
                                )

            except Exception:
                pass

    # 3. Check JS files for native window.confirm (exclude CMUI.confirm and window.CMUI.confirm)
    for jf in js_files:
        try:
            content = jf.read_text(encoding='utf-8', errors='ignore')
            rel_path = jf.relative_to(res_path)

            for match in re.finditer(r'(?:window\.)?confirm\s*\(', content):
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

    # 4. Classify resource
    if not report['has_nui']:
        report['category'] = 'NO_NUI'
        report['pass'] = True
    elif is_cm_ui:
        report['category'] = 'KERNEL_PROVIDER'
        report['pass'] = True
    else:
        has_all_assets = (
            report['has_theme'] and
            report['has_components'] and
            report['has_layout'] and
            report['has_icons'] and
            report['has_ui_js']
        )
        violations_count = (
            len(report['window_confirm']) +
            len(report['protected_selectors']) +
            len(report['token_overrides']) +
            len(report['duplicate_fonts']) +
            len(report['load_order_violations']) +
            len(report['custom_control_fonts'])
        )

        if has_all_assets and violations_count == 0:
            report['category'] = 'FULLY_MIGRATED'
            report['pass'] = True
        elif report['has_theme'] or report['has_components'] or report['has_layout'] or report['has_icons'] or report['has_ui_js']:
            report['category'] = 'PARTIAL_CM_UI'
            report['pass'] = False
        else:
            report['category'] = 'LEGACY_UI'
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
    layout_loaded = sum(1 for r in ui_reports if r['has_layout'])
    icons_loaded = sum(1 for r in ui_reports if r['has_icons'])
    js_loaded = sum(1 for r in ui_reports if r['has_ui_js'])

    total_window_confirm = sum(len(r['window_confirm']) for r in reports)
    total_protected_selectors = sum(len(r['protected_selectors']) for r in reports)
    total_token_overrides = sum(len(r['token_overrides']) for r in reports)
    total_duplicate_fonts = sum(len(r['duplicate_fonts']) for r in reports)
    total_load_order = sum(len(r['load_order_violations']) for r in reports)
    total_custom_fonts = sum(len(r['custom_control_fonts']) for r in reports)
    total_dangerous_sizing = sum(len(r['dangerous_sizing']) for r in reports)

    kernel = [r['name'] for r in ui_reports if r['category'] == 'KERNEL_PROVIDER']
    fully_migrated = [r['name'] for r in ui_reports if r['category'] == 'FULLY_MIGRATED']
    partial_cm_ui = [r['name'] for r in ui_reports if r['category'] == 'PARTIAL_CM_UI']
    legacy_ui = [r['name'] for r in ui_reports if r['category'] == 'LEGACY_UI']

    print("=" * 70)
    print("CM UI CONTRACT AUDIT REPORT (v2.0.1)")
    print("=" * 70)
    print(f"Resources scanned:        {len(reports)}")
    print(f"UI resources detected:    {len(ui_reports)}")
    print()
    print(f"Shared theme loaded:      {theme_loaded} / {len(ui_reports)}")
    print(f"Shared components loaded: {comp_loaded} / {len(ui_reports)}")
    print(f"Shared layout loaded:     {layout_loaded} / {len(ui_reports)}")
    print(f"Shared icons loaded:      {icons_loaded} / {len(ui_reports)}")
    print(f"Shared JS loaded:         {js_loaded} / {len(ui_reports)}")
    print()
    print("Violations:")
    print(f"  Native window.confirm:        {total_window_confirm} violations")
    print(f"  Protected selector overrides: {total_protected_selectors} violations")
    print(f"  CM token overrides:           {total_token_overrides} violations")
    print(f"  Duplicate font definitions:   {total_duplicate_fonts} violations")
    print(f"  Load order violations:        {total_load_order} violations")
    print(f"  Custom control fonts:         {total_custom_fonts} violations")
    print(f"  Dangerous viewport sizing:    {total_dangerous_sizing} warnings")
    print()
    print(f"KERNEL PROVIDER (1):")
    for k in kernel:
        print(f"  [*] {k}")
    print()
    print(f"FULLY MIGRATED ({len(fully_migrated)}):")
    for p in fully_migrated:
        print(f"  [+] {p}")
    print()
    print(f"PARTIAL CM UI ({len(partial_cm_ui)}):")
    for part in partial_cm_ui:
        print(f"  [~] {part}")
    print()
    print(f"LEGACY UI ({len(legacy_ui)}):")
    for leg in legacy_ui:
        print(f"  [-] {leg}")
    print("=" * 70)

    if '--detail' in sys.argv:
        print("\nDETAILED AUDIT BY RESOURCE:")
        for r in ui_reports:
            has_issues = (not r['pass']) or r['load_order_violations'] or r['dangerous_sizing']
            if has_issues and r['category'] != 'KERNEL_PROVIDER':
                print(f"\nResource: {r['name']} [{r['category']}]")
                missing = []
                if not r['has_theme']: missing.append('cm-theme.css')
                if not r['has_components']: missing.append('cm-components.css')
                if not r['has_layout']: missing.append('cm-layout.css')
                if not r['has_icons']: missing.append('cm-icons.css')
                if not r['has_ui_js']: missing.append('cm-ui.js')
                if missing:
                    print(f"  Missing Assets: {', '.join(missing)}")
                if r['load_order_violations']:
                    print("  Load Order Violations:")
                    for v in r['load_order_violations']: print(f"    - {v}")
                if r['window_confirm']:
                    print("  window.confirm:")
                    for v in r['window_confirm']: print(f"    - {v}")
                if r['protected_selectors']:
                    print("  Protected Selectors:")
                    for v in r['protected_selectors']: print(f"    - {v}")
                if r['custom_control_fonts']:
                    print("  Custom Control Fonts:")
                    for v in r['custom_control_fonts']: print(f"    - {v}")
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
