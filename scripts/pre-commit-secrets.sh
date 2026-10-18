#!/bin/sh
# 커밋 직전에 비밀 정보가 들어갔는지 검사한다. 설치: cp scripts/pre-commit-secrets.sh .git/hooks/pre-commit
# 정말 의도한 경우에만 `git commit --no-verify`로 건너뛴다.
bad=0

# 1) 비밀 파일 이름
for f in $(git diff --cached --name-only --diff-filter=ACM); do
  case "$f" in
    .env|.env.*|*/.env|*/.env.*|*.env|*kma_key.lua|*.secret|secrets/*|*/secrets/*)
      echo "차단: 비밀 파일은 커밋할 수 없습니다 -> $f"; bad=1 ;;
  esac
done

# 2) 키처럼 보이는 문자열 (키 이름 뒤에 영문/숫자 24자 이상)
hits=$(git diff --cached -U0 | grep -E '^\+' | grep -v '^+++' | grep -E -i '(service_?key|api_?key|token|secret|password)["'"'"' ]*[=:][ "'"'"']*[A-Za-z0-9%+/=_-]{24,}')
if [ -n "$hits" ]; then
  echo "차단: 키/토큰처럼 보이는 문자열이 있습니다 (값은 표시하지 않음):"
  echo "$hits" | sed -E 's/([=:][ "'"'"']*)[A-Za-z0-9%+\/=_-]{24,}/\1[숨김]/' | head -5
  bad=1
fi

if [ "$bad" -ne 0 ]; then
  echo "커밋을 중단했습니다. 키는 .env.local 같은 무시되는 파일에만 두세요."
  exit 1
fi
exit 0
