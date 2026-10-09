// 2026-10-06. Browser-only practice. Tables are exported from the product core.
function createHaneulPreviewEngine(data) {
  function hangulToKeys(value) {
    let out = '';
    for (const ch of value.normalize('NFC')) {
      const n = ch.codePointAt(0) - 0xac00;
      if (n >= 0 && n < 11172) {
        out += data.jamoKeys[data.consonants[Math.floor(n / 588)]];
        out += data.jamoKeys[data.vowels[Math.floor(n / 28) % 21]];
        if (n % 28) out += data.jamoKeys[data.finalChars[n % 28]];
      } else if (data.jamoKeys[ch]) out += data.jamoKeys[ch];
      else if (/[0-9'’]/.test(ch)) out += ch;
      else return null;
    }
    return out || null;
  }
  function keysToHangul(value) {
    let out = '', initial = null, medial = null, finals = [];
    const assembled = () => {
      if (initial !== null && medial !== null) {
        const tail = finals.length === 2 ? data.finalPairs[finals.join(',')] : finals.length ? data.finalIndices[finals[0]] : 0;
        return String.fromCodePoint(0xac00 + (initial * 21 + medial) * 28 + tail);
      }
      return initial !== null ? data.consonants[initial] : medial !== null ? data.vowels[medial] : '';
    };
    const flush = () => { out += assembled(); initial = null; medial = null; finals = []; };
    for (const ch of value) {
      const entry = data.layout[ch];
      if (!entry) {
        if (!/[0-9'’]/.test(ch)) return null;
        flush(); out += ch; continue;
      }
      const index = entry.index;
      if (entry.kind === 'c') {
        if (medial === null) { if (initial !== null) flush(); initial = index; }
        else if (initial === null) { flush(); initial = index; }
        else if (!finals.length && data.finalIndices[index] >= 0) finals = [index];
        else if (finals.length === 1 && data.finalPairs[`${finals[0]},${index}`] !== undefined) finals.push(index);
        else { flush(); initial = index; }
      } else if (finals.length) {
        const carry = finals.pop(); out += assembled(); initial = carry; medial = index; finals = [];
      } else if (medial !== null) {
        const combined = data.vowelPairs[`${medial},${index}`];
        if (combined !== undefined) medial = combined;
        else { flush(); medial = index; }
      } else medial = index;
    }
    flush(); return out || null;
  }
  function toggle(value) {
    const word = value.normalize('NFC');
    if (!/^[A-Za-z0-9가-힣ㄱ-ㅣ'’]+$/.test(word)) return null;
    const hangul = /[가-힣ㄱ-ㅣ]/.test(word), latin = /[A-Za-z]/.test(word);
    if (hangul === latin) return null;
    return hangul ? hangulToKeys(word) : keysToHangul(word);
  }
  return { hangulToKeys, keysToHangul, toggle };
}
if (typeof module !== 'undefined' && module.exports) module.exports = { createHaneulPreviewEngine };
if (typeof document !== 'undefined') (() => {
  const root = document.getElementById('haneul-onboarding-preview');
  const assets = JSON.parse(document.getElementById('hk-preview-assets').textContent);
  const engine = createHaneulPreviewEngine(assets.data);
  const win = root.querySelector('.hk-window'), stage = root.querySelector('#hk-stage');
  const status = root.querySelector('#hk-status'), next = root.querySelector('#hk-next'), back = root.querySelector('#hk-back');
  const names = ['설치','입력기 등록과 선택','직접 입력하기','단축키와 개인 사전','메뉴바와 후원'];
  const titles = ['Mac에 하늘키보드','Mac에서 하늘키보드를 선택','하늘키보드로 apple','원하는 글자로 바꿔보세요','메뉴바에서 만나요'];
  const descriptions = [
    '익숙한 두벌식에 더 편한 한영 입력을 더해요.<br>먼저 하늘키보드 입력기를 설치해 주세요.',
    '등록하는 위치를 화면으로 따라가 보세요.<br>추가한 뒤 메뉴바의 입력 소스에서 하늘키보드를 선택해요.',
    '시연을 보고 아래 연습장에 직접 입력해 보세요.<br>영어로 바뀌어요. 한글모드는 그대로에요.',
    '영어 사전에 없는 이름이나 숫자 조합도 바꿀 수 있어요.<br>단어 뒤에 커서를 두고 Shift + Space를 눌러 보세요.',
    '메뉴바에서 설정을 열거나 이 안내를 다시 볼 수 있어요.<br>필요할 때 언제든 하늘키보드를 눌러 주세요.'
  ];
  const state = { step:0, installed:false, registerPage:0, registered:false, selected:false, oldRemoved:false, menu:true, dictTab:'force' };
  const design = { glass:true, appearance:'system' };
  // Text typed by the user stays only in this page's memory, never widgetState.
  const practice = { auto:{value:'',pending:null,pair:null}, manual:{value:'',pending:null,pair:null} };
  const personal = { force:new Set(), block:new Set(), recent:[] };
  const verifiedAuto = new Set(Object.keys(assets.data.autoWords).map(w=>w.toLowerCase()));
  let installTimer, demoTimer, installing = false, demoRunning = false;
  const icon = name => `<i data-lucide="${name}" aria-hidden="true"></i>`;
  const esc = value => String(value).replace(/[&<>"']/g,ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const button = (id,label,extra='') => `<button id="${id}" type="button" class="hk-button cursor-interaction ${extra}">${label}</button>`;
  const normalize = value => value.normalize('NFC').replace(/’/g,"'").trim().toLowerCase();
  function hydrate(snapshot) {
    const saved = snapshot && snapshot.privateContent;
    if (!saved || saved.version !== 2) return false;
    const before = JSON.stringify(state);
    if (Number.isInteger(saved.step)) state.step=Math.max(0,Math.min(4,saved.step));
    if (Number.isInteger(saved.registerPage)) state.registerPage=Math.max(0,Math.min(2,saved.registerPage));
    for (const key of ['installed','registered','selected','oldRemoved','menu']) if (typeof saved[key]==='boolean') state[key]=saved[key];
    if (['force','block','recent'].includes(saved.dictTab)) state.dictTab=saved.dictTab;
    return before !== JSON.stringify(state);
  }
  function save() {
    if (window.openai && window.openai.setWidgetState) Promise.resolve(window.openai.setWidgetState({modelContent:{preview:'하늘키보드 시작하기 수정안',step:names[state.step]},privateContent:{version:2,...state}})).catch(()=>{});
  }
  const announce = text => { status.textContent=text; };
  const bind = (id,fn) => { const el=root.querySelector('#'+id); if(el)el.addEventListener('click',fn); };
  function decorate() {
    root.querySelectorAll('[data-hk-logo]').forEach(img=>{img.src=assets.logo;});
    root.querySelectorAll('[data-hk-input-icon]').forEach(el=>{el.style.maskImage=`url("${assets.inputIcon}")`;el.style.webkitMaskImage=`url("${assets.inputIcon}")`;});
    if(globalThis.lucide)globalThis.lucide.createIcons({attrs:{width:16,height:16}});
  }
  function go(step) { clearTimeout(demoTimer);demoRunning=false;state.step=Math.max(0,Math.min(4,step));announce('');render();save(); }
  function render() {
    root.querySelector('#hk-eyebrow').textContent=`0${state.step+1}  ${names[state.step]}`;
    root.querySelector('#hk-heading').textContent=titles[state.step];
    root.querySelector('#hk-description').innerHTML=descriptions[state.step];
    stage.dataset.step=String(state.step);
    next.textContent=state.step===4?'하늘키보드 시작하기':'다음';back.disabled=state.step===0;
    root.querySelector('#hk-progress').innerHTML=names.map((label,i)=>`<button type="button" class="cursor-interaction" aria-label="${i+1}단계: ${label}" data-step="${i}" ${state.step===i?'aria-current="step"':''}><span></span></button>`).join('');
    root.querySelector('#hk-progress').querySelectorAll('button[data-step]').forEach(el=>el.addEventListener('click',()=>go(Number(el.dataset.step))));
    [renderInstall,renderRegistration,renderAutomatic,renderManual,renderMenu][state.step]();decorate();
  }
  function renderInstall() {
    stage.innerHTML=`<div class="hk-install-card"><img class="hk-install-icon" data-hk-logo alt="하늘키보드"><div><h3>하늘키보드 입력기</h3><span class="hk-chip ${state.installed?'is-ready':''}">${icon(state.installed?'circle-check':'circle-dashed')}${state.installed?'설치 완료':installing?'설치하는 중':'아직 설치되지 않았어요'}</span></div></div><div class="hk-install-actions">${button('hk-install',state.installed?'설치 완료':installing?'설치하는 중…':'입력기 설치하기',state.installed?'':'hk-primary')}<button type="button" class="hk-text-button cursor-interaction" id="hk-installed">${state.installed?'미설치 화면도 보기':'이미 설치한 화면 보기'}</button></div><p class="hk-note">Mac에서 사용할 한국어 입력기를 준비해요.<br>여기서는 설치 전후의 모습을 체험할 수 있어요.</p>`;
    root.querySelector('#hk-install').disabled=state.installed||installing;
    bind('hk-install',()=>{installing=true;render();installTimer=setTimeout(()=>{installing=false;state.installed=true;if(state.step===0){render();announce('설치 완료 화면이에요. 실제 설치 상태를 확인한 것은 아니에요.');}save();},700);});
    bind('hk-installed',()=>{clearTimeout(installTimer);installing=false;state.installed=!state.installed;render();announce('설치 상태 미리보기를 바꿨어요.');save();});
  }
  function renderRegistration() {
    const p=state.registerPage;
    const sidebar=p===0?`<div class="hk-sidebar-title">시스템 설정</div><span>일반</span><span>모양</span><div class="hk-sidebar-selected">${icon('keyboard')} 키보드</div>`:`<div class="hk-sidebar-title">${p===1?'언어':'입력 소스'}</div><span>${p===1?'영어':'ABC'}</span><div class="hk-sidebar-selected">${p===1?'한국어':'하늘키보드'}</div>`;
    let content;
    if(p===0) content=`<h3 class="hk-setting-title">키보드</h3><div class="hk-setting-row"><span>키 반복 속도</span><span>느리게 ━━━ 빠르게</span></div><div class="hk-setting-row"><span><strong>텍스트 입력</strong><br>입력 소스</span>${button('hk-settings-edit','편집','hk-primary')}</div><p class="hk-note">시스템 설정 → 키보드에서<br><strong>텍스트 입력의 편집</strong>을 눌러요.</p>`;
    else if(p===1) content=`<h3 class="hk-setting-title">입력 소스 추가</h3><div class="hk-source-option"><span data-hk-input-icon aria-hidden="true"></span>하늘키보드 (두벌식)</div><p class="hk-note">입력 소스 목록의 <strong>＋</strong>를 누른 뒤<br><strong>한국어 → 하늘키보드 (두벌식)</strong>을 선택해요.</p><div class="hk-setting-actions">${button('hk-register',state.registered?'등록 완료':'추가','hk-primary')}</div>`;
    else content=`<h3 class="hk-setting-title">입력 소스에서 선택</h3><div class="hk-source-option"><span data-hk-input-icon aria-hidden="true"></span>하늘키보드 (두벌식)</div><div class="hk-setting-row"><span>${state.oldRemoved?'기존 두벌식 제거됨':'두벌식 · 기본 입력기'}</span>${state.oldRemoved?icon('circle-check'):button('hk-remove-old','제거')}</div><div class="hk-setting-actions">${button('hk-select',state.selected?'선택 완료':'하늘키보드 선택','hk-primary')}</div>`;
    stage.innerHTML=`<div class="hk-setting-steps" aria-label="등록 위치 안내">${['① 설정 열기','② 입력기 추가','③ 선택하기'].map((label,i)=>`<button type="button" class="cursor-interaction" data-reg="${i}" aria-pressed="${p===i}">${label}</button>`).join('')}</div><div class="hk-settings" aria-label="시스템 설정 화면을 단순화한 안내"><div class="hk-settings-sidebar">${sidebar}</div><div class="hk-settings-content">${content}</div></div><div class="hk-source-status"><span class="hk-chip ${state.registered?'is-ready':''}">${icon(state.registered?'circle-check':'circle-dashed')}${state.registered?'등록 완료':'아직 등록되지 않았어요'}</span><span class="hk-chip ${state.selected?'is-ready':''}">${state.selected?'선택 완료':'선택 전'}</span></div><p class="hk-note">하늘키보드를 추가한 뒤 <strong>기존 ‘두벌식’은 목록에서 빼 주세요.</strong><br>영어 입력용 ABC는 그대로 두면 돼요.</p>`;
    root.querySelectorAll('[data-reg]').forEach(el=>el.addEventListener('click',()=>{state.registerPage=Number(el.dataset.reg);render();save();}));
    bind('hk-settings-edit',()=>{state.registerPage=1;render();save();});
    bind('hk-register',()=>{state.registered=true;state.registerPage=2;render();announce('샘플 입력 소스에 등록했어요. 실제 시스템 설정은 바뀌지 않아요.');save();});
    bind('hk-remove-old',()=>{state.oldRemoved=true;render();announce('샘플 목록에서 기존 두벌식을 뺐어요.');save();});
    bind('hk-select',()=>{if(!state.registered){state.registerPage=1;render();announce('먼저 하늘키보드를 추가해 주세요.');return;}state.selected=true;render();announce('샘플에서 하늘키보드를 선택했어요.');save();});
    if(state.selected && root.querySelector('#hk-select'))root.querySelector('#hk-select').disabled=true;
    if(root.querySelector('#hk-remove-old'))root.querySelector('#hk-remove-old').disabled=!state.registered;
  }
  function practiceMarkup(mode) {
    const manual=mode==='manual';
    return `<div class="hk-practice"><div class="hk-practice-head"><label for="hk-${mode}-input">${manual?'자유롭게 쓰고 직접 바꿔보세요':'여기에 직접 입력해 보세요'}</label><span class="hk-mode">${manual?'Shift + Space':'한글 모드 연습'}</span></div><input class="hk-input" id="hk-${mode}-input" type="text" maxlength="500" placeholder="${manual?'재가, m5, a16z 또는 원하는 단어':'apple, tangerine 또는 원하는 단어'}" autocomplete="off" autocapitalize="off" spellcheck="false" aria-describedby="hk-${mode}-message"><div class="hk-practice-bottom"><span class="hk-note">${manual?'단어 뒤에서 <kbd>⇧</kbd> + <kbd>Space</kbd>':'입력 후 <kbd>Space</kbd>를 눌러 주세요.'}</span>${button('hk-'+mode+'-convert',manual?'Shift + Space 눌러보기':'스페이스 눌러보기')}</div><p class="hk-practice-message" id="hk-${mode}-message" aria-live="polite">${manual?'한 번 더 누르면 다시 바뀌어요.':'영어로 바뀌어요. 한글모드는 그대로에요.'}</p></div>`;
  }
  function renderAutomatic() {
    stage.innerHTML=`<div class="hk-demo"><div><div class="hk-demo-label">apple 입력 시연</div><div class="hk-demo-word" id="hk-demo-word">메ㅔㅣㄷ → apple</div></div>${button('hk-demo','시연 보기')}</div>${practiceMarkup('auto')}<div class="hk-examples"><span>단어 넣어보기</span>${['apple','tangerine','cinestill'].map(w=>`<button type="button" class="cursor-interaction" data-example="${w}">${w}</button>`).join('')}</div><p class="hk-note">시연과 연습장은 따로 움직여요. 원하는 단어를 직접 입력해 보세요.<br>자동 변환은 샘플에 담긴 대표 단어를 지원해요.</p>`;
    connectInput('auto');
    bind('hk-auto-convert',()=>performAuto(true));
    bind('hk-demo',()=>{
      clearTimeout(demoTimer);demoRunning=true;const word=root.querySelector('#hk-demo-word'),control=root.querySelector('#hk-demo');control.disabled=true;let index=0;
      const tick=()=>{if(state.step!==2)return;if(index<5){word.textContent=engine.keysToHangul('apple'.slice(0,++index));demoTimer=setTimeout(tick,270);}else{word.textContent='apple';control.disabled=false;control.textContent='다시 보기';demoRunning=false;}};
      if(window.matchMedia('(prefers-reduced-motion: reduce)').matches){word.textContent='apple';control.disabled=false;demoRunning=false;}else tick();
    });
    root.querySelectorAll('[data-example]').forEach(el=>el.addEventListener('click',()=>{const input=root.querySelector('#hk-auto-input');input.value=engine.keysToHangul(el.dataset.example);practice.auto.value=input.value;practice.auto.pending=null;input.focus();input.setSelectionRange(input.value.length,input.value.length);}));
  }
  function renderManual() {
    stage.innerHTML=`${practiceMarkup('manual')}<div class="hk-dictionary" aria-label="설정의 개인 사전 미리보기"><div class="hk-dict-location"><strong>하늘키보드 설정 → 개인 사전</strong><span>샘플 설정</span></div><div class="hk-dict-tabs" aria-label="개인 사전 종류">${[['force','변환 추가'],['block','변환 금지'],['recent','되돌린 단어']].map(([key,label])=>`<button type="button" class="cursor-interaction" data-dict="${key}" aria-pressed="${state.dictTab===key}">${label}</button>`).join('')}</div><div class="hk-dict-pane" id="hk-dict-pane"></div></div><p class="hk-note">설정 → 영타 변환에서 단축키와 적용 범위를 바꿀 수 있어요.<br>터미널 등 일부 앱에서는 이 단축키로 글자를 바꿀 수 없어요.</p>`;
    connectInput('manual');bind('hk-manual-convert',performManual);
    root.querySelectorAll('[data-dict]').forEach(el=>el.addEventListener('click',()=>{state.dictTab=el.dataset.dict;updateDictionary();save();}));
    updateDictionary();
  }
  function targetBeforeCursor(input) {
    const end=input.selectionStart ?? input.value.length;
    const before=input.value.slice(0,end);
    const match=before.match(/([A-Za-z0-9가-힣ㄱ-ㅣ\u1100-\u11ff]+(?:['’][A-Za-z0-9가-힣ㄱ-ㅣ\u1100-\u11ff]+)*)([^A-Za-z0-9가-힣ㄱ-ㅣ\u1100-\u11ff]*)$/u);
    if(!match || match[1].length>64)return null;
    const start=end-match[0].length;
    return {start,end:start+match[1].length,word:match[1],cursor:end};
  }
  function replaceWord(input,target,replacement,field) {
    input.value=input.value.slice(0,target.start)+replacement+input.value.slice(target.end);
    const position=target.cursor+replacement.length-target.word.length;
    input.setSelectionRange(position,position);field.value=input.value;field.pending=null;
  }
  const message = (mode,text) => { const el=root.querySelector('#hk-'+mode+'-message');if(el)el.textContent=text; };
  function performAuto(addSpace=false) {
    const input=root.querySelector('#hk-auto-input');if(!input)return;
    const field=practice.auto;
    const target=targetBeforeCursor(input);
    let result='단어를 입력하고 스페이스를 눌러 주세요.';
    if(target){
      const raw=field.pending&&field.pending.start===target.start&&field.pending.text===target.word?field.pending.raw:(engine.hangulToKeys(target.word) || (/^[A-Za-z0-9'’]+$/.test(target.word)?target.word:null));
      const key=raw?normalize(raw):'';
      const blocked=personal.block.has(key)||personal.block.has(normalize(target.word));
      if(blocked)result='샘플의 변환 금지에 등록한 단어라 그대로 두었어요.';
      else if(raw&&(personal.force.has(key)||verifiedAuto.has(key))){
        replaceWord(input,target,raw,field);field.pair={a:target.word,b:raw,start:target.start};
        result='영어로 바뀌어요. 한글모드는 그대로에요.';
      }else result='이 글자는 그대로 두었어요. 4단계에서는 단축키로 직접 바꿔볼 수 있어요.';
    }
    if(addSpace){const at=input.selectionStart ?? input.value.length;input.value=input.value.slice(0,at)+' '+input.value.slice(at);input.setSelectionRange(at+1,at+1);}
    field.value=input.value;field.pending=null;message('auto',result);if(addSpace)input.focus();
  }
  function performManual() {
    const input=root.querySelector('#hk-manual-input');if(!input)return;
    const field=practice.manual,target=targetBeforeCursor(input);
    if(!target){message('manual','한글이나 알파벳이 든 단어 뒤에 커서를 두어 주세요.');input.focus();return;}
    let replacement=null;
    if(field.pair&&field.pair.start===target.start){if(target.word===field.pair.a)replacement=field.pair.b;else if(target.word===field.pair.b)replacement=field.pair.a;}
    if(replacement===null){replacement=engine.toggle(target.word);if(replacement!==null)field.pair={a:target.word,b:replacement,start:target.start};}
    if(replacement===null){message('manual','숫자만 있거나 한글과 영어가 섞인 단어는 그대로 두어요.');input.focus();return;}
    replaceWord(input,target,replacement,field);input.focus();
    message('manual',`${target.word} → ${replacement} · 한 번 더 누르면 다시 바뀌어요.`);
    if(/[A-Za-z]/.test(target.word)&&/[가-힣ㄱ-ㅣ]/.test(replacement)){
      personal.recent=personal.recent.filter(row=>row.english!==target.word);
      personal.recent.unshift({english:target.word,hangul:replacement});personal.recent=personal.recent.slice(0,10);updateDictionary();
    }
  }
  function connectInput(mode) {
    const input=root.querySelector('#hk-'+mode+'-input'),field=practice[mode];input.value=field.value;
    input.addEventListener('compositionstart',()=>{field.pending=null;field.pair=null;});
    input.addEventListener('input',event=>{field.value=input.value;field.pending=null;field.pair=null;if(mode==='auto'&&!event.isComposing&&/\s$/.test(input.value.slice(0,input.selectionStart)))performAuto(false);});
    input.addEventListener('keydown',event=>{
      if(event.key===' '&&event.shiftKey&&!event.ctrlKey&&!event.altKey&&!event.metaKey){event.preventDefault();if(!event.repeat && mode==='manual')performManual();else if(mode==='auto')message('auto','단축키 체험은 4단계의 자유 입력칸에서 할 수 있어요.');return;}
      if(mode!=='auto'||event.isComposing||event.ctrlKey||event.metaKey||event.altKey)return;
      const start=input.selectionStart,end=input.selectionEnd;
      const pending=field.pending;
      if(event.key==='Backspace'&&start===end&&pending&&start===pending.start+pending.text.length){
        event.preventDefault();pending.raw=pending.raw.slice(0,-1);const text=engine.keysToHangul(pending.raw)||'';
        input.value=input.value.slice(0,pending.start)+text+input.value.slice(start);input.setSelectionRange(pending.start+text.length,pending.start+text.length);pending.text=text;if(!text)field.pending=null;field.value=input.value;return;
      }
      if(event.key.length===1&&/^[A-Za-z0-9'’]$/.test(event.key)){
        event.preventDefault();const continues=pending&&start===end&&start===pending.start+pending.text.length&&input.value.slice(pending.start,start)===pending.text;
        const from=continues?pending.start:start,raw=(continues?pending.raw:'')+event.key;
        const text=engine.keysToHangul(raw);if(text===null)return;
        input.value=input.value.slice(0,from)+text+input.value.slice(end);input.setSelectionRange(from+text.length,from+text.length);field.pending={start:from,raw,text};field.value=input.value;field.pair=null;return;
      }
      if(event.key===' '&&!event.shiftKey){event.preventDefault();performAuto(true);return;}
      if(!['Shift','Alt','Control','Meta'].includes(event.key))field.pending=null;
    });
  }
  function updateDictionary() {
    if(state.step!==3)return;
    root.querySelectorAll('[data-dict]').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.dict===state.dictTab)));
    const pane=root.querySelector('#hk-dict-pane'),tab=state.dictTab;
    if(tab==='recent'){
      const row=personal.recent[0];
      pane.innerHTML=`<p>내가 한글로 되돌린 기록이에요. 기록만으로 다음 변환을 막지는 않아요.</p>${row?`<div class="hk-dict-edit"><span class="hk-dict-message">${esc(row.english)} → ${esc(row.hangul)}</span>${button('hk-block-recent','다시 바꾸지 않기')}</div>`:'<p>위 연습장에 apple을 입력하고 Shift + Space를 눌러 보세요.</p>'}`;
      if(row)bind('hk-block-recent',()=>{personal.block.add(normalize(row.english));message('manual','샘플의 변환 금지에 추가했어요. 단축키로 직접 바꾸는 것은 계속 가능해요.');state.dictTab='block';updateDictionary();save();});
    }else{
      const force=tab==='force',list=personal[tab];
      pane.innerHTML=`<p>${force?'영어로 바꾸고 싶은 단어를 등록해요. 3단계에서 결과를 체험할 수 있어요.':'자동으로 바뀌지 않았으면 하는 단어를 등록해요. 단축키 변환은 가능해요.'}</p><div class="hk-dict-edit"><input class="hk-input" id="hk-dict-input" type="text" maxlength="40" placeholder="${force?'예: mybrand':'예: apple'}" aria-label="${force?'변환 추가':'변환 금지'} 연습 단어" autocomplete="off" spellcheck="false">${button('hk-dict-add','추가')}</div><div class="hk-dict-message" id="hk-dict-result">${list.size?`샘플 등록: ${esc([...list].slice(-3).join(', '))}`:'추가한 단어가 없어요.'}</div>`;
      const add=()=>{const raw=root.querySelector('#hk-dict-input').value,key=normalize(raw);const valid=force?/^[a-z0-9]+(?:'[a-z0-9]*)?$/.test(key)&&/[a-z]/.test(key):/^[a-z0-9가-힣ㄱ-ㅣ]+(?:'[a-z0-9가-힣ㄱ-ㅣ]*)?$/.test(key)&&/[a-z가-힣ㄱ-ㅣ]/.test(key);if(!valid){root.querySelector('#hk-dict-result').textContent='공백 없이 한 단어를 입력해 주세요.';return;}list.add(key);updateDictionary();announce('샘플 사전에만 추가했어요. 실제 개인 사전은 바뀌지 않아요.');};
      bind('hk-dict-add',add);root.querySelector('#hk-dict-input').addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.isComposing){event.preventDefault();add();}});
    }
    decorate();
  }
  function renderMenu() {
    stage.innerHTML=`<div class="hk-desktop"><div class="hk-menubar"><span class="hk-menu-caption">Mac 메뉴바</span>${icon('wifi')}<button id="hk-menu-open" type="button" class="hk-menu-trigger cursor-interaction" aria-expanded="${state.menu}" aria-label="하늘키보드 메뉴 보기">${assets.menuIcon} 한</button><span>오후 2:30</span></div><div class="hk-menu" ${state.menu?'':'hidden'}><button type="button" class="cursor-interaction" id="hk-menu-settings">${icon('settings-2')} 하늘키보드 설정…</button><button type="button" class="cursor-interaction" id="hk-menu-replay">${icon('circle-play')} 시작하기 다시 보기…</button><button type="button" class="cursor-interaction" id="hk-menu-support">${icon('heart')} 하늘키보드 응원하기…</button></div></div><p class="hk-free">${icon('heart')} 하늘키보드는 영원히 무료입니다.</p><div class="hk-support"><p class="hk-note">개발을 응원하고 싶다면 후원은 자유롭게 선택해 주세요.</p><button type="button" class="hk-text-button cursor-interaction" id="hk-support">후원으로 응원하기</button></div>`;
    bind('hk-menu-open',()=>{state.menu=!state.menu;render();save();});bind('hk-menu-replay',()=>go(0));
    bind('hk-menu-settings',()=>{go(3);announce('설정 → 개인 사전의 미리보기로 이동했어요.');});
    const support=()=>announce('후원 방법은 준비 중이에요. 후원 여부와 관계없이 무료로 사용할 수 있어요.');bind('hk-menu-support',support);bind('hk-support',support);
  }
  back.addEventListener('click',()=>go(state.step-1));next.addEventListener('click',()=>{if(state.step<4)go(state.step+1);else announce('체험을 마쳤어요. 실제 제품에서는 여기서 시작하기 창이 닫혀요.');});
  window.addEventListener('openai:set_globals',event=>{const incoming=event.detail&&event.detail.globals&&event.detail.globals.widgetState;if(incoming&&hydrate(incoming)){clearTimeout(demoTimer);demoRunning=false;render();}});
  hydrate(window.openai&&window.openai.widgetState);render();
  if(globalThis.Tweak){const tweak=new Tweak({container:win,onChange:()=>{win.dataset.glass=String(design.glass);win.style.colorScheme=design.appearance==='system'?'light dark':design.appearance;}});tweak.addToggle(design,'glass',{label:'유리 배경'});tweak.addSelect(design,'appearance',{label:'화면 밝기',options:[{label:'시스템 설정 따르기',value:'system'},{label:'밝게',value:'light'},{label:'어둡게',value:'dark'}]});}
})();
