#!/bin/bash
# 精簡版的 GStreamer 打包腳本
# 只包含 FFXIV 過場動畫所需的最小插件集

nixResult="result"
sourceDir="$nixResult/nix/store"
targetDir="../wine"
overridesDir="overrides"
receipt="packaged-nix-output"

if [[ ! -d $sourceDir ]]; then
    echo "warning: Nix build did not succeed. No runtime to package."
    cd "$PROJECT_DIR"/XIV\ on\ Mac/
    [ -d "wine" ] && exit 0
    echo "note: No prexisting wine package. Attempting archive download..."
    curl -LO https://github.com/cycleapple/XIV-on-Mac-in-TC/releases/download/ff-wine-10.0.0-optimized/wine-optimized.tar.xz
    tar -xf wine-optimized.tar.xz
    rm wine-optimized.tar.xz
    exit 0
fi

if [[ ! -L "$nixResult" ]]; then
  echo "error: Nix build failed."
  exit 1
fi

nixResultTarget=$(readlink "$nixResult")

if [[ -e "$receipt" && -d "$targetDir" ]]; then
  current_content=$(<"$receipt")
  if [[ "$current_content" == "$nixResultTarget" ]]; then
    echo "note: The last built wine package matches the current one. No changes made."
    exit 0
  fi
fi

echo "$nixResultTarget" > "$receipt"
echo "note: Updated receipt $receipt with Nix store result: $nixResultTarget"
echo "note: Packaging wine with minimal GStreamer plugins..."

subDir=$(find $sourceDir -type d -mindepth 1 -maxdepth 1 | head -n 1)

rm -rf $targetDir
mkdir -p $targetDir
cp -R "$subDir/"* $targetDir
chmod -R u+w $targetDir
rsync -a "$overridesDir/lib" $targetDir

libDir="$targetDir/lib"
mkdir -p "$libDir"
processedLibs=("libMoltenVK.dylib")

# Strip existing code signatures before modifying binaries to avoid warnings
# install_name_tool will otherwise print that changes invalidate the signature.
find "$targetDir" -type f \
    \( -name "*.dylib" -o -name "*.so" -o -perm -111 \) \
    -exec sh -c 'codesign --remove-signature "$1" 2>/dev/null || true' _ {} \;

is_processed() {
    local libName=$1
    for processedLib in "${processedLibs[@]}"; do
        if [[ "$processedLib" == "$libName" ]]; then
            return 0
        fi
    done
    return 1
}

extract_rpaths() {
    local file=$1
    otool -l "$file" | awk '/cmd LC_RPATH/ { getline; getline; if($2 ~ /\/nix\/store/) print $2 }'
}

extract_dependencies() {
    local dylib=$1
    otool -l "$dylib" | awk '/cmd LC_LOAD_DYLIB/ { getline; getline; if($2 ~ /\/nix\/store/ && $2 ~ /\.dylib$/) print $2 }'
}

resolve_symlink_path() {
    local symlinkPath=$1
    local symlinkDir=$(dirname "$symlinkPath")
    local symlinkBaseName=$(basename "$(readlink "$symlinkPath")")
    echo "$(cd "$symlinkDir" && pwd -P)/$symlinkBaseName"
}

remove_nix_rpaths() {
    local file=$1
    local rpaths_to_remove=$(otool -l "$file" | awk '/cmd LC_RPATH/ { getline; getline; if($2 ~ /\/nix\/store/) print $2 }')

    for rpath in $rpaths_to_remove; do
        install_name_tool -delete_rpath "$rpath" "$file"
    done
}

