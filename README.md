# mac-reaper

macOS 고아 프로세스 자동 정리 도구.

opencode, zsh, fzf 등이 부모 프로세스 없이 고아로 누적되어 메모리/CPU를 잠식하는 문제를 해결합니다.

## 동작 원리

1. **탐지**: PPID=1 (launchd에 입양된 고아) 프로세스 중 설정된 패턴에 매칭되는 것을 찾음
2. **필터**: 최소 1시간 이상 된 프로세스만 대상 (갓 생성된 건 건드리지 않음)
3. **조건**: `children=0` 조건이 있으면 자식 프로세스 없는 것만 kill (활성 세션 보호)
4. **정리**: SIGTERM → 3초 대기 → SIGKILL (graceful shutdown 우선)
5. **재검증**: kill 직전에 `comm/ppid/age/children=0/start_token/command_hash` 조건 재검증
6. **락**: 동시 실행 방지를 위해 run lock 사용
7. **로깅**: `~/.mac-reaper/logs/YYYY-MM-DD.log` + macOS syslog

## 설치

```bash
./install.sh
```

launchd agent로 등록됩니다:
- **매 3시간** 자동 실행
- **로그인 시** 자동 실행
- **재부팅 후** 자동 복구

## 사용

```bash
# 수동 실행
./reap.sh

# Dry-run (탐지만, kill 안 함)
REAPER_DRY_RUN=1 ./reap.sh
```

## 테스트

```bash
./tests/run.sh
```

테스트 범위:
- detector 시간 파싱/필터링/정확 매칭/중복 제거/command hash
- reaper 상태/사유(reason) 매핑/start token 검증/kill budget
- lock 충돌/복구(누락 pid, dead pid, unrelated live pid)
- 설정 검증 fail-fast (invalid config)

## 제거

```bash
./uninstall.sh
```

## 설정

`conf/defaults.conf` 에서 수정:

| 변수 | 기본값 | 설명 |
|---|---|---|
| `REAPER_DRY_RUN` | `0` | 1이면 탐지만 |
| `REAPER_LOCK_DIR` | `~/.mac-reaper/run.lock` | 동시실행 방지 lock 위치 |
| `REAPER_ORPHAN_MIN_AGE_SEC` | `3600` | 최소 경과 시간 (초) |
| `REAPER_MAX_KILLS` | `200` | 1회 실행 최대 kill 수 |
| `REAPER_GRACE_WAIT_SEC` | `3` | TERM 후 대기 시간(초) |
| `REAPER_LOG_RETAIN_DAYS` | `30` | 로그 보관 일수 |
| `REAPER_TARGETS` | opencode, zsh, fzf | 정리 대상 |

## 구조

```
mac-reaper/
├── reap.sh              # 엔트리포인트
├── install.sh           # launchd 등록
├── uninstall.sh         # launchd 해제
├── conf/
│   └── defaults.conf    # 설정
├── lib/
│   ├── detector.sh      # 고아 탐지
│   ├── reaper.sh        # kill 로직
│   └── reporter.sh      # 로깅
└── launchd/
    └── net.kilhyeonjun.mac-reaper.plist
```
