echo Building Twin Stick

OSX_LD_FLAGS="-framework AppKit
-framework IOKit"

mkdir ../../build
pushd ../../build
rm -rf twinstick.app
mkdir -p twinstick.app
clang -g -std=c++11 $OSX_LD_FLAGS -o twinstick ../twinstick/code/osx_main.mm
cp twinstick twinstick.app/twinstick
cp "../twinstick/resources/info.plist" twinstick.app/info.plist
popd
