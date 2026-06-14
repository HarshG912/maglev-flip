#!/bin/bash

# 1. Download the stable Flutter SDK into Vercel's temporary environment
echo "Downloading Flutter SDK..."
git clone https://github.com/flutter/flutter.git -b stable

# 2. Add Flutter to Vercel's execution path
export PATH="$PATH:`pwd`/flutter/bin"

# 3. Enable web support (just in case)
flutter config --enable-web

# 4. Fetch your project dependencies
flutter pub get

# 5. Build the high-performance web version of Maglev Flip
echo "Building the Vibe Engine..."
flutter build web --release