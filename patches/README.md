# Ghostscript Mac 빌드 수정 사항

원본은 `third_party/ghostscript-10.0.0/`에 보존했습니다. 빌드 스크립트가 이를
`build/ghostscript-10.0.0/`에 복사한 뒤 다음 두 파일만 바꿉니다.

- `zlib/zutil.h`
- `libpng/pngpriv.h`

`TARGET_OS_MAC`을 검사하던 구형 Mac OS용 분기에 `!defined(__APPLE__)` 조건을
추가했습니다. 현대 macOS SDK에서도 참이 되는 매크로 때문에 구형 헤더·정의가
선택되는 문제를 피하기 위한 수정입니다. 수정한 파일 전체를 이 폴더에 보존했습니다.

구성 및 컴파일 명령은 기존 배포본의 빌드 구성과 같습니다.

```sh
./configure --prefix=/iprint-bundled --without-x --disable-cups --disable-gtk \
  --disable-fontconfig --without-tesseract --without-libidn
make -j4 CFLAGS_STANDARD='-O2 -DNDEBUG -mmacosx-version-min=13.0' \
  XCFLAGS='-Wno-error=declaration-after-statement' XLDFLAGS='-mmacosx-version-min=15.0'
```

앱 프런트엔드는 Apple SDK의 Foundation/AppKit/PDFKit/UniformTypeIdentifiers와
CommonCrypto를 사용합니다. 새 저장소용 빌드·패키징 도구는 프로젝트 루트에서
상대 경로로 동작하며 원래 개인 작업 폴더에 의존하지 않습니다.
