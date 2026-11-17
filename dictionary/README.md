# 사전 정본과 기록 (dictionary)

> **기준일:** 2026-11-17 · 폴더 정리(#267)로 `dict_work/`에서 이름을 바꾸고, 날짜를 붙인 기록을 `records/`로 옮겼습니다.

번들 영어 사전을 만들고 검역할 때 쓰는 정본과 그 근거 기록을 둡니다. 앱에 실제로 들어가는 낱말 파일은 [`Resources/IM/`](../Resources/IM)에 있습니다.

| 파일 | 하는 일 |
|---|---|
| [`dict_manifest.tsv`](dict_manifest.tsv) | 번들 영어 사전 목록의 정본입니다. 런타임·테스트·검역이 함께 읽습니다. |
| [`exclusions.txt`](exclusions.txt) | 생성기가 항상 빼는 제외 목록의 정본입니다. 없으면 생성기가 멈춥니다. |
| [`scowl_exclusions_alljamo4.txt`](scowl_exclusions_alljamo4.txt) | SCOWL에서 빼는 4자모 이하 전부-자모 낱말입니다(초성체 보호). |
| [`exclusion_overlap_baseline.tsv`](exclusion_overlap_baseline.tsv) | 배포 사전과 제외 목록이 겹치는 줄의 기준선입니다. 새 겹침이 생기면 테스트가 실패합니다. |
| [`SOURCE_FORMATS.md`](SOURCE_FORMATS.md) | 원본 자료의 형식과 다시 만드는 방법입니다. |
| [`records/`](records) | 날짜를 붙인 검역·등록 기록입니다. |

- `records/`의 파일은 사전 주석, `Resources/IM/phonetic_dictionary.json`의 `record` 값, 테스트가 경로로 가리킵니다. 이름을 바꾸거나 옮기지 않고 새 기록을 더하기만 합니다.
- 새 기록은 `YYYY-MM-DD-<주제>.<csv|tsv|md|txt>` 이름으로 `records/`에 넣습니다.
- 사전을 고친 뒤에는 `python3 scripts/build_english_table.py`로 합친 표를 다시 만들고 `--check`로 확인합니다.
