#!/bin/bash

# Pro-tip:
# echo "./lint.sh" > .git/hooks/pre-commit
# chmod +x .git/hooks/pre-commit

FAILED_HEADER="\033[1;31mFAILED:\033[0m"
BAD_FILE="/tmp/${PWD##*/}.bad"
GOOD_FILE="/tmp/${PWD##*/}.good"

COMMIT_ID=$(git rev-parse HEAD)
readarray -t PY_FILES_ARRAY < <(git ls-files '*.py')
readarray -t HTML_FILES_ARRAY < <(git ls-files '**/templates/**.html')
readarray -t PRETTIER_FILES_ARRAY < <(git ls-files '*.css' '*.js' '*.md' '*.ts')
readarray -t PRETTIER_FILES_ARRAY < <(find "${PRETTIER_FILES_ARRAY[@]}" -not -type l)
readarray -t SPELL_FILES_ARRAY < <(git ls-files)

if [ -f "$GOOD_FILE" ]; then
  if [ "$COMMIT_ID" == "$(cat "$GOOD_FILE")" ]; then
    echo -e "-----------------------------------------------------------------------"
    echo -e "\033[1;32m$COMMIT_ID\033[0m was marked all-OK, exiting..."
    echo -e "-----------------------------------------------------------------------"
    exit 0
  fi
fi

if [ -f "$BAD_FILE" ]; then
  if [ "$COMMIT_ID" == "$(cat "$BAD_FILE")" ]; then
    echo -e "-----------------------------------------------------------------------"
    echo -e "\033[1;33m$COMMIT_ID\033[0m was marked faulty, aborting..."
    echo -e "-----------------------------------------------------------------------"
    exit 1
  fi
fi

echo -e "-----------------------------------------------------------------------"
echo -e "\033[1;36mTesting $COMMIT_ID\033[0m"
echo -e "\033[1;34mWill check ${#PY_FILES_ARRAY[@]} Python files...\033[0m"
echo -e "-----------------------------------------------------------------------"

if [ "$1" == "--force" ]; then
  echo -e "\033[1;31m]$COMMIT_ID\033[0m not being compared to upstream"
  echo -e "---------------------------"
  echo -e ""
else
  echo -e "\033[1;35mChecking against upstream ...\033[0m"
  echo -e "---------------------------"
  git fetch
  if [ "$(git rev-list --count HEAD..@\{u\})" -gt 0 ]; then
    echo -e "$FAILED_HEADER Upstream is ahead of you"
    echo "$COMMIT_ID" >"$BAD_FILE"
    exit 1
  fi
  echo -e ""
fi

echo -e "\033[1;35mRunning poetry sync ...\033[0m"
echo -e "---------------------------"
if ! poetry sync; then
  echo -e "$FAILED_HEADER Dependency update failed"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mRunning spell-check ...\033[0m"
echo -e "---------------------------"
if ! codespell "${SPELL_FILES_ARRAY[@]}"; then
  echo -e "$FAILED_HEADER Spell-check failed"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mRunning manage.py check ...\033[0m"
echo -e "---------------------------"
if ! python manage.py check; then
  echo -e "$FAILED_HEADER python manage.py check failed"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mMaking migrations ...\033[0m"
echo -e "---------------------------"
if ! python manage.py makemigrations | grep "No changes detected"; then
  echo -e "$FAILED_HEADER I think you forgot a migration!"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
python manage.py migrate
echo -e ""

echo -e "\033[1;35mRunning ruff...\033[0m"
echo -e "---------------------------"
if ! ruff check --fix --exit-non-zero-on-fix "${PY_FILES_ARRAY[@]}"; then
  echo -e "$FAILED_HEADER Some files that needed in-place edits from ruff check, editing now..."
  echo -e "Please recommit and try again"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
if ! ruff format --diff "${PY_FILES_ARRAY[@]}"; then
  echo -e "$FAILED_HEADER Some files that needed in-place ruff format, editing now..."
  ruff format "${PY_FILES_ARRAY[@]}"
  echo -e "Please recommit and try again"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi

echo -e ""

echo -e "\033[1;35mRunning djlint ...\033[0m"
echo -e "---------------------------"
if ! djlint --check "${HTML_FILES_ARRAY[@]}"; then
  echo -e "$FAILED_HEADER djlint failed, editing files now"
  djlint --reformat --quiet "${HTML_FILES_ARRAY[@]}"
  echo -e "Please recommit and try again"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mRunning python manage.py validate_templates ...\033[0m"
echo -e "---------------------------"
if ! python manage.py validate_templates; then
  echo -e "$FAILED_HEADER Template errors were found"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mRunning prettier ...\033[0m"
echo -e "---------------------------"
if ! prettier --check "${PRETTIER_FILES_ARRAY[@]}"; then
  echo -e "$FAILED_HEADER prettier failed, re-running now"
  prettier --write "${PRETTIER_FILES_ARRAY[@]}"
  echo -e "Please recommit and try again"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mRunning pyright ...\033[0m"
echo -e "---------------------------"
if ! pyright; then
  echo -e "$FAILED_HEADER pyright failed"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "\033[1;35mRunning coverage/tests ...\033[0m"
echo -e "---------------------------"
if ! coverage run manage.py test --shuffle 1337; then
  echo -e "$FAILED_HEADER Unit tests did not check out"
  echo "$COMMIT_ID" >"$BAD_FILE"
  exit 1
fi
echo -e ""

echo -e "Generating coverage report ..."
coverage report -m --skip-empty --skip-covered
coverage html --skip-empty --skip-covered

echo -e "\033[1;32mAll checks passed\033[0m, saving this as a good commit"
echo "$COMMIT_ID" >"$GOOD_FILE"
exit 0
