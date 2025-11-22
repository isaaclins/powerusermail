#!/bin/bash

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is required but not found."
    exit 1
fi

# Run the Python dev runner
python3 dev_runner.py
