#!/bin/bash

# Build the application
xcodebuild -scheme PowerUserMail -configuration Debug -destination 'platform=macOS' -derivedDataPath build

# Check if build succeeded
if [ $? -eq 0 ]; then
    echo "Build succeeded. Running PowerUserMail..."
    # Run the application
    open build/Build/Products/Debug/PowerUserMail.app
else
    echo "Build failed."
    exit 1
fi
