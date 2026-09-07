// Feasibility probe only: manually supplied AST, not a production parser/engine.
globalThis.runMeteredProbe = function () {
  class Exhausted extends Error {}
  class Budget {
    constructor(limit) { this.limit=limit; this.used=0; }
    take() { if(this.used >= this.limit) throw new Exhausted(); this.used++; }
  }
  const chr = c => ({op:'char', c});
  const cat = (...xs) => ({op:'cat',xs});
  const alt = (...xs) => ({op:'alt',xs});
  const plus = x => ({op:'plus',x});
  const boundary = () => ({op:'word'});
  const literal = s => cat(...Array.from(s,chr));
  function compile(ast,budget) {
    const p=[];
    const emit = i => {budget.take(); if(p.length===512) throw new Exhausted(); p.push(i);return p.length-1;};
    function build(a,next,depth) {
      budget.take(); if(depth>16) throw new Exhausted();
      if(a.op==='cat') { for(let k=a.xs.length-1;k>=0;k--){budget.take();next=build(a.xs[k],next,depth+1);} return next; }
      if(a.op==='alt') {let head=build(a.xs[0],next,depth+1);for(let k=1;k<a.xs.length;k++){budget.take();head=emit({op:'split',a:head,b:build(a.xs[k],next,depth+1)});}return head;}
      if(a.op==='plus') {const split=emit({op:'split',a:null,b:next});const head=build(a.x,split,depth+1);p[split].a=head;return head;}
      return emit({...a,next});
    }
    const end=emit({op:'match'});const start=build(ast,end,0);return {p,start};
  }
  const word = c => c!==undefined && ((c>=48&&c<=57)||(c>=65&&c<=90)||(c>=97&&c<=122)||c===95);
  function first(program,text,from,budget) {
    // Earliest origin dominates later origins at the same state/position.
    let active=new Map(),best=null;
    function closure(seeds,pos) {
      const visited=new Map(),out=new Map(),stack=[];
      for(const item of seeds){budget.take();stack.push(item);}
      while(stack.length) {
        budget.take(); const [pc,start]=stack.pop();
        if(visited.has(pc)&&visited.get(pc)<=start)continue;
        visited.set(pc,start);const i=program.p[pc];
        if(i.op==='split') {stack.push([i.a,start],[i.b,start]);continue;}
        if(i.op==='word') {const before=pos===0?undefined:text.codePointAt(pos-1);const after=pos===text.length?undefined:text.codePointAt(pos);if(word(before)!==word(after))stack.push([i.next,start]);continue;}
        if(i.op==='end') {if(pos===text.length)stack.push([i.next,start]);continue;}
        if(i.op==='begin') {if(pos===0)stack.push([i.next,start]);continue;}
        if(i.op==='match') {if(!best||start<best[0]||(start===best[0]&&pos>best[1]))best=[start,pos];continue;}
        out.set(pc,start);
      }
      return out;
    }
    for(let pos=from;;) {
      budget.take();const seeds=[];
      for(const [pc,start] of active){budget.take();seeds.push([pc,start]);}
      if(!best)seeds.push([program.start,pos]);
      active=closure(seeds,pos);
      if(pos===text.length)break;
      const cp=text.codePointAt(pos),symbol=String.fromCodePoint(cp),next=new Map();
      for(const [pc,start] of active) {budget.take();const i=program.p[pc];if((!best||start<=best[0])&&i.c===symbol){if(!next.has(i.next)||start<next.get(i.next))next.set(i.next,start);}}
      if(best&&next.size===0)break;
      active=next;pos+=cp>0xffff?2:1;
    }
    return best;
  }
  function scan(program,text,budget) {
    if(text.length>16384) return {status:'oversize',matches:[]};
    let from=0,matches=[];
    try {
      while(from<text.length){budget.take();const m=first(program,text,from,budget);if(!m)break;if(m[1]===m[0])throw new Error('nullable AST rejected by probe');matches.push(m);if(matches.length>2000)throw new Exhausted();from=m[1];}
      return {status:'complete',matches};
    } catch(e) {if(e instanceof Exhausted)return {status:'budget',matches:[]};throw e;}
  }
  const assertions=[];
  function check(name,ok,detail){assertions.push({name,ok,detail});if(!ok)throw new Error(name+': '+JSON.stringify(detail));}
  const compileBudget=new Budget(100000);
  const defaults=[['ERROR','FATAL','CRITICAL'],['WARN','WARNING'],['INFO'],['DEBUG','TRACE']];
  for(const levels of defaults) {
    const prog=compile(cat(boundary(),alt(...levels.map(literal)),boundary()),compileBudget);
    const text=levels.join(' '),b=new Budget(2000000),r=scan(prog,text,b);
    check('default '+levels[0],r.status==='complete'&&r.matches.length===levels.length,{...r,steps:b.used});
  }
  let b=new Budget(2000000),p=compile(cat(plus(plus(chr('a'))),{op:'end'}),compileBudget);
  let t=performance.now(),r=scan(p,'a'.repeat(16000)+'!',b);
  check('nested repetition failure',r.status==='complete'&&r.matches.length===0,{...r,steps:b.used,ms:performance.now()-t});
  b=new Budget(200);r=scan(p,'a'.repeat(16000)+'!',b);
  check('precise internal stop',r.status==='budget'&&b.used===200,{...r,steps:b.used});
  b=new Budget(2000000);p=compile(alt(literal('a'),literal('ab')),compileBudget);r=scan(p,'ab',b);
  check('leftmost longest',JSON.stringify(r.matches)==='[[0,2]]',r);
  p=compile(literal('😀한'),compileBudget);r=scan(p,'x😀한z',b);
  check('UTF16 offsets',JSON.stringify(r.matches)==='[[1,4]]',r);
  p=compile(cat({op:'begin'},literal('ERROR')),compileBudget);
  const lines=['ERROR one','ERROR two'].map(s=>scan(p,s,b));
  check('line anchors',lines.every(x=>x.matches.length===1),lines);
  p=compile(literal('import os'),compileBudget);
  const host=document.createElement('pre');host.innerHTML='<code><span class="hljs-keyword">import</span> os</code>';document.body.append(host);
  const nodes=[host.firstChild.firstChild.firstChild,host.firstChild.lastChild];
  r=scan(p,nodes.map(n=>n.data).join(''),b);
  let offset=0,parts=[];
  for(const node of nodes){const start=offset,end=offset+node.length;offset=end;for(const [a,z] of r.matches){if(a<end&&z>start)parts.push({node,start:Math.max(a,start)-start,end:Math.min(z,end)-start});}}
  for(const part of parts.reverse()){const tail=part.node.splitText(part.end);const match=part.node.splitText(part.start);const span=document.createElement('mark');span.textContent=match.data;match.replaceWith(span);}
  check('cross token DOM mapping',host.textContent==='import os'&&host.querySelectorAll('mark').length===2&&host.querySelectorAll('.hljs-keyword').length===1,{html:host.innerHTML});
  let stopped=false,cb=new Budget(2);try{compile(literal('abc'),cb);}catch(e){stopped=e instanceof Exhausted;}
  check('compile stop',stopped&&cb.used===2,{steps:cb.used});
  check('no eval CSP',(()=>{try{eval('1');return false;}catch(e){return e.name==='EvalError';}})(),{});
  return {assertions,compileSteps:compileBudget.used};
};
