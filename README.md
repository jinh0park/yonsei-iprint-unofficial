# 연세 iPrint Native (비공식)

Apple Silicon Mac용 개인 제작 비공식 아이프린트 클라이언트의 **0.1.14 소스 배포본**입니다.
macOS 15 이상과 연세대 캠퍼스 네트워크에서 사용합니다. 학교·아이프린트·삼성의 공식 앱은 아닙니다.

PDF 첫 장 미리보기, 로그인·로그아웃, 회원가입, 읽기 전용 회원정보 확인,
A4 흑백 인쇄, 단면·양면 방향 선택과 1~99부 설정을 제공합니다.
서버 대기 문서 조회·새로고침·선택 삭제(학교 서버 실동작 미확인)도 제공합니다.
PDF를 글자 외곽선 변환 및 압축한 뒤 인쇄 서버로 보냅니다.

일반 사용자는 소스를 빌드할 필요 없이 별도로 제공된 설치 DMG를 받으면 됩니다.
공유된 설치본의 버전·SHA-256은 [배포본 기록](docs/DISTRIBUTED_BINARY.json)에 있습니다.

## 폴더 구성

| 경로 | 내용 |
|---|---|
| `native/` | 배포한 0.1.14 앱 소스와 합성 입력용 검사 코드 |
| `third_party/ghostscript-10.0.0/` | 생략 없이 보존한 Ghostscript 10.0.0 원본 전체 |
| `patches/ghostscript/` | Mac에서 빌드하기 위해 수정한 두 파일 |
| `assets/AppIcon.icns` | 앱 빌드에 필요한 아이콘 |
| `tools/` | 이 저장소만으로 빌드·패키징하는 스크립트 |
| `docs/original-workspace/` | 기존 배포본에 동봉했던 원래 작업환경용 스크립트·안내의 보존본 |
| `LICENSE`, `THIRD_PARTY_NOTICES.md` | AGPLv3 및 타사 구성물 고지 |

`native/main.m`, `NativeCore.m`, `NativeCore.h`, 가입 약관과 기존 테스트 코드는
배포본과 같은 내용입니다. 저장소 구성에 맞춘 빌드 도구와 문서를 추가했습니다.
아이프린트의 원본 Windows 설치파일·EXE/DLL, Wine, Rosetta, 계정 정보,
인쇄 문서와 시험 로그는 포함하지 않습니다. Ghostscript 원본의 부속 예제·도구는
원본 자료의 일부로 보존하지만 Mac 앱에 묶어 실행하지 않습니다.
테스트에 쓰는 `NativeTest`와 `Native-Test-17`은 합성 시험값입니다.

## 빌드

Apple Silicon Mac, Xcode Command Line Tools, Python 3와 `make`가 필요합니다.
이 저장소에 모든 Ghostscript 소스와 수정 자료를 포함했으므로 빌드 중 소스를
인터넷에서 추가로 다운로드하지 않습니다.

```sh
python3 tools/build.py --jobs 4
```

처음에는 `build/`에 원본 트리를 복사하고 Mac용 수정 사항을 적용해 Ghostscript를
컴파일합니다. 이어서 AppKit 클라이언트를 컴파일하고 필요한 리소스를 묶습니다.
완성된 앱은 `dist/연세 iPrint Native (비공식).app`에 있습니다.
같은 입력으로 다시 실행하면 완료된 Ghostscript 빌드를 재사용합니다.
다시 빌드하려면 `--force-ghostscript`를 지정합니다.

앱은 ad-hoc 서명되며 Apple Developer ID 서명·공증은 하지 않습니다.
소스가 같아도 컴파일러·SDK·빌드 시각 때문에 기존 배포 바이너리와 바이트 단위로
동일한 결과를 보장하지 않습니다. 앱 실행에는 Python, Wine, Rosetta가 필요 없습니다.

원래 빌드 구성과 두 수정 파일의 설명은 [빌드 변경 내역](patches/README.md)에 있습니다.

## 로컬 검사

앱을 먼저 빌드한 다음 다음 명령으로 합성 입력 검사를 실행할 수 있습니다.
학교 계정이나 실제 프린터를 사용하지 않습니다. 프로토콜 검사는 로컬 TCP 포트를 엽니다.

```sh
export IPRINT_NATIVE_APP="$PWD/dist/연세 iPrint Native (비공식).app"
export IPRINT_NATIVE_BINARY="$IPRINT_NATIVE_APP/Contents/MacOS/iPrintNative"

"$IPRINT_NATIVE_BINARY" --self-test native/tests/oracle-vectors.json
python3 native/tests/test_protocol.py
python3 native/tests/test_registration_protocol.py
python3 native/tests/test_profile_protocol.py
python3 native/tests/test_queue_protocol.py

mkdir -p build/checks
xcrun clang -fobjc-arc -fblocks -fno-modules -framework Foundation -arch arm64 \
  -I native native/NativeCore.m native/tests/print_options_tests.m \
  -o build/checks/print_options_tests
python3 native/tests/test_print_options.py \
  build/checks/print_options_tests build/checks/print-options
```

루트의 [소스 목록](SOURCE_MANIFEST.sha256)은 실제 소스 파일을 확인하기 위한 해시 목록입니다.
`python3 tools/check_source.py`로 확인할 수 있습니다.
[검증 기록](docs/VERIFICATION.json)은 소스 공개용 폴더 준비 시의 빌드·검사 결과입니다.

## 실제 동작 확인 범위

이전 버전에서 학교 서버 로그인·가입·한글 이름 표시와 실제 흑백 출력을 확인했습니다.
양면·여러 부수 설정은 로컬 변환·전송 검사를 통과했지만 학교 복합기의 실제 출력과
과금은 아직 확인하지 않았습니다. 대기 문서 조회·삭제는 로컬 시험만 통과했으며
학교 서버에서는 아직 확인하지 않았습니다. 사용 방법은 [사용 안내](docs/Usage.ko.md)를 참고하세요.

회원정보 수정·비밀번호 변경·잔액 충전은 제공하지 않습니다. 비밀번호는 파일이나
키체인에 저장하지 않고 로그아웃·종료 때 입력란에서 지웁니다.
프로토콜 조사 기록은 [native/Protocol.md](native/Protocol.md)에 있습니다.

## 라이선스와 배포

이 저장소의 앱 구현과 새 빌드 도구는 [GNU AGPL v3](LICENSE)로 제공합니다.
Ghostscript와 그 안의 타사 라이브러리·폰트·문서는 각 원본 라이선스 및 고지를
그대로 유지합니다. 원래 서비스의 가입 약관은 별도 제3자 고지이며 이 프로젝트의
코드 라이선스로 다시 허가되는 문서가 아닙니다.

설치 DMG를 공유할 때 이 버전의 전체 소스를 무료로 받을 수 있는 공개 링크를
설치파일 옆에 안내하세요. 일반 사용자가 소스를 함께 내려받을 필요는 없습니다.
게시글 예시와 GitHub 업로드 순서는 [PUBLISH.ko.md](docs/PUBLISH.ko.md)에 있습니다.

공개 소스 URL을 명시한 새 설치 DMG를 만들려면 다음처럼 실행합니다.
아래 URL은 예시이므로 실제 공개한 버전의 주소로 바꿔야 합니다.

```sh
python3 tools/package.py \
  --source-url 'https://github.com/YOUR-USER/yonsei-iprint/tree/v0.1.14'
```
