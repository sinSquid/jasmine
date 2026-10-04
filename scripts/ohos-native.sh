#!/bin/sh
set -eu
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OHOS_PATH="$PROJECT_DIR/native/jmbackend/platforms/ohos"
test -d "$OHOS_PATH"
cd "$OHOS_PATH"
make
test -d dist
mkdir -p "$PROJECT_DIR/ohos/entry/libs"
rsync -av --exclude oh-package.json5 "$OHOS_PATH/dist/" "$PROJECT_DIR/ohos/entry/libs/"
