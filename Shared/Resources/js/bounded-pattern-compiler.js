// Shared/Resources/js/bounded-pattern-compiler.js
// Restricted regex compiler. Deliberately no native regex, DOM or matching API.
(function (root) {
    'use strict';
    const MAX_SOURCE = 256, MAX_DEPTH = 16, MAX_REPEAT = 100;
    const MAX_STATES = 512, MAX_WORK = 100000, MAX_SCALAR = 0x10ffff;
    const budgets = new WeakMap();
    class Rejection extends Error {
        constructor(reason, offset) { super(reason); this.reason = reason; this.offset = offset; }
    }
    function createBudget(limit = MAX_WORK) {
        if (!Number.isInteger(limit) || limit < 0 || limit > MAX_WORK) throw new RangeError('compile budget');
        const state = { used: 0, limit };
        const handle = Object.freeze({ get used() { return state.used; }, get limit() { return state.limit; } });
        budgets.set(handle, state);
        return handle;
    }

    function compile(source, budget = createBudget()) {
        const work = budgets.get(budget);
        let offset = 0;
        function fail(reason) { throw new Rejection(reason, offset); }
        function take() {
            if (work.used >= work.limit) fail('compile-budget');
            work.used++;
        }
        if (!work) return { status: 'rejected', reason: 'invalid-budget', offset: 0 };
        if (typeof source !== 'string') return { status: 'rejected', reason: 'invalid-source', offset: 0 };
        if (source.length > MAX_SOURCE) return { status: 'rejected', reason: 'source-limit', offset: 0 };

        const digit = c => c !== undefined && c >= '0' && c <= '9';
        const peek = () => source[offset];
        function read() {
            take();
            if (offset === source.length) fail('syntax');
            const scalar = source.codePointAt(offset);
            if (scalar >= 0xd800 && scalar <= 0xdfff) fail('invalid-unicode');
            offset += scalar > 0xffff ? 2 : 1;
            return scalar;
        }
        function consume(c) {
            take();
            if (peek() !== c) fail('syntax');
            offset++;
        }
        function node(op, fields, nullable) { take(); return { op, ...fields, nullable }; }
        function canonical(ranges, negate) {
            // Input length is already capped. Charge comparisons and every range
            // before allocation; surrogate intervals cannot match scalar input.
            ranges.sort((a, b) => { take(); return a[0] - b[0] || a[1] - b[1]; });
            const merged = [];
            for (const pair of ranges) {
                take();
                const last = merged[merged.length - 1];
                if (last && pair[0] <= last[1] + 1) last[1] = Math.max(last[1], pair[1]);
                else merged.push([pair[0], pair[1]]);
            }
            if (!negate) return merged;
            let start = 0;
            const complement = [];
            for (const [lo, hi] of merged) {
                take();
                if (start < lo) complement.push([start, lo - 1]);
                start = hi + 1;
            }
            take();
            if (start <= MAX_SCALAR) complement.push([start, MAX_SCALAR]);
            return complement;
        }
        function escaped(inClass) {
            consume('\\');
            const c = String.fromCodePoint(read());
            const controls = { n: 10, r: 13, t: 9, f: 12, v: 11 };
            if (Object.hasOwn(controls, c)) return { scalar: controls[c] };
            const classes = {
                d: [[48, 57]], w: [[48, 57], [65, 90], [95, 95], [97, 122]],
                s: [[9, 13], [32, 32]]
            };
            const lower = c.toLowerCase();
            if (Object.hasOwn(classes, lower)) return { ranges: canonical(classes[lower], c !== lower) };
            if (c === 'b' || c === 'B') {
                if (inClass) fail('unsupported');
                return { assertion: c === 'b' ? 'word' : 'not-word' };
            }
            if ('\\.^$|?*+()[]{}-/'.includes(c)) return { scalar: c.codePointAt(0) };
            fail('unsupported');
        }
        function classAtom() {
            take();
            if (peek() === '\\') return escaped(true);
            return { scalar: read() };
        }
        function characterClass() {
            consume('[');
            const negate = peek() === '^';
            if (negate) consume('^');
            const ranges = [];
            while (offset < source.length && peek() !== ']') {
                take();
                const first = classAtom();
                if (peek() === '-' && source[offset + 1] !== ']') {
                    consume('-');
                    const last = classAtom();
                    if (first.scalar === undefined || last.scalar === undefined || first.scalar > last.scalar) fail('syntax');
                    take(); ranges.push([first.scalar, last.scalar]);
                } else if (first.ranges) {
                    for (const pair of first.ranges) { take(); ranges.push(pair); }
                } else { take(); ranges.push([first.scalar, first.scalar]); }
            }
            if (!ranges.length) fail('syntax');
            consume(']');
            return node('class', { ranges: canonical(ranges, negate) }, false);
        }
        function atom(depth) {
            take();
            const c = peek();
            if (c === '(') {
                if (depth >= MAX_DEPTH) fail('depth-limit');
                consume('(');
                if (peek() === '?') {
                    consume('?');
                    if (peek() !== ':') fail('unsupported');
                    consume(':');
                }
                const result = alternative(depth + 1);
                consume(')');
                return result;
            }
            if (c === '[') return characterClass();
            if (c === '\\') {
                const e = escaped(false);
                if (e.assertion) return node('assert', { kind: e.assertion }, true);
                if (e.ranges) return node('class', { ranges: e.ranges }, false);
                return node('char', { value: e.scalar }, false);
            }
            if (c === '^' || c === '$') { consume(c); return node('assert', { kind: c === '^' ? 'begin' : 'end' }, true); }
            if (c === '.') {
                consume('.');
                return node('class', { ranges: [[0, 9], [11, 12], [14, 0x2027], [0x202a, MAX_SCALAR]] }, false);
            }
            if (c === undefined || '*+?{}]'.includes(c)) fail('syntax');
            return node('char', { value: read() }, false);
        }
        function number() {
            take();
            if (!digit(peek())) fail('syntax');
            let value = 0;
            while (digit(peek())) {
                take(); value = value * 10 + read() - 48;
                if (value > MAX_REPEAT) fail('repeat-limit');
            }
            return value;
        }
        function quantified(depth) {
            let child = atom(depth);
            const q = peek();
            if (q === undefined || !'*+?{'.includes(q)) return child;
            if (child.op === 'assert') fail('syntax');
            let min, max;
            consume(q);
            if (q === '*') { min = 0; max = null; }
            else if (q === '+') { min = 1; max = null; }
            else if (q === '?') { min = 0; max = 1; }
            else {
                min = number(); max = min;
                if (peek() === ',') { consume(','); max = peek() === '}' ? null : number(); }
                consume('}');
                if (max !== null && max < min) fail('syntax');
            }
            const next = peek();
            if (next === '?' || next === '+') fail('unsupported');
            if (next === '*' || next === '{') fail('syntax');
            return node('repeat', { child, min, max }, min === 0 || child.nullable);
        }
        function sequence(depth) {
            const children = [];
            let nullable = true;
            while (offset < source.length && peek() !== '|' && peek() !== ')') {
                take();
                const child = quantified(depth);
                children.push(child); nullable = nullable && child.nullable;
            }
            return node('sequence', { children }, nullable);
        }
        function alternative(depth) {
            const children = [sequence(depth)];
            let nullable = children[0].nullable;
            while (peek() === '|') {
                consume('|');
                const child = sequence(depth);
                children.push(child); nullable = nullable || child.nullable;
            }
            return node('alternative', { children }, nullable);
        }
        try {
            take();
            const ast = alternative(0);
            if (offset !== source.length) fail('syntax');
            if (ast.nullable) fail('nullable');
            const instructions = [];
            function emit(instruction) {
                take();
                if (instructions.length >= MAX_STATES) fail('state-limit');
                instructions.push(instruction);
                return instructions.length - 1;
            }
            function build(n, next) {
                take();
                switch (n.op) {
                case 'char': return emit({ op: 'char', value: n.value, next });
                case 'class': return emit({ op: 'class', ranges: n.ranges, next });
                case 'assert': return emit({ op: 'assert', kind: n.kind, next });
                case 'sequence':
                    for (let k = n.children.length - 1; k >= 0; k--) { take(); next = build(n.children[k], next); }
                    return next;
                case 'alternative': {
                    let first = build(n.children[0], next);
                    for (let k = 1; k < n.children.length; k++) {
                        take(); first = emit({ op: 'split', first, second: build(n.children[k], next) });
                    }
                    return first;
                }
                case 'repeat': {
                    if (n.max === null) {
                        const loop = emit({ op: 'split', first: null, second: next });
                        instructions[loop].first = build(n.child, loop);
                        next = loop;
                    } else {
                        for (let k = n.min; k < n.max; k++) {
                            take(); next = emit({ op: 'split', first: build(n.child, next), second: next });
                        }
                    }
                    for (let k = 0; k < n.min; k++) { take(); next = build(n.child, next); }
                    return next;
                }
                default: throw new Error('unknown compiler node');
                }
            }
            const start = build(ast, emit({ op: 'match' }));
            return { status: 'compiled', program: { start, instructions } };
        } catch (e) {
            if (!(e instanceof Rejection)) throw e;
            return { status: 'rejected', reason: e.reason, offset: e.offset };
        }
    }
    root.BoundedPatternCompiler = Object.freeze({ createBudget, compile });
})(globalThis);
