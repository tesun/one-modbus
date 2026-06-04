#!/bin/bash
set -ex

VER="${CNB_BRANCH#v}"
FNAME="modbusrtu_broker_${VER}.exe"

P1=$(echo $VER | cut -d. -f1)
P2=$(echo $VER | cut -d. -f2)
P3=$(echo $VER | cut -d. -f3)

printf '{"FixedFileInfo":{"FileVersion":{"Major":%s,"Minor":%s,"Patch":%s,"Build":0},"ProductVersion":{"Major":%s,"Minor":%s,"Patch":%s,"Build":0},"FileFlagsMask":"3f","FileFlags":"00","FileOS":"040004","FileType":"01","FileSubType":"00"},"StringFileInfo":{"Comments":"get: gitee.com/dingjiazhi/one-modbus/releases","CompanyName":"DJ","FileDescription":"modbusrtu_broker","FileVersion":"%s.0","InternalName":"modbusrtu_broker","LegalCopyright":"Copyright 2026 DJ","OriginalFilename":"modbusrtu_broker.exe","ProductName":"one-modbus","ProductVersion":"%s.0"},"IconPath":"app.ico","ManifestPath":""}' \
  $P1 $P2 $P3 $P1 $P2 $P3 $VER $VER > /tmp/versioninfo.json
~/go/bin/goversioninfo -icon app.ico /tmp/versioninfo.json

export GOPROXY=https://goproxy.cn,direct
go mod init modbusrtu_broker 2>/dev/null
go mod tidy
CGO_ENABLED=1 GOOS=windows GOARCH=amd64 CC=x86_64-w64-mingw32-gcc \
  CGO_CFLAGS="-D_WIN32" CGO_LDFLAGS="-lws2_32" \
  go build -ldflags '-s -w -extldflags=-static' -o /tmp/$FNAME

ls -lh /tmp/$FNAME
echo "BUILD OK"

# Create Release with $CNB_TOKEN
python3 -c "
import json
body = json.dumps({
  'tag_name': '$CNB_BRANCH',
  'name': 'one-modbus $CNB_BRANCH',
  'body': '# one-modbus $CNB_BRANCH\n\n- Windows amd64 exe\n\nDownload: https://gitee.com/dingjiazhi/one-modbus/releases/tag/$CNB_BRANCH',
  'target_commitish': 'master'
})
print(body)
" > /tmp/release.json

RESP=$(curl -s -X POST "$CNB_API_ENDPOINT/$CNB_REPO_SLUG/-/releases" \
  -H "Authorization: Bearer $CNB_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/vnd.cnb.api+json" \
  --data-binary @/tmp/release.json)

RID=$(echo $RESP | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
echo "Release ID: $RID"
[ -n "$RID" ] || { echo "RELEASE FAIL: $RESP"; exit 1; }

SZ=$(stat -c%s /tmp/$FNAME)
python3 -c "
import json
print(json.dumps({'asset_name': '$FNAME', 'size': $SZ, 'overwrite': True}))
" > /tmp/asset.json

URESP=$(curl -s -X POST "$CNB_API_ENDPOINT/$CNB_REPO_SLUG/-/releases/$RID/asset-upload-url" \
  -H "Authorization: Bearer $CNB_TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/vnd.cnb.api+json" \
  --data-binary @/tmp/asset.json)

UURL=$(echo $URESP | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))")
[ -n "$UURL" ] && curl -s -X PUT "$UURL" -H "Content-Type: application/octet-stream" --data-binary @/tmp/$FNAME
echo "OK: https://cnb.cool/$CNB_REPO_SLUG/releases/tag/$CNB_BRANCH"
