# GitHub 소스와 설치본 공유

공개 소스 저장소: [jinh0park/yonsei-iprint-unofficial](https://github.com/jinh0park/yonsei-iprint-unofficial)

- `main`: 최신 소스 및 사용 안내·현장 검증 기록
- `v0.1.14`: 기존 0.1.14 앱에 대응하는 소스 태그(보존)
- `v0.1.15`: 회원가입 오류 진단판에 대응하는 소스 태그

기존 버전 태그는 보존합니다. 같은 실행파일에 대한 후속 검증 결과와 문서 변경은
`main`에 기록하며, 앱 코드를 변경해 새 버전을 배포하면 해당 버전의 소스 태그도 만듭니다.
현재 원격 이름은 `origin`이고 작업 브랜치는 `main`입니다.

## 카페 게시글

설치용 `연세-iPrint-Native-0.1.15-비공식-공증.dmg`를 첨부하고,
다음과 같이 같은 버전의 전체 소스 링크를 안내하세요.

> 개인 제작 비공식 Mac 호환 클라이언트입니다.
> 버전 0.1.15 전체 소스 코드·Ghostscript 원본·수정사항·빌드 방법 및 라이선스:
> https://github.com/jinh0park/yonsei-iprint-unofficial/tree/v0.1.15
> 최신 사용 안내·현장 검증 기록:
> https://github.com/jinh0park/yonsei-iprint-unofficial

일반 사용자는 설치를 위해 소스를 별도로 내려받지 않아도 됩니다.
전체 소스가 로그인 없이 무료로 제공되는지 확인하고 제공 상태를 유지하세요.
`docs/DISTRIBUTED_BINARY.json`에서 설치파일의 이름·크기·SHA-256을 확인할 수 있습니다.

## 소스를 갱신할 때

`build/`, `dist/`, 캐시와 개인 설정 파일은 커밋하지 않습니다.
Ghostscript 원본 안의 `.gitignore`에 걸리는 파일도 있으므로 원본 자료를 새로 추가할 때는
필요한 파일이 모두 추적되는지 확인하세요. 전체 소스 목록의 해시도 함께 갱신한 뒤
`python3 tools/check_source.py`와 `git diff --check`로 확인합니다.

```sh
git status --short
git diff --cached
git commit -m "Describe the source or documentation update"
git push origin main
```
