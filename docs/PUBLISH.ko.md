# GitHub에 올리기

이 폴더는 로컬 Git 저장소로 초기화되어 있고 공개할 소스가 스테이징되어 있습니다.
원격 저장소 연결이나 GitHub 업로드는 하지 않았습니다.
`build/`, `dist/`, 캐시와 개인 설정 파일은 커밋 대상에서 제외됩니다.
원본 Ghostscript 안의 `.gitignore` 때문에 소스가 빠지지 않도록 전체 원본을
명시적으로 스테이징했습니다. 초기 상태에서 `git reset`으로 스테이징을 취소했다면
다시 `git add -f third_party/ghostscript-10.0.0`도 실행하세요.

1. 개인 GitHub 계정에 **공개(Public)** 빈 저장소를 만듭니다.
   이 폴더에 README와 라이선스가 있으므로 GitHub에서 같은 파일을 새로 만들 필요는 없습니다.
2. 이 폴더에서 아래 명령을 실행합니다. `YOUR-USER`와 저장소 이름을 실제 값으로 바꾸세요.

```sh
git status --short
git commit -m "Publish v0.1.14 corresponding source"
git tag v0.1.14
git remote add origin https://github.com/YOUR-USER/yonsei-iprint.git
git push -u origin main
git push origin v0.1.14
```

Git이 이름과 이메일 설정을 요청하면 본인이 사용할 커밋 작성자 정보로 설정한 뒤
커밋하면 됩니다. 이 폴더를 준비하면서 작성자나 원격 주소를 임의로 지정하지 않았습니다.

## 카페 게시글

설치용 `연세-iPrint-Native-0.1.14-비공식-카페용.dmg` 하나를 첨부하고,
실제 공개 저장소의 이 버전 링크를 다음처럼 안내하세요.

> 버전 0.1.14 전체 소스 코드·수정사항·빌드 방법 및 라이선스:
> https://github.com/YOUR-USER/yonsei-iprint/tree/v0.1.14

위 URL은 예시입니다. 올린 뒤 로그인하지 않은 상태에서도 해당 링크에서
전체 소스를 내려받을 수 있는지 확인하고 제공 상태를 유지하세요.
일반 사용자는 소스를 별도로 내려받지 않아도 설치할 수 있습니다.

GitHub에서는 앱 설치파일이나 중간 빌드 결과를 이 저장소에 커밋하지 않아도 됩니다.
`docs/DISTRIBUTED_BINARY.json`에는 기존 카페용 설치 DMG의 버전·크기·해시를 기록했습니다.
