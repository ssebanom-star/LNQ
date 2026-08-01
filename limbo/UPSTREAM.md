# Upstream provenance

이 디렉터리는 [limboemu/limbo](https://github.com/limboemu/limbo) 의 포크이며,
QEMU 11 포팅 작업을 위해 이 저장소에 벤더링되었다.

| 항목 | 값 |
|---|---|
| Upstream | https://github.com/limboemu/limbo |
| Branch | `master` (= `Branch_Branch_6.0.1`) |
| Commit | `887c6a68cd6b414377d7f8071bc12bbc16e59809` |
| 가져온 날짜 | 2026-08-01 |
| 라이선스 | GPL v2 (루트 `COPYING` 참조) |

Limbo 는 GPLv2 이므로 이 포크의 변경사항도 GPLv2 로 배포된다.

## 이 포크의 변경 방향

[`../docs/limbo-x86-qemu11-port-plan.md`](../docs/limbo-x86-qemu11-port-plan.md) 참조.

요약:

- 번들 QEMU 를 **5.1.0 → 11.0.3** 으로 교체
- QEMU 11.0 이 32비트 호스트 지원을 삭제했으므로 **`arm64-v8a` / `x86_64` 전용**
- 네이티브 빌드를 Makefile 주입 방식에서 **Meson/Ninja** 방식으로 전환
- `minSdkVersion` 을 21 → **28** 로 상향 (bionic 이 API 28 부터 `iconv` 를 제공하므로
  glib 2.66+ 크로스 빌드에 필요하고, Limbo 의 iconv/intl 셰임을 제거할 수 있다)
- gcc(NDK r14b) 경로 삭제, clang(NDK r27+) 전용

## 업스트림과의 차이를 확인하려면

```sh
git clone --branch master https://github.com/limboemu/limbo.git /tmp/limbo-upstream
git -C /tmp/limbo-upstream checkout 887c6a68cd6b414377d7f8071bc12bbc16e59809
diff -ru /tmp/limbo-upstream limbo --exclude=.git
```
