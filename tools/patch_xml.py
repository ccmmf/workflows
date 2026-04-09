#!/usr/bin/env python3
"""
patch_xml.py — in-place XML element patcher.

Usage:
    patch_xml.py <template_path> <xml_path> <new_content> [--block]

Arguments:
    template_path   Path to the XML file to patch (modified in-place).
    xml_path        Slash-separated element path, e.g. "host" or "model/binary".
                    The last segment is the target tag; an optional leading segment
                    constrains the match to within that parent element.
    new_content     Replacement value. Without --block, replaces the text node only.
                    With --block, replaces the entire element including its tags.
    --block         Replace the full <tag>...</tag> element rather than just its text.

Exit codes:
    0   Success.
    1   Usage error, file I/O error, or element not found.
"""

import sys
import re


def usage(msg=None):
    if msg:
        print(f"patch_xml: {msg}", file=sys.stderr)
    print(__doc__, file=sys.stderr)
    sys.exit(1)


def patch_element(text, tag, new_content, replace_block):
    # Regex-based: assumes tags have no attributes (e.g. <host>, not <host name="x">).
    # This holds for PEcAn template.xml but would need revision for attributed tags.
    if replace_block:
        patched, n = re.subn(
            r'<' + tag + r'>.*?</' + tag + r'>',
            new_content, text, count=1, flags=re.DOTALL,
        )
    else:
        patched, n = re.subn(
            r'(<' + tag + r'>)[^<]*(</'+tag+r'>)',
            r'\g<1>' + new_content + r'\g<2>',
            text, count=1,
        )
    return patched, n


def main():
    args = sys.argv[1:]
    replace_block = '--block' in args
    args = [a for a in args if a != '--block']

    if len(args) != 3:
        usage(f"expected 3 positional arguments, got {len(args)}")

    template_path, xml_path, new_content = args
    parts = xml_path.split('/')
    tag = parts[-1]
    parent = parts[0] if len(parts) > 1 else None

    try:
        content = open(template_path).read()
    except OSError as e:
        print(f"patch_xml: {e}", file=sys.stderr)
        sys.exit(1)

    if parent:
        total_replaced = 0

        def replacer(m):
            nonlocal total_replaced
            patched, n = patch_element(m.group(0), tag, new_content, replace_block)
            total_replaced += n
            return patched

        result = re.sub(
            r'<' + parent + r'>.*?</' + parent + r'>',
            replacer, content, count=1, flags=re.DOTALL,
        )
    else:
        result, total_replaced = patch_element(content, tag, new_content, replace_block)

    if total_replaced == 0:
        print(f"patch_xml: no element matched path '{xml_path}' in {template_path}", file=sys.stderr)
        sys.exit(1)

    try:
        open(template_path, 'w').write(result)
    except OSError as e:
        print(f"patch_xml: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
