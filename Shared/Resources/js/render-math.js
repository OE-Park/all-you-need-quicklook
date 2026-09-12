// Render only text nodes. Never reinterpret markup, code, or generated math.
(function (root) {
    'use strict';
    const protectedTags = new Set(['PRE', 'CODE', 'SCRIPT', 'STYLE', 'TEXTAREA', 'SVG', 'MATH']);
    // Consume TeX before Markdown can interpret escapes, emphasis, or tags in it.
    // A closing dollar must not be escaped. Keep the raw delimiters for the DOM pass.
    const mathSource = String.raw`\$\$((?:\\[\s\S]|[^\\])*?)\$\$|\$((?:\\[^\n]|[^\\$\n])+?)\$`;
    const mathToken = new RegExp('^(?:' + mathSource + ')');
    const escapeText = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    // Preserve Markdown escape intent before marked removes the backslash.
    // Inline extensions do not run inside fenced or inline code tokens.
    marked.use({ extensions: [{
        name: 'previewMathSource', level: 'inline',
        start(source) { return source.indexOf('$'); },
        tokenizer(source) {
            if (this.lexer.state.inRawBlock) return;
            const match = mathToken.exec(source.slice(0, 8192));
            if (match) return { type: 'previewMathSource', raw: match[0] };
        },
        renderer(token) { return escapeText(token.raw); }
    }, {
        name: 'previewEscapedDollar', level: 'inline',
        start(source) { return source.indexOf('\\$'); },
        tokenizer(source) {
            if (this.lexer.state.inRawBlock) return;
            if (source.startsWith('\\$')) return { type: 'previewEscapedDollar', raw: source.slice(0, 2) };
        },
        renderer() { return '<span class="math-literal">$</span>'; }
    }] });
    root.renderPreviewMath = function (element) {
        let visited = 0, textBudget = 262144, expressions = 0, skipped = false;
        const nodes = [];
        let node = element.firstChild;
        while (node) {
            if (++visited > 20000) { skipped = true; break; }
            const protectedNode = node.nodeType === 1 &&
                (protectedTags.has(node.tagName.toUpperCase()) || node.classList.contains('katex') || node.classList.contains('math-literal'));
            if (node.nodeType === 3) {
                if (node.data.length > textBudget) { skipped = true; break; }
                textBudget -= node.data.length;
                nodes.push(node);
            }
            if (!protectedNode && node.firstChild) { node = node.firstChild; continue; }
            while (node !== element && !node.nextSibling) node = node.parentNode;
            node = node === element ? null : node.nextSibling;
        }
        for (const node of nodes) {
            const text = node.data;
            const pattern = new RegExp(mathSource, 'g');
            const fragment = document.createDocumentFragment();
            let end = 0, match;
            while ((match = pattern.exec(text))) {
                // A literal backslash immediately before a delimiter protects it.
                let backslashes = 0;
                for (let i = match.index - 1; i >= 0 && text[i] === '\\'; i--) backslashes++;
                if (backslashes % 2) continue;
                if (++expressions > 1000 || match[0].length > 8192) { skipped = true; break; }
                fragment.append(document.createTextNode(text.slice(end, match.index)));
                const span = document.createElement('span');
                try {
                    katex.render((match[1] === undefined ? match[2] : match[1]).trim(), span,
                        { displayMode: match[1] !== undefined, throwOnError: false, trust: false, maxExpand: 1000 });
                    fragment.append(span);
                } catch (_) { fragment.append(document.createTextNode(match[0])); }
                end = pattern.lastIndex;
            }
            if (end) {
                fragment.append(document.createTextNode(text.slice(end)));
                node.replaceWith(fragment);
            }
            if (expressions > 1000) break;
        }
        if (skipped && !element.querySelector('.math-skipped')) {
            const notice = document.createElement('div');
            notice.className = 'placeholder-image math-skipped';
            notice.textContent = 'Some math was left as text because the preview limit was reached.';
            element.append(notice);
        }
    };
})(globalThis);
