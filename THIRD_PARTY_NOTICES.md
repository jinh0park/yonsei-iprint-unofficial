# 구성물과 라이선스

- 앱 구현과 이 저장소 전용 빌드·검증 도구: GNU Affero General Public License v3.
  전문은 루트 `LICENSE`에 있습니다.
- Ghostscript 10.0.0: Artifex Software 및 원본에 표시된 기여자.
  원본의 `third_party/ghostscript-10.0.0/LICENSE`와 `doc/COPYING`을 보존했습니다.
- Ghostscript에 동봉된 타사 라이브러리·CMap·폰트·문서: 각 디렉터리에 포함된
  개별 저작권·라이선스 문서를 유지합니다. 이를 루트 라이선스로 대체하지 않습니다.
  특히 `DroidSansFallback.NOTICE`, `Resource/CMap` 및 FreeType, JPEG, PNG, TIFF,
  zlib 등 원본 디렉터리의 고지를 참고하세요.
- `native/RegistrationTerms.txt`: 원본 서비스가 제시하는 가입 약관 고지입니다.
  서비스 운영자의 권리를 유지하며, 이 저장소의 코드 라이선스 적용 대상이 아닙니다.
- 아이프린트의 원본 Windows 설치파일·실행파일·DLL과 삼성 Intel 인쇄 필터는 포함하지 않습니다.
  Ghostscript 원본에 들어 있던 예제·부속 도구는 원본 자료로 보존하며 Mac 앱에 포함하지 않습니다.

Ghostscript 원본 출처와 원본 아카이브 SHA-256은 `third_party/UPSTREAM.json`에
있습니다. Mac용 빌드 수정 사항은 `patches/README.md`에 설명했습니다.
