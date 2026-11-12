#!/usr/bin/env python3
"""2026-11-12 (#228, 리뷰 build-release-docs-F-6): check_doc_links.py 대조군 — 임시 git 트리에서 깨진 링크가 실제로 잡히는지.
HTML 속성(<img src> · <a href>)과 참조식 링크(`[이름]: 경로`)까지 본다. 네트워크·빌드 없음."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("check_doc_links", HERE / "check_doc_links.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

DOC = """# 시험
<p align="center"><img src="docs/media/banner.jpg" alt="배너" width="600"></p>
<a href='docs/guide.md'>안내</a> · [글 링크](docs/guide.md) · [참조식][guide] · [외부](https://example.com)
<img src="https://example.com/x.png"> <a href="#쪽지">쪽지</a> <a href="mailto:a@example.com">메일</a>

[guide]: docs/guide.md
[banner-ref]: <docs/media/banner.jpg> "제목"
[web]: https://example.com/page

```
<img src="docs/코드블록은-안-본다.png">
```
"""
cases = []
with tempfile.TemporaryDirectory(prefix="haneul-doc-links-") as work:
    root = Path(work)
    subprocess.run(["git", "-C", work, "init", "-q"], check=True)
    (root / "docs/media").mkdir(parents=True)
    (root / "docs/media/banner.jpg").write_bytes(b"x")
    (root / "docs/guide.md").write_text("# 안내\n")
    (root / "README.md").write_text(DOC)
    subprocess.run(["git", "-C", work, "add", "-A"], check=True)
    files = module.tracked_files(root)
    checked, broken = module.broken_links(root, files)
    cases.append(("모두 추적 중", broken == [] and checked == 5, (checked, broken)))
    # 배너 이미지를 추적에서 빼면 HTML <img src>와 참조식 정의가 둘 다 잡혀야 한다.
    subprocess.run(["git", "-C", work, "rm", "-q", "--cached", "docs/media/banner.jpg"], check=True)
    files = module.tracked_files(root)
    checked, broken = module.broken_links(root, files)
    targets = sorted(target for _, _, target in broken)
    cases.append(("HTML 이미지·참조식 이미지 깨짐", targets == ["docs/media/banner.jpg", "docs/media/banner.jpg"], targets))
    subprocess.run(["git", "-C", work, "add", "docs/media/banner.jpg"], check=True)
    subprocess.run(["git", "-C", work, "rm", "-q", "--cached", "docs/guide.md"], check=True)
    files = module.tracked_files(root)
    checked, broken = module.broken_links(root, files)
    cases.append(("href·마크다운·참조식 문서 링크 깨짐", len(broken) == 3, broken))
for name, ok, detail in cases:
    assert ok, (name, detail)
    print(f"PASS: {name}")
print(f"Doc links checker: {len(cases)} passed, 0 failed")