process_dylib_dependecy() {
    local dylibPath=$1
    local dylibName=$(basename "$dylibPath")

    if is_processed "$dylibName"; then
        return 0
    fi
    processedLibs+=("$dylibName")

    if [[ -L "$dylibPath" ]]; then
        local targetName=$(readlink "$dylibPath")
        ln -s "$targetName" "$libDir/$dylibName"
        process_dylib_dependecy "$(resolve_symlink_path "$dylibPath")"
        return
    else
        cp "$dylibPath" "$libDir"
        chmod +w "$libDir/$dylibName"
        install_name_tool -id "@rpath/$dylibName" "$libDir/$dylibName"
    fi

    local dependencies=$(extract_dependencies "$libDir/$dylibName")
    for dep in $dependencies; do
        local depName=$(basename "$dep")
        install_name_tool -change "$dep" "@rpath/$depName" "$libDir/$dylibName"
        process_dylib_dependecy "$dep"
    done

    local dylibRpaths=$(extract_rpaths "$libDir/$dylibName")
    while read -r rpath; do
        if [[ -d "$rpath" ]]; then
            for dep in "$rpath"/*.dylib; do
                if [[ -f "$dep" ]]; then
                    local depName=$(basename "$dep")
                    install_name_tool -change "$dep" "@rpath/$depName" "$libDir/$dylibName"
                    process_dylib_dependecy "$dep"
                fi
            done
        fi
    done <<< "$dylibRpaths"

    remove_nix_rpaths "$libDir/$dylibName"
}

process_binary() {
    local binaryPath=$1
    local binaryName=$(basename "$binaryPath")

    install_name_tool -id "$binaryName" "$binaryPath"

    local dependencies=$(extract_dependencies "$binaryPath")
    for dep in $dependencies; do
        local depName=$(basename "$dep")
        install_name_tool -change "$dep" "@rpath/$depName" "$binaryPath"
        process_dylib_dependecy "$dep"
    done

    local binaryRpaths=$(extract_rpaths "$binaryPath")
    while read -r rpath; do
        if [[ -d "$rpath" ]]; then
            for dep in "$rpath"/*.dylib; do
                if [[ -f "$dep" ]]; then
                    local depName=$(basename "$dep")
                    install_name_tool -change "$dep" "@rpath/$depName" "$binaryPath"
                    process_dylib_dependecy "$dep"
                fi
            done
        fi
    done <<< "$binaryRpaths"

    remove_nix_rpaths "$binaryPath"

    install_name_tool -add_rpath "@executable_path/../lib" "$binaryPath"
    install_name_tool -add_rpath "@loader_path/../.." "$binaryPath"
}

find "$targetDir" -type f | while read file; do
    if [[ -d "$file" ]]; then
        continue
    fi
    if [[ "$file" == *".dylib" || "$file" == *".so" || -x "$file" ]]; then
        process_binary "$file"
    fi
done

# Copy GStreamer core libraries first - 這些是所有插件的依賴
echo "note: Copying GStreamer core libraries..."
for gstLibStore in /nix/store/*gstreamer-*/lib /nix/store/*gst-plugins-*/lib; do
    if [[ -d "$gstLibStore" ]]; then
        for gstLib in "$gstLibStore"/libgst*.dylib; do
            if [[ -f "$gstLib" && ! -L "$gstLib" ]]; then
                gstLibName=$(basename "$gstLib")
                if [[ ! -f "$libDir/$gstLibName" ]]; then
                    echo "note: Copying core library: $gstLibName"
                    cp "$gstLib" "$libDir/"
                    chmod +w "$libDir/$gstLibName"
                    codesign --remove-signature "$libDir/$gstLibName" 2>/dev/null || true
                    process_dylib_dependecy "$gstLib"
                fi
            fi
        done
    fi
done

# Copy minimal GStreamer plugins - 只包含視頻播放必需的插件
echo "note: Copying minimal GStreamer plugins for video playback..."
gstPluginDir="$libDir/gstreamer-1.0"
mkdir -p "$gstPluginDir"

# 定義 FFXIV 過場動畫所需的最小插件集
# 這些插件足以支持常見的視頻格式 (H.264/HEVC in AVI/MP4)
REQUIRED_PLUGINS=(
    # 核心插件
    "libgstcoreelements.dylib"     # 基礎元素 (filesrc, typefind 等)
    "libgstplayback.dylib"         # 播放支援

    # 容器格式
    "libgstasf.dylib"              # ASF/WMV 容器 (FFXIV 過場動畫)
    "libgstavi.dylib"              # AVI 容器
    "libgstisomp4.dylib"           # MP4/MOV 容器
    "libgstmatroska.dylib"         # MKV 容器 (備用)
    "libaom.3.dylib"               # AV1 解碼器 (備用)

    # 視頻解碼 (基礎)
    "libgstlibav.dylib"            # FFmpeg 解碼器 (支持 H.264/HEVC/VC-1/WMA 等)
    "libgstvideoparsersbad.dylib"  # 視頻解析器
    "libgstdeinterlace.dylib"      # 視頻去交錯

    # 音頻解碼 (基礎)
    "libgstaudioparsers.dylib"     # 音頻解析器
    "libgstaudioconvert.dylib"     # 音頻轉換
    "libgstaudioresample.dylib"    # 音頻重採樣

    # 類型檢測
    "libgsttypefindfunctions.dylib" # 自動檢測檔案類型

    # 視頻處理
    "libgstvideoconvertscale.dylib" # 視頻縮放和轉換
    "libgstvideofilter.dylib"       # 視頻濾鏡 (包含 videoflip)
)

for pluginStore in /nix/store/*gstreamer-*/lib/gstreamer-1.0 /nix/store/*gst-plugins-*/lib/gstreamer-1.0 /nix/store/*gst-libav-*/lib/gstreamer-1.0; do
    if [[ -d "$pluginStore" ]]; then
        for requiredPlugin in "${REQUIRED_PLUGINS[@]}"; do
            plugin="$pluginStore/$requiredPlugin"
            if [[ -f "$plugin" && ! -L "$plugin" ]]; then
                pluginName=$(basename "$plugin")
                if [[ ! -f "$gstPluginDir/$pluginName" ]]; then
                    echo "note: Copying required plugin: $pluginName"
                    cp "$plugin" "$gstPluginDir/"
                    chmod +w "$gstPluginDir/$pluginName"
                    codesign --remove-signature "$gstPluginDir/$pluginName" 2>/dev/null || true
                    process_binary "$gstPluginDir/$pluginName"
                fi
            fi
        done
    fi
done

echo "note: Packaged $(ls -1 "$gstPluginDir" | wc -l) GStreamer plugins (minimal set)"
