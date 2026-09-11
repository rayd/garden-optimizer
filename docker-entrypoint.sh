#!/bin/bash
set -e

# Script to run migrations and start the application

case "$1" in
  migrate)
    echo "Running migrations..."
    exec ./bin/garden_optimizer eval "GardenOptimizer.Release.migrate"
    ;;
  seed)
    echo "Running seeds..."
    exec ./bin/garden_optimizer eval "GardenOptimizer.Release.seed"
    ;;
  start)
    echo "Starting Garden Optimizer..."
    exec ./bin/garden_optimizer start
    ;;
  *)
    exec ./bin/garden_optimizer "$@"
    ;;
esac
