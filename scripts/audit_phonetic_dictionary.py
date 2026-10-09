#!/usr/bin/env python3
"""2026-10-09 / #84: 발음 사전 수량·중복·번호 범위를 원본 JSON에서 검증한다."""
import collections
import hashlib
import json
from pathlib import Path
import re
import unicodedata

root = Path(__file__).resolve().parent.parent
path = root / 'Resources/IM/phonetic_dictionary.json'
data = path.read_bytes()
document = json.loads(data)
assert document['schemaVersion'] == 1
entries = document['entries']
taxonomy = {c['id']: c['subcategories'] for c in document['categories']}
keys = [e['hangul'] for e in entries]
assert len(keys) == len(set(keys)), '중복 한글 표기'
assert 'people' not in taxonomy, '인물·음악 그룹 범주는 지원하지 않음'
for e in entries:
    assert e['category'] in taxonomy, e
    assert e['subcategory'] in taxonomy[e['category']], e
    assert re.fullmatch(r'[가-힣0-9]+', e['hangul']), e
    assert unicodedata.normalize('NFC', e['hangul']) == e['hangul'], e
    assert re.fullmatch(r'[A-Za-z0-9]+(?:[ -][A-Za-z0-9]+)*', e['english']), e
index = {e['hangul']: e['english'] for e in entries}
for hangul, english in {'선물': 'gift', '선물거래': 'futures trading', '선물계약': 'futures contract',
                        '지수': 'index', '메시': 'mesh', '줌': 'zoom', '디스코드': 'Discord'}.items():
    assert index[hangul] == english, ('지정 의미/기존 대응 충돌', hangul)
for wrong in ['겔럭시', '에플', '갤럭시024', '갤럭시11', '갤럭시19', '갤럭시30', '아이폰9', '아이폰10', '아이폰22']:
    assert wrong not in keys, wrong
expected_phones = {}
for family, ko, en in [('galaxy', '갤럭시', 'Galaxy'), ('iphone', '아이폰', 'iPhone')]:
    policy = document['phonePolicy'][family]
    confirmed = policy['confirmedNumbers']
    reserved = policy['reservedNumbers']
    assert reserved == list(range(max(confirmed) + 1, max(confirmed) + 4))
    for field, category in [('confirmedNumbers', 'phone-confirmed'), ('reservedNumbers', 'phone-reserved')]:
        for number in policy[field]:
            expected_phones[ko + str(number)] = (en + str(number), category)
actual_phones = {e['hangul']: (e['english'], e['category']) for e in entries if e['category'].startswith('phone-')}
assert actual_phones == expected_phones, '번호 정책과 실제 사전 불일치'
print(json.dumps({
    'reviewedOn': document['reviewedOn'],
    'sha256': hashlib.sha256(data).hexdigest(),
    'bytes': len(data),
    'uniqueHangulEntries': len(keys),
    'uniqueEnglishOutputs': len({e['english'] for e in entries}),
    'categories': dict(collections.Counter(e['category'] for e in entries)),
    'subcategories': dict(collections.Counter(e['category'] + '/' + e['subcategory'] for e in entries)),
    'baseEntries': len(keys) - len(actual_phones),
    'numericAliases': len(actual_phones),
}, ensure_ascii=False, indent=2))
