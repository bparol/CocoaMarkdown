#!/usr/bin/env bash

xcodebuild archive \
 -scheme CocoaMarkdown-iOS \
 -archivePath build/iphonesimulator \
 -sdk iphonesimulator \
 SKIP_INSTALL=NO | xcpretty

 xcodebuild archive \
 -scheme CocoaMarkdown-iOS \
 -archivePath  build/iphoneos \
 -sdk iphoneos \
 SKIP_INSTALL=NO | xcpretty

 xcodebuild -create-xcframework \
 -framework build/iphoneos.xcarchive/Products/Library/Frameworks/CocoaMarkdown.framework \
 -framework build/iphonesimulator.xcarchive/Products/Library/Frameworks/CocoaMarkdown.framework \
 -output build/CocoaMarkdown.xcframework
