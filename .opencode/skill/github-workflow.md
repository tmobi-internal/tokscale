# GitHub Workflow

GitHub 계정 및 리모트 사용 규칙.

## Accounts

| Account    | Usage                              |
|------------|------------------------------------|
| `leecoder` | 기본 계정. 대부분의 작업에 사용     |
| `t1000040` | `tmobi-internal` 레포 작업 전용    |

## Rules

1. **기본**: `leecoder` 계정 활성 상태로 작업한다.
2. **PR 생성**: `leecoder` fork에서 upstream(`junhoyeo/tokscale`)으로 PR을 올린다.
   - `gh pr create --repo junhoyeo/tokscale --base main --head leecoder:<branch>`
3. **push**: 브랜치를 `leecoder` remote에 push한다.
4. **tmobi-internal 작업 시**: `gh auth switch --user t1000040`으로 전환 후 `tmobi` remote로 push/PR 작업.
   - 작업 완료 후 반드시 `gh auth switch --user leecoder`로 복원.

## Remote mapping

| Remote     | URL                                          |
|------------|----------------------------------------------|
| `origin`   | `https://github.com/junhoyeo/tokscale.git`   |
| `leecoder` | `https://github.com/leecoder/tokscale.git`   |
| `tmobi`    | `https://github.com/tmobi-internal/tokscale.git` |

## Quick reference

```bash
# 일반 작업 (leecoder 계정)
gh auth switch --user leecoder
git push leecoder <branch>
gh pr create --repo junhoyeo/tokscale --base main --head leecoder:<branch>

# tmobi-internal 작업 (t1000040 계정)
gh auth switch --user t1000040
git push tmobi <branch>
gh pr create --repo tmobi-internal/tokscale --base main --head <branch>
gh auth switch --user leecoder  # 복원
```
