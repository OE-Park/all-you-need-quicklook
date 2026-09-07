// Shared/Resources/js/bounded-pattern-matcher.js
// Metered Thompson VM over BoundedPatternCompiler programs. No native regex, no DOM.
(function (root) {
    'use strict';
    const MAX_STEPS = 2000000, MAX_TEXT = 262144, MAX_INTERVALS = 2000;
    const MAX_SEGMENTS = 4000, MAX_RUN = 16384;
    const COUNTERS = [['steps', MAX_STEPS], ['text', MAX_TEXT],
                      ['intervals', MAX_INTERVALS], ['segments', MAX_SEGMENTS]];
    const budgets = new WeakMap();
    class Exhausted extends Error {
        constructor(reason) { super(reason); this.reason = reason; }
    }
    // One metering helper for every entry point; Task 2's resolveRun reuses it.
    function stepper(work) {
        return function take() {
            if (work.steps >= work.stepsLimit) throw new Exhausted('step-budget');
            work.steps++;
        };
    }

    function createBudget(limits = {}) {
        const state = {}, view = {};
        for (const [name, max] of COUNTERS) {
            const limit = limits[name] === undefined ? max : limits[name];
            if (!Number.isInteger(limit) || limit < 0 || limit > max) throw new RangeError('match budget');
            state[name] = 0; state[name + 'Limit'] = limit;
            Object.defineProperty(view, name, { get: () => state[name], enumerable: true });
            Object.defineProperty(view, name + 'Limit', { get: () => state[name + 'Limit'], enumerable: true });
        }
        const handle = Object.freeze(view);
        budgets.set(handle, state);
        return handle;
    }

    function findMatches(program, text, budget) {
        const work = budgets.get(budget);
        if (!work) return { status: 'rejected', reason: 'invalid-budget' };
        if (typeof text !== 'string') return { status: 'rejected', reason: 'invalid-text' };
        if (!program || typeof program !== 'object' || !Array.isArray(program.instructions)
            || !Number.isInteger(program.start) || !program.instructions[program.start]) {
            return { status: 'rejected', reason: 'invalid-program' };
        }
        if (text.length > MAX_RUN) return { status: 'skipped', reason: 'run-limit' };
        if (work.text + text.length > work.textLimit) return { status: 'incomplete', reason: 'text-budget' };
        work.text += text.length;                       // charged before any scanning

        const code = program.instructions;
        const take = stepper(work);                     // one unit of attempted work
        // \w is ASCII-only, so a surrogate code unit is never a word character and
        // charCodeAt needs no pair decoding for \b / \B.
        const isWord = u => u !== undefined && ((u >= 48 && u <= 57) || (u >= 65 && u <= 90)
            || (u >= 97 && u <= 122) || u === 95);
        const wordAt = p => isWord(p >= 0 && p < text.length ? text.charCodeAt(p) : undefined);
        const widthAt = p => text.codePointAt(p) > 0xffff ? 2 : 1;
        function inRanges(ranges, scalar) {
            for (const [lo, hi] of ranges) { take(); if (scalar >= lo && scalar <= hi) return true; }
            return false;
        }
        // Explicit stack; `list` maps pc -> earliest start, so leftmost wins on collision.
        function addThread(list, pc, start, pos) {
            const stack = [[pc, start]];
            while (stack.length) {
                take();                                  // attempted, even if deduplicated below
                const [current, from] = stack.pop();
                const seen = list.get(current);
                if (seen !== undefined && seen <= from) continue;
                list.set(current, from);
                const i = code[current];
                if (i.op === 'split') stack.push([i.first, from], [i.second, from]);
                else if (i.op === 'assert') {
                    const before = wordAt(pos - 1), here = wordAt(pos);
                    const holds = i.kind === 'begin' ? pos === 0
                        : i.kind === 'end' ? pos === text.length
                        : i.kind === 'word' ? before !== here : before === here;
                    if (holds) stack.push([i.next, from]);
                }
            }
        }
        const matches = [];
        function commit(best) {
            if (work.intervals >= work.intervalsLimit) throw new Exhausted('interval-limit');
            work.intervals++;
            matches.push({ start: best.start, end: best.end });
        }
        try {
            let list = new Map(), best = null, pos = 0;
            for (;;) {
                if (best === null) addThread(list, program.start, pos, pos);
                for (const [pc, start] of list) {        // enumerate reached match states
                    take();
                    if (code[pc].op !== 'match') continue;
                    if (best === null || start < best.start
                        || (start === best.start && pos > best.end)) best = { start, end: pos };
                }
                if (best !== null) {                     // a later start can never be leftmost
                    for (const [pc, start] of list) { take(); if (start > best.start) list.delete(pc); }
                }
                if (list.size === 0 || pos === text.length) {
                    if (best !== null) { commit(best); pos = best.end; best = null; list = new Map(); continue; }
                    if (pos === text.length) break;
                    pos += widthAt(pos); list = new Map(); continue;
                }
                const scalar = text.codePointAt(pos), width = scalar > 0xffff ? 2 : 1;
                const next = new Map();
                for (const [pc, start] of list) {
                    take();
                    const i = code[pc];
                    const advances = i.op === 'char' ? scalar === i.value
                        : i.op === 'class' ? inRanges(i.ranges, scalar) : false;
                    if (advances) addThread(next, i.next, start, pos + width);
                }
                list = next; pos += width;
            }
        } catch (e) {
            if (!(e instanceof Exhausted)) throw e;
            return { status: 'incomplete', reason: e.reason };   // run discarded atomically
        }
        return { status: 'matched', matches };
    }
    const RANK = { error: 4, warn: 3, info: 2, debug: 1 };

    function resolveRun(groups, budget) {
        const work = budgets.get(budget);
        if (!work) return { status: 'rejected', reason: 'invalid-budget' };
        if (!Array.isArray(groups)) return { status: 'rejected', reason: 'invalid-groups' };
        const take = stepper(work);
        try {
            const events = [];                            // {pos, delta, key}
            for (const group of groups) {
                take();                                    // charged for examining this group,
                if (!group || typeof group !== 'object' || !Array.isArray(group.matches)) {
                    return { status: 'rejected', reason: 'invalid-groups' };
                }
                const level = group.kind === 'level' ? group.level : null;
                if (group.kind !== 'general' && !(group.kind === 'level' && RANK[level])) {
                    return { status: 'rejected', reason: 'invalid-groups' };
                }
                for (const m of group.matches) {
                    take();                                // and for examining each of its matches,
                    if (!m || !Number.isInteger(m.start) || !Number.isInteger(m.end) || m.end <= m.start) {
                        return { status: 'rejected', reason: 'invalid-groups' };
                    }
                    events.push({ pos: m.start, delta: 1, key: level || 'general' },
                                { pos: m.end, delta: -1, key: level || 'general' });
                }                                          // before any event allocation.
            }
            const active = { general: 0, error: 0, warn: 0, info: 0, debug: 0 };
            const segments = [];
            function emit(start, end) {                    // covered slice between two events
                let level = null;
                for (const name of ['error', 'warn', 'info', 'debug']) {
                    take();
                    if (active[name] > 0 && (level === null || RANK[name] > RANK[level])) level = name;
                }
                const general = active.general > 0;
                if (level === null && !general) return;
                const last = segments[segments.length - 1];
                if (last && last.end === start && last.level === level && last.general === general) {
                    last.end = end; return;                // merge, no new wrapper
                }
                if (work.segments >= work.segmentsLimit) throw new Exhausted('segment-limit');
                work.segments++;
                segments.push({ start, end, level, general });
            }
            events.sort((a, b) => { take(); return a.pos - b.pos || a.delta - b.delta; });
            let index = 0, previous = null;
            while (index < events.length) {
                take();
                const pos = events[index].pos;
                if (previous !== null && pos > previous) emit(previous, pos);
                while (index < events.length && events[index].pos === pos) {
                    take(); active[events[index].key] += events[index].delta; index++;
                }
                previous = pos;
            }
            return { status: 'resolved', segments };
        } catch (e) {
            if (!(e instanceof Exhausted)) throw e;
            return { status: 'incomplete', reason: e.reason };
        }
    }

    root.BoundedPatternMatcher = Object.freeze({ createBudget, findMatches, resolveRun });
})(globalThis);
