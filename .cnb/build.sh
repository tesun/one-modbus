#!/bin/bash
# CNB 构建脚本 - one-modbus
set -ex

VER="${CNB_BRANCH#v}"
REPO="$CNB_REPO_SLUG"
FNAME="modbusrtu_broker_${VER}.exe"

# 生成 versioninfo.json
P1=$(echo $VER | cut -d. -f1)
P2=$(echo $VER | cut -d. -f2)
P3=$(echo $VER | cut -d. -f3)
printf '{"FixedFileInfo":{"FileVersion":{"Major":%s,"Minor":%s,"Patch":%s,"Build":0},"ProductVersion":{"Major":%s,"Minor":%s,"Patch":%s,"Build":0},"FileFlagsMask":"3f","FileFlags":"00","FileOS":"040004","FileType":"01","FileSubType":"00"},"StringFileInfo":{"Comments":"get: gitee.com/dingjiazhi/one-modbus/releases","CompanyName":"DJ","FileDescription":"modbusrtu_broker","FileVersion":"%s.0","InternalName":"modbusrtu_broker","LegalCopyright":"Copyright 2026 DJ","OriginalFilename":"modbusrtu_broker.exe","ProductName":"one-modbus","ProductVersion":"%s.0"},"IconPath":"app.ico","ManifestPath":""}' \
  $P1 $P2 $P3 $P1 $P2 $P3 $VER $VER > /tmp/versioninfo.json
~/go/bin/goversioninfo -icon app.ico /tmp/versioninfo.json

# 编译
export GOPROXY=https://goproxy.cn,direct
go mod init modbusrtu_broker 2>/dev/null
go mod tidy
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
  CGO_CFLAGS="-D_WIN32" CGO_LDFLAGS="-lws2_32" \
  go build -ldflags '-s -w -extldflags=-static' -o /tmp/$FNAME
ls -lh /tmp/$FNAME

# 创建 Release
BODY=$(printf '{"tag_name":"%s","name":"one-modbus %s","body":"# one-modbus %s\\n\\nDownload: https://gitee.com/dingjiazhi/one-modbus/releases/tag/%s","target_commitish":"master"}' \
  "$CNB_BRANCH" "$CNB_BRANCH" "$CNB_BRANCH" "$CNB_BRANCH")
RESP=$(curl -s -X POST "$CNB_API_ENDPOINT/$REPO/-/releases" \
  -H "Authorization: Bearer $CNB_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/vnd.cnb.api+json" -d "$BODY")
RID=$(echo $RESP | jq -r '.id // empty')
[ -n "$RID" ] || { echo "RELEASE FAIL: $RESP"; exit 1; }

# 上传 exe
SZ=$(stat -c%s /tmp/$FNAME)
URESP=$(curl -s -X POST "$CNB_API_ENDPOINT/$REPO/-/releases/$RID/asset-upload-url" \
  -H "Authorization: Bearer $CNB_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/vnd.cnb.api+json" \
  -d "{\"asset_name\":\"$FNAME\",\"size\":$SZ,\"overwrite\":true}")
UURL=$(echo $URESP | jq -r '.url // empty')
[ -n "$UURL" ] && curl -s -X PUT "$UURL" -H "Content-Type: application/octet-stream" --data-binary @/tmp/$FNAME
echo "OK: https://cnb.cool/$REPO/releases/tag/$CNB_BRANCH"
