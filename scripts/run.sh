#!/bin/bash
FLAVOR=$1
if [ -z "$FLAVOR" ]; then
    echo "Usage: ./run.sh [flavor]"
    exit 1
fi
flutter run --flavor $FLAVOR -t lib/main/main_$FLAVOR.dart
