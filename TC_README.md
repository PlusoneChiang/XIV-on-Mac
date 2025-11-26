# XIV on Mac for TC

TC fork of XIV on Mac.

build with

```sh
xcodebuild -project "XIV on Mac.xcodeproj" -scheme "XIV on Mac" \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES build
```

debug with

```sh
xcodebuild -project "XIV on Mac.xcodeproj" -scheme "XIV on Mac" \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=YES build
```
