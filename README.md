# LNQ

Limbo x86 (Android용 QEMU 에뮬레이터)를 **QEMU 11**로 포팅하기 위한 조사·계획 저장소.

## 문서

- [`docs/limbo-x86-qemu11-port-plan.md`](docs/limbo-x86-qemu11-port-plan.md) — 포팅 계획서

## 스크립트

- [`scripts/fetch-sources.sh`](scripts/fetch-sources.sh) — Limbo 소스, QEMU 11.0.3, 크로스 빌드 의존성 취득

```sh
./scripts/fetch-sources.sh [작업디렉터리]   # 기본값: ./work
```

## 요약

| 항목 | 값 |
|---|---|
| 대상 | [limboemu/limbo](https://github.com/limboemu/limbo) `master` (앱 v6.0.1) |
| 현재 번들 QEMU | **5.1.0** (레거시 기기용 2.9.1) — 앱 버전 6.0.1과 혼동 주의 |
| 목표 QEMU | **11.0.3** (stable) |
| 최대 난관 | QEMU 5.2에서 Makefile → Meson 전환, QEMU 11.0에서 32비트 호스트 지원 삭제 |
| 지원 ABI | `arm64-v8a`, `x86_64` 만 (`armeabi-v7a`, `x86`은 QEMU 11에서 빌드 불가) |
| 예상 기간 | 13~15주 (1인) |
