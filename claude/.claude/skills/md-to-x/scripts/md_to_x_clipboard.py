#!/usr/bin/env python3
"""
Put rich text or an image on the macOS clipboard for one-shot Cmd+V into
X Articles, Notion, Google Docs, or any rich-text editor.

Two modes:
    Text mode (default) — convert Markdown file to HTML rich text on clipboard.
    Image mode (--image) — put image file on clipboard as PNG (any input format).

Stock-macOS only. No pip installs. Uses osascript, textutil, and sips — all built in.

Usage:
    # Text mode
    python3 md_to_x_clipboard.py /path/to/article.md
    python3 md_to_x_clipboard.py /path/to/article.md --rtf
    python3 md_to_x_clipboard.py /path/to/article.md --strip-h1

    # Image mode
    python3 md_to_x_clipboard.py /path/to/screenshot.png --image
    python3 md_to_x_clipboard.py /path/to/photo.jpg --image
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile


def inline(s: str) -> str:
    s = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', s)
    s = re.sub(r'(?<!\*)\*([^*\n]+)\*(?!\*)', r'<em>\1</em>', s)
    s = re.sub(r'`([^`\n]+)`', r'<code>\1</code>', s)
    s = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', s)
    return s


def md_to_html(md: str, strip_h1: bool = False) -> str:
    out: list[str] = []
    para: list[str] = []
    in_ul = False
    in_ol = False
    in_quote = False
    h1_skipped = False

    def flush_para() -> None:
        if para:
            text = inline(' '.join(p.strip() for p in para))
            out.append(f'<p>{text}</p>')
            para.clear()

    def close_lists() -> None:
        nonlocal in_ul, in_ol
        if in_ul:
            out.append('</ul>')
            in_ul = False
        if in_ol:
            out.append('</ol>')
            in_ol = False

    def close_quote() -> None:
        nonlocal in_quote
        if in_quote:
            out.append('</blockquote>')
            in_quote = False

    for line in md.split('\n'):
        s = line.strip()

        if not s:
            flush_para()
            close_lists()
            close_quote()
            continue

        if s.startswith('# '):
            flush_para()
            close_lists()
            close_quote()
            if strip_h1 and not h1_skipped:
                h1_skipped = True
                continue
            out.append(f'<h1>{inline(s[2:])}</h1>')
            continue

        if s.startswith('## '):
            flush_para()
            close_lists()
            close_quote()
            out.append(f'<h2>{inline(s[3:])}</h2>')
            continue

        if s.startswith('### '):
            flush_para()
            close_lists()
            close_quote()
            out.append(f'<h3>{inline(s[4:])}</h3>')
            continue

        if s.startswith('> '):
            flush_para()
            close_lists()
            if not in_quote:
                out.append('<blockquote>')
                in_quote = True
            out.append(f'<p>{inline(s[2:])}</p>')
            continue

        if s.startswith('- '):
            flush_para()
            close_quote()
            if in_ol:
                out.append('</ol>')
                in_ol = False
            if not in_ul:
                out.append('<ul>')
                in_ul = True
            out.append(f'<li>{inline(s[2:])}</li>')
            continue

        m = re.match(r'^\d+\.\s+(.+)$', s)
        if m:
            flush_para()
            close_quote()
            if in_ul:
                out.append('</ul>')
                in_ul = False
            if not in_ol:
                out.append('<ol>')
                in_ol = True
            out.append(f'<li>{inline(m.group(1))}</li>')
            continue

        close_lists()
        close_quote()
        para.append(s)

    flush_para()
    close_lists()
    close_quote()
    return ''.join(out)


def set_clipboard_html(html: str) -> None:
    fd, path = tempfile.mkstemp(suffix='.html')
    try:
        os.write(fd, html.encode('utf-8'))
        os.close(fd)
        script = f'set the clipboard to (read POSIX file "{path}" as «class HTML»)'
        subprocess.run(['osascript', '-e', script], check=True)
    finally:
        if os.path.exists(path):
            os.unlink(path)


def set_clipboard_rtf(html: str) -> None:
    """Fallback: convert HTML to RTF via textutil, then put RTF on clipboard."""
    fd_html, html_path = tempfile.mkstemp(suffix='.html')
    rtf_path = html_path.replace('.html', '.rtf')
    try:
        os.write(fd_html, html.encode('utf-8'))
        os.close(fd_html)
        subprocess.run(
            ['textutil', '-convert', 'rtf', html_path, '-output', rtf_path],
            check=True,
        )
        script = f'set the clipboard to (read POSIX file "{rtf_path}" as «class RTF »)'
        subprocess.run(['osascript', '-e', script], check=True)
    finally:
        for p in (html_path, rtf_path):
            if os.path.exists(p):
                os.unlink(p)


def set_clipboard_image(image_path: str) -> None:
    """Put any image file on the clipboard as PNG (stock macOS via sips + osascript)."""
    if not os.path.isfile(image_path):
        sys.exit(f'image not found: {image_path}')

    ext = os.path.splitext(image_path)[1].lower()
    png_path = image_path
    converted = False
    fd_png = None

    if ext != '.png':
        fd_png, png_path = tempfile.mkstemp(suffix='.png')
        os.close(fd_png)
        subprocess.run(
            ['sips', '-s', 'format', 'png', image_path, '--out', png_path],
            check=True,
            capture_output=True,
        )
        converted = True

    try:
        script = f'set the clipboard to (read POSIX file "{png_path}" as «class PNGf»)'
        subprocess.run(['osascript', '-e', script], check=True)
    finally:
        if converted and os.path.exists(png_path):
            os.unlink(png_path)


def strip_yaml_frontmatter(md: str) -> str:
    if md.startswith('---\n'):
        end = md.find('\n---\n', 4)
        if end != -1:
            return md[end + 5 :]
    return md


def main() -> None:
    parser = argparse.ArgumentParser(description='Put Markdown rich text or an image on the macOS clipboard.')
    parser.add_argument('file', help='Path to a Markdown file (text mode) or image file (--image).')
    parser.add_argument('--image', action='store_true', help='Image mode: put the file on the clipboard as PNG image data.')
    parser.add_argument('--rtf', action='store_true', help='Text mode only: use RTF clipboard instead of HTML.')
    parser.add_argument('--strip-h1', action='store_true', help='Text mode only: strip the first H1 (for editors that set the title separately, like X Articles).')
    args = parser.parse_args()

    if args.image:
        if args.rtf or args.strip_h1:
            sys.exit('--rtf and --strip-h1 are text-mode only; remove them when using --image.')
        set_clipboard_image(args.file)
        print(f'Image on clipboard: {os.path.basename(args.file)}. Click target paragraph and Cmd+V.')
        return

    with open(args.file, encoding='utf-8') as f:
        md = strip_yaml_frontmatter(f.read())

    html = md_to_html(md, strip_h1=args.strip_h1)

    if args.rtf:
        set_clipboard_rtf(html)
        kind = 'RTF'
    else:
        set_clipboard_html(html)
        kind = 'HTML'

    print(f'{kind} on clipboard ({len(html)} chars of HTML source). Click target editor and Cmd+V.')


if __name__ == '__main__':
    main()
