"""MkDocs hook: map links to real repository files onto the docs pages that include them.

The Markdown sources link to real files (README.md, LICENSE, examples/*/README.md, ...), so
links work on GitHub and in the installed gem. Files outside docs/ are not site pages, so for
the site build this hook rewrites each such link to the docs/ wrapper page that includes the
file with include-markdown (for example, README.md -> index.md).
"""

import os
import re

import mkdocs.plugins

INCLUDE_RE = re.compile(r'\{%\s*include-markdown\s+"([^"]+)"[^%]*%\}')
# An inline link target, or a reference-style link definition, with an optional anchor.
LINK_RE = re.compile(r'(\]\(|^\[[^\]]+\]:\s*)([^)\s#]+)(#[^)\s]*)?', re.MULTILINE)

_wrappers = {}  # absolute path of an included real file -> wrapper page's absolute path


def on_files(files, config):
    _wrappers.clear()
    for file in files.documentation_pages():
        with open(file.abs_src_path, encoding='utf-8') as f:
            body = re.sub(r'^# .*\n', '', f.read()).strip()
        match = INCLUDE_RE.fullmatch(body)
        if match:
            real = os.path.join(os.path.dirname(file.abs_src_path), match.group(1))
            _wrappers[os.path.normpath(real)] = file.abs_src_path
    return files


# Run after include-markdown, which inserts the included files' (rewritten) links.
@mkdocs.plugins.event_priority(-50)
def on_page_markdown(markdown, page, config, files):
    page_dir = os.path.dirname(page.file.abs_src_path)

    def replace(match):
        target = match.group(2)
        if '://' in target or target.startswith('mailto:'):
            return match.group(0)
        wrapper = _wrappers.get(os.path.normpath(os.path.join(page_dir, target)))
        if wrapper is None:
            return match.group(0)
        return match.group(1) + os.path.relpath(wrapper, page_dir) + (match.group(3) or '')

    return LINK_RE.sub(replace, markdown)
