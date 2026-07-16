# v5 変更点 (ビルドエラー修正)

## v4 のビルドエラー原因

```
error: cannot find 'RTF_GATEWAY' in scope
error: cannot find type 'rt_msghdr' in scope
error: cannot find 'RTA_DST' in scope
error: cannot find 'RTA_GATEWAY' in scope
```

Swift の Darwin モジュールでは、`CTL_NET`, `PF_ROUTE`, `AF_INET`, `NET_RT_DUMP` などの
上位レベル定数は自動 import されているが、`<net/route.h>` の中身
(`rt_msghdr`, `RTF_GATEWAY`, `RTA_DST` 等) は自動 import されていない。

## v5 の変更

### 1. Bridging Header を追加
新規ファイル: `FCReborn/FCReborn-Bridging-Header.h`

```c
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <arpa/inet.h>
```

これで `<net/route.h>` の定義が Swift から見えるようになる。

### 2. project.yml 更新
```yaml
settings:
  base:
    SWIFT_OBJC_BRIDGING_HEADER: "FCReborn/FCReborn-Bridging-Header.h"
```

`xcodegen generate` で正しく Xcode project に反映される。

### 3. WiFiHelper.swift のライフタイム安全性を改善
`withUnsafeBufferPointer` のクロージャの中で route table のパースを完結させた。
クロージャの外にポインタを持ち出さないようにしてクラッシュリスクを回避。

### 4. Version bump
- Marketing: `1.3.0` → `1.4.0`
- Build: `4` → `5`
- AppVersion.buildTag: `"v1.4.0 (build 5) [FCReborn v5]"`

## v5 で必ずビルドが通ってほしいポイント

- Bridging Header の path が正しく解決される (`FCReborn/FCReborn-Bridging-Header.h`)
- `<net/route.h>` の API は iOS SDK でも使える (太古の BSD API、iOS でも継続利用可)

## ビルド後の期待動作

v4 と同じ:
1. `全 IPv4 インターフェース:` 一覧が出る
2. `gateway 候補一覧: <実際の gateway>, ...` が出る
3. `[試行1] TCP → <実際の gateway>:3290` で成功

もし PF_ROUTE で取れた本物の gateway が `10.172.239.1` 以外なら根本原因確定。
