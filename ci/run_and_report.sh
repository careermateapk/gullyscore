#!/usr/bin/env bash
# Runs a command; if it fails, puts the important error lines into one
# GitHub annotation so they are visible on the run's summary page.
set -o pipefail
"$@" 2>&1 | tee /tmp/step_output.txt
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  msg=$(grep -E "^\s*error •|^\s*warning •|lib/.*\.dart:[0-9]+:[0-9]+: Error|Error:|What went wrong|FAILURE|Some tests failed|version solving failed|Because |Expected:|Actual:|Exception" /tmp/step_output.txt \
    | head -60 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  java=$(grep -E -A4 "\.java:[0-9]+: error|^e: .*\.kt|Unresolved reference|cannot find symbol|Missing class|ERROR: R8|ERROR:.*R8" /tmp/step_output.txt \
    | head -40 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  [ -n "$java" ] && echo "::error title=Java/Kotlin errors::${java}"
  gradle=$(grep -E -A10 "What went wrong" /tmp/step_output.txt | head -40 | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  [ -n "$gradle" ] && echo "::error title=Gradle::${gradle}"
  [ -z "$msg" ] && msg=$(tail -40 /tmp/step_output.txt | sed 's/%/%25/g; s/\r//g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=Step failed::${msg}"
fi
exit "$code"
